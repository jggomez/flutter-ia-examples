"""Gemini as a *writer*: structured data and copy only, never UI.

Every call uses `response_schema`, so Gemini returns a typed object that code
places into components the surface builders already chose. Gemini never sees
the catalog and never emits A2UI.
"""

from __future__ import annotations

import logging
import os
from typing import Any, Protocol

from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

WRITER_MODEL = os.getenv("WRITER_MODEL", "gemini-3.8-flash")


class ItemAttributes(BaseModel):
    brand: str = Field(description="Brand or manufacturer, e.g. 'Mazda'.")
    model: str = Field(description="Model name, e.g. 'CX-30'.")
    year: str = Field(description="Estimated model year or generation, e.g. '2021'.")
    color: str = Field(description="Exterior color or finish.")
    summary: str = Field(description="One short sentence describing the item's look.")


class OdometerReading(BaseModel):
    raw_reading_text: str = Field(
        description="Digits exactly as shown, e.g. '034,200'."
    )
    unit: str = Field(description="'km' or 'mi'.")


class ListingCopy(BaseModel):
    title: str = Field(description="Marketplace title, at most 70 characters.")
    description: str = Field(description="2-3 honest sentences for buyers.")
    rationale: str = Field(description="One sentence explaining the price range.")


class Writer(Protocol):
    async def describe_item(self, photo: bytes) -> ItemAttributes: ...

    async def read_odometer(self, photo: bytes) -> OdometerReading: ...

    async def write_listing(self, facts: dict[str, Any]) -> ListingCopy: ...


class GeminiWriter:
    """`Writer` backed by `google-genai` (Vertex AI or AI Studio, from env)."""

    def __init__(self, model: str = WRITER_MODEL) -> None:
        self._model = model
        self._client: Any = None

    def _get_client(self) -> Any:
        if self._client is None:
            from google import genai

            self._client = genai.Client()
        return self._client

    async def _generate(
        self, contents: list[Any], schema: type[BaseModel]
    ) -> BaseModel:
        from google.genai import types

        response = await self._get_client().aio.models.generate_content(
            model=self._model,
            contents=contents,
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=schema,
                temperature=0.2,
            ),
        )
        if isinstance(response.parsed, schema):
            return response.parsed
        return schema.model_validate_json(response.text or "{}")

    @staticmethod
    def _image(photo: bytes) -> Any:
        from google.genai import types

        mime = "image/png" if photo.startswith(b"\x89PNG") else "image/jpeg"
        return types.Part.from_bytes(data=photo, mime_type=mime)

    async def describe_item(self, photo: bytes) -> ItemAttributes:
        result = await self._generate(
            [
                self._image(photo),
                "The photo shows an item for sale. Identify it for a "
                "marketplace listing. Use an empty string when a value is not visible.",
            ],
            ItemAttributes,
        )
        assert isinstance(result, ItemAttributes)
        return result

    async def read_odometer(self, photo: bytes) -> OdometerReading:
        result = await self._generate(
            [self._image(photo), "Read the odometer (total distance) in this photo."],
            OdometerReading,
        )
        assert isinstance(result, OdometerReading)
        return result

    async def write_listing(self, facts: dict[str, Any]) -> ListingCopy:
        result = await self._generate(
            [
                "Write marketplace copy for this item. Use only these facts, do not "
                f"invent features:\n{facts}"
            ],
            ListingCopy,
        )
        assert isinstance(result, ListingCopy)
        return result
