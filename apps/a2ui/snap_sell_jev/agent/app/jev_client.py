"""Thin async wrapper around TypeSafe's Jev decision model (`typesafe-sdk`).

Jev never writes text or JSON. It answers named questions about a `state`
(text, a JSON object, or an image) with calibrated probabilities:

* `noul`   -> probability that the statement is true (0..1)
* `choice` -> the chosen option plus a probability per option
* `score`  -> a distribution over ordered levels (we use the expected level)

All questions of one call are answered in parallel by a single request
(~100-300 ms). This module only transports questions and answers; what to ask
and how to act on the answers lives in `app.decisions`.
"""

# demo-data: approved — the DecisionEngine protocol docstring mentions the scripted test stand-in; production uses TypeSafeJev.

from __future__ import annotations

import io
import logging
import os
from dataclasses import dataclass, field
from typing import Any, Protocol

logger = logging.getLogger(__name__)

DEFAULT_JEV_MODEL = "jev-latest"
DEFAULT_TIMEOUT_S = 5.0
# Image assets are experimental in Jev; the API rejects them without this opt-in.
IMAGE_OPT_IN_HEADERS = {"TypeSafe-Danger-Zone-Images": "true"}
# Jev rejects images outside roughly 384-1536 px ("Invalid image dimensions"),
# and phone photos are usually 3000+ px, so every photo is fitted to this box.
JEV_IMAGE_MAX_SIDE = 1024
JEV_IMAGE_MIN_SIDE = 384


def fit_photo_for_jev(photo: bytes) -> bytes:
    """Return a JPEG whose sides lie within Jev's accepted range, keeping aspect."""
    from PIL import Image as PILImage
    from PIL import ImageOps

    with PILImage.open(io.BytesIO(photo)) as img:
        img = ImageOps.exif_transpose(img).convert("RGB")
        scale = min(1.0, JEV_IMAGE_MAX_SIDE / max(img.size))
        if min(img.size) * scale < JEV_IMAGE_MIN_SIDE:
            scale = JEV_IMAGE_MIN_SIDE / min(img.size)
        if scale != 1.0:
            size = (round(img.width * scale), round(img.height * scale))
            img = img.resize(size, PILImage.Resampling.LANCZOS)
        out = io.BytesIO()
        img.save(out, format="JPEG", quality=85)
        return out.getvalue()


class JevUnavailableError(RuntimeError):
    """Jev cannot answer (no API key, network or API error). Never guessed around."""


@dataclass(frozen=True)
class JevAnswer:
    """One answer, normalized across the three question types."""

    kind: str
    #: noul: P(true). choice: probability of the chosen option. score: confidence.
    probability: float
    #: choice only: the option Jev picked.
    choice: str | None = None
    #: choice: option -> p. score: level index (as str) -> p.
    probabilities: dict[str, float] = field(default_factory=dict)

    @property
    def expected_level(self) -> float:
        """score only: expected level index (0 = first criterion)."""
        return sum(int(k) * p for k, p in self.probabilities.items())

    def ranked(self) -> list[str]:
        """choice only: options from most to least likely."""
        return sorted(
            self.probabilities, key=self.probabilities.__getitem__, reverse=True
        )


class DecisionEngine(Protocol):
    """What the flow needs from Jev. Tests provide a scripted fake."""

    async def ask(
        self,
        state: dict[str, Any],
        questions: dict[str, dict[str, Any]],
        *,
        photo: bytes | None = None,
    ) -> dict[str, JevAnswer]: ...


def _normalize(answer: Any) -> JevAnswer:
    kind = getattr(answer, "type", "")
    if kind == "noul":
        return JevAnswer(kind="noul", probability=float(answer.noul))
    if kind == "choice":
        return JevAnswer(
            kind="choice",
            probability=float(answer.confidence),
            choice=str(answer.choice),
            probabilities={str(k): float(v) for k, v in answer.probabilities.items()},
        )
    if kind == "score":
        return JevAnswer(
            kind="score",
            probability=float(answer.confidence),
            probabilities={str(k): float(v) for k, v in answer.probabilities.items()},
        )
    raise JevUnavailableError(f"Unsupported Jev answer type: {kind!r}")


class TypeSafeJev:
    """`DecisionEngine` backed by the TypeSafe System One API."""

    def __init__(
        self,
        api_key: str | None = None,
        model: str | None = None,
        timeout: float = DEFAULT_TIMEOUT_S,
    ) -> None:
        self._api_key = (
            api_key or os.getenv("JEV_API_KEY") or os.getenv("TYPESAFE_API_KEY")
        )
        self._model = model or os.getenv("JEV_MODEL", DEFAULT_JEV_MODEL)
        self._timeout = timeout
        self._client: Any = None

    def _get_client(self) -> Any:
        if not self._api_key:
            raise JevUnavailableError(
                "JEV_API_KEY is not set. Create a key at https://console.typesafe.ai/keys "
                "and add it to agent/.env."
            )
        if self._client is None:
            from typesafe_sdk import AsyncTypeSafeClient

            self._client = AsyncTypeSafeClient(
                api_key=self._api_key,
                model=self._model,
                timeout=self._timeout,
                headers=IMAGE_OPT_IN_HEADERS,
            )
        return self._client

    async def ask(
        self,
        state: dict[str, Any],
        questions: dict[str, dict[str, Any]],
        *,
        photo: bytes | None = None,
    ) -> dict[str, JevAnswer]:
        from typesafe_sdk import Image, TypeSafeError

        client = self._get_client()
        request_state: dict[str, Any] = dict(state)
        if photo:
            # The SDK sends the image as a multipart asset and puts its reference here.
            request_state["photo"] = Image(fit_photo_for_jev(photo))
        try:
            response = await client.system_one(state=request_state, questions=questions)
        except TypeSafeError as exc:
            raise JevUnavailableError(f"Jev request failed: {exc}") from exc
        answers = {name: _normalize(a) for name, a in response.answers.items()}
        missing = set(questions) - set(answers)
        if missing:
            raise JevUnavailableError(f"Jev did not answer: {sorted(missing)}")
        return answers
