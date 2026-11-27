"""The selling wizard as a state machine: Jev decides, Gemini writes, code assembles.

One call to `SellingFlow.handle` is one A2A turn. Per stage it:
1. asks Jev its questions and Gemini its writing task *in parallel*,
2. turns Jev's probabilities into decisions (`app.decisions`),
3. runs the deterministic business rules (`app.tools`, shared with the Express agent),
4. assembles the next A2UI v1.0 surface (`app.surfaces`).

No LLM ever writes UI here, so there is nothing to repair: a surface either
validates in `surfaces._surface` or the turn fails loudly in tests.
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from dataclasses import dataclass, field
from typing import Any

from app import decisions, field_bank, surfaces, tools
from app.jev_client import DecisionEngine, JevUnavailableError
from app.writer import ItemAttributes, Writer

logger = logging.getLogger(__name__)

@dataclass
class TurnInput:
    action: dict[str, Any] | None = None
    photo: bytes | None = None
    image_url: str | None = None


@dataclass
class TurnOutput:
    messages: list[dict[str, Any]] = field(default_factory=list)
    text: str = ""
    #: Jev decisions of this turn, for the client's trace panel and the logs.
    trace: list[dict[str, Any]] = field(default_factory=list)
    #: Session state keys to persist (ADK `state_delta`).
    state: dict[str, Any] = field(default_factory=dict)


class _StateContext:
    """Minimal stand-in for ADK's ToolContext so `app.tools` can be reused as-is."""

    def __init__(self, state: dict[str, Any]) -> None:
        self.state = state


_DETECTED_KEYS = ("category", "isEv", "brand", "model", "year", "color")


class SellingFlow:
    def __init__(self, jev: DecisionEngine, writer: Writer) -> None:
        self._jev = jev
        self._writer = writer

    async def handle(self, state: dict[str, Any], turn: TurnInput) -> TurnOutput:
        st: dict[str, Any] = json.loads(json.dumps(dict(state), default=str))
        st.setdefault("listing_draft", {})
        out = TurnOutput()
        name = (turn.action or {}).get("name")
        ctx = dict((turn.action or {}).get("context") or {})
        try:
            if name is None:
                if turn.photo:
                    await self._on_item_photo(st, turn, out)
                else:
                    out.text = (
                        "Send a photo of a car, motorcycle, or smartphone to start."
                    )
            elif name == "submit_detected_details":
                await self._on_details(st, ctx, out)
            elif name == "request_odometer_scan":
                st["need_odometer"] = True
                st.setdefault("need_damage", False)
                self._render_followup(st, out, [])
            elif name == "upload_followup_photo":
                await self._on_followup_photo(st, ctx, turn, out)
            elif name == "submit_followup":
                await self._on_followup_submit(st, ctx, out)
            elif name == "publish_listing":
                self._on_publish(st, ctx, out)
            else:
                out.text = f"Unknown action '{name}'."
        except JevUnavailableError as exc:
            logger.error("Jev unavailable: %s", exc)
            out.messages = []
            out.text = f"Jev could not decide this step: {exc}"
            return out
        out.state = {
            k: st[k]
            for k in (
                "listing_draft",
                "stage",
                "jev_photo",
                "condition_level",
                "plausibility_warned",
                "need_odometer",
                "need_damage",
                "form_fields",
            )
            if k in st
        }
        return out

    async def _ask(
        self,
        out: TurnOutput,
        stage: str,
        state: dict[str, Any],
        questions: dict[str, dict[str, Any]],
        photo: bytes | None = None,
    ) -> dict[str, Any]:
        started = time.perf_counter()
        answers = await self._jev.ask(state, questions, photo=photo)
        logger.info(
            "Jev %s answered %d questions in %.0f ms",
            stage,
            len(questions),
            (time.perf_counter() - started) * 1000,
        )
        return answers

    @staticmethod
    def _record(
        out: TurnOutput, stage: str, entries: list[decisions.TraceEntry]
    ) -> None:
        out.trace.extend({"stage": stage, **e.to_dict()} for e in entries)

    # -- Stage 1 ------------------------------------------------------------

    async def _on_item_photo(
        self, st: dict[str, Any], turn: TurnInput, out: TurnOutput
    ) -> None:
        assert turn.photo is not None
        jev_task = self._ask(
            out,
            "photo",
            {"task": "Classify the photo of an item someone wants to sell."},
            decisions.photo_questions(),
            photo=turn.photo,
        )
        jev_answers, attrs = await asyncio.gather(
            jev_task, self._writer.describe_item(turn.photo), return_exceptions=True
        )
        if isinstance(jev_answers, BaseException):
            raise jev_answers
        decision = decisions.decide_photo(jev_answers)
        self._record(out, "photo", decision.trace)

        if decision.category == "unsupported":
            st["stage"] = "selling_unsupported"
            out.messages = surfaces.unsupported()
            out.text = "Jev could not match the photo to a supported category."
            return

        form = decisions.decide_form(jev_answers, decision)
        self._record(out, "form", form.trace)
        notices: list[str] = list(form.notices)
        if isinstance(attrs, BaseException):
            logger.warning("Gemini could not describe the item: %s", attrs)
            attrs = ItemAttributes(brand="", model="", year="", color="", summary="")
            notices.append("We could not read the item details. Please fill them in.")
        if decision.retake_hint:
            notices.append(
                "Jev thinks this photo is hard to read. A sharper photo gets better offers."
            )

        result = tools.record_detected_item(
            category=decision.category,
            brand=attrs.brand,
            model=attrs.model,
            year_or_generation=attrs.year,
            color=attrs.color,
            condition_summary=attrs.summary,
            confidence=decision.confidence,
            is_ev=decision.is_ev,
            visible_damage=decision.has_damage,
            image_url=turn.image_url or "",
            tool_context=_StateContext(st),  # type: ignore[arg-type]
        )
        st["jev_photo"] = {
            "category": decision.category,
            "isEv": decision.is_ev,
            "confidence": decision.confidence,
        }
        st.pop("plausibility_warned", None)
        st["form_fields"] = form.fields
        details = field_bank.default_details(form.fields, has_damage=decision.has_damage)
        out.messages = surfaces.detected(
            category=decision.category,
            confidence=decision.confidence,
            is_ev=decision.is_ev,
            fields=form.fields,
            item={
                "imageUrl": result["image_url"],
                "summary": result["condition_summary"],
                "brand": attrs.brand,
                "model": attrs.model,
                "year": attrs.year,
                "color": attrs.color,
            },
            details=details,
            notices=notices,
        )
        out.text = (
            f"Jev: {decision.category} ({decision.confidence:.0%})"
            f"{', EV' if decision.is_ev else ''}{', visible damage' if decision.has_damage else ''}."
        )

    def _rerender_detected(
        self,
        st: dict[str, Any],
        ctx: dict[str, Any],
        notices: list[str],
        out: TurnOutput,
    ) -> None:
        photo = st.get("jev_photo", {})
        draft = st["listing_draft"]
        category = photo.get("category", draft.get("category", "car"))
        is_ev = bool(photo.get("isEv", False))
        fields = st.get("form_fields") or field_bank.assemble(
            category, is_ev, [], damage_first=False
        )
        details = field_bank.default_details(
            fields, has_damage=bool(ctx.get("hasDamage", False))
        )
        details.update({k: v for k, v in ctx.items() if k in details})
        out.messages = surfaces.detected(
            category=category,
            confidence=float(photo.get("confidence", draft.get("confidence", 0.0))),
            is_ev=is_ev,
            fields=fields,
            item={
                "imageUrl": draft.get("imageUrl", ""),
                "summary": draft.get("summary", ""),
                **{
                    k: ctx.get(k, draft.get(k, ""))
                    for k in ("brand", "model", "year", "color")
                },
            },
            details=details,
            notices=notices,
        )
        st["stage"] = "selling_step_1_detected"

    async def _on_details(
        self, st: dict[str, Any], ctx: dict[str, Any], out: TurnOutput
    ) -> None:
        validation = tools.validate_listing_fields(
            json.dumps(ctx),
            _StateContext(st),  # type: ignore[arg-type]
        )
        if not validation["valid"]:
            self._rerender_detected(
                st, ctx, list(validation["field_errors"].values()), out
            )
            out.text = "Some details need fixing."
            return

        draft = st["listing_draft"]
        category = str(draft.get("category", "car"))
        has_mileage = tools._parse_int(draft.get("mileageKm")) is not None
        answers = await self._ask(
            out,
            "details",
            {
                "item": {k: draft.get(k) for k in _DETECTED_KEYS},
                "details": {k: v for k, v in ctx.items() if k not in _DETECTED_KEYS},
            },
            decisions.details_questions(category),
        )
        decision = decisions.decide_details(
            answers,
            already_warned=bool(st.get("plausibility_warned")),
            has_mileage=has_mileage,
        )
        self._record(out, "details", decision.trace)
        st["condition_level"] = decision.condition_level

        if decision.send_back:
            st["plausibility_warned"] = True
            self._rerender_detected(
                st,
                ctx,
                [
                    "Jev rated these details as inconsistent. Please double-check them, "
                    "or tap Continue again to keep them."
                ],
                out,
            )
            out.text = "Jev asked to double-check the details."
            return

        followups = list(validation["required_followups"])
        if decision.want_odometer_photo and "odometer_photo" not in followups:
            followups.append("odometer_photo")
        st["need_odometer"] = "odometer_photo" in followups
        st["need_damage"] = "damage_photo" in followups
        if followups:
            self._render_followup(st, out, [])
            out.text = "A couple of photos will make the listing stronger."
        else:
            await self._render_preview(st, out)

    # -- Stage 2 ------------------------------------------------------------

    def _render_followup(
        self, st: dict[str, Any], out: TurnOutput, notices: list[str]
    ) -> None:
        st["stage"] = "selling_step_2_followup"
        out.messages = surfaces.followup(
            need_odometer=bool(st.get("need_odometer")),
            need_damage=bool(st.get("need_damage")),
            followup_data=st["listing_draft"],
            notices=notices,
        )

    async def _on_followup_photo(
        self, st: dict[str, Any], ctx: dict[str, Any], turn: TurnInput, out: TurnOutput
    ) -> None:
        if not turn.photo:
            self._render_followup(
                st, out, ["The photo did not arrive. Please try again."]
            )
            return
        draft = st["listing_draft"]
        url = turn.image_url or ""
        notices: list[str] = []
        if ctx.get("requestType") == "odometer":
            try:
                reading = await self._writer.read_odometer(turn.photo)
                result = tools.extract_odometer_reading(
                    reading.raw_reading_text,
                    reading.unit,
                    _StateContext(st),  # type: ignore[arg-type]
                )
            except Exception as exc:
                logger.warning("Odometer reading failed: %s", exc)
                result = {
                    "status": "error",
                    "error": "Gemini could not read the photo.",
                }
            if result["status"] == "success":
                # The tool replaces `listing_draft`; write to the current dict.
                draft = st["listing_draft"]
                draft["odometerPhotoUrl"] = url
                notices.append(f"✅ Read {result['mileageKm']:,} km from the odometer.")
            else:
                notices.append(f"⚠️ {result['error']} Please retake the photo.")
        else:
            answers = await self._ask(
                out,
                "damage_photo",
                {
                    "task": "Check a close-up photo meant to document damage on an item for sale."
                },
                decisions.damage_photo_questions(),
                photo=turn.photo,
            )
            ok, entry = decisions.decide_damage_photo(answers)
            self._record(out, "damage_photo", [entry])
            if ok:
                draft["damagePhotoUrl"] = url
                notices.append("✅ Damage photo added.")
            else:
                notices.append(
                    "⚠️ Jev could not see the damage in that photo. Please retake it closer."
                )
        self._render_followup(st, out, notices)

    async def _on_followup_submit(
        self, st: dict[str, Any], ctx: dict[str, Any], out: TurnOutput
    ) -> None:
        draft = st["listing_draft"]
        if ctx.get("damageNotes"):
            draft["damageNotes"] = str(ctx["damageNotes"])
        missing: list[str] = []
        if st.get("need_odometer") and not draft.get("odometerPhotoUrl"):
            missing.append("⚠️ Add an odometer photo so we can verify the mileage.")
        if st.get("need_damage") and not draft.get("damagePhotoUrl"):
            missing.append("⚠️ Add a close-up of the damage.")
        if missing:
            self._render_followup(st, out, missing)
            return
        await self._render_preview(st, out)

    # -- Stages 3 and 4 -------------------------------------------------------

    async def _render_preview(self, st: dict[str, Any], out: TurnOutput) -> None:
        estimate = tools.estimate_price_and_build_preview(
            0.0,
            "USD",
            _StateContext(st),  # type: ignore[arg-type]
        )
        level = int(st.get("condition_level", 2))
        factor = decisions.CONDITION_PRICE_FACTOR[level]
        for key in ("minPrice", "suggestedPrice", "maxPrice", "askingPrice"):
            estimate[key] = int(round(estimate[key] * factor / 100) * 100)
        condition = decisions.CONDITION_LEVELS[level]

        facts = {
            "specs": estimate["specs"],
            "condition": condition,
            "damageNotes": st["listing_draft"].get("damageNotes", ""),
            "priceRange": [
                estimate["minPrice"],
                estimate["maxPrice"],
                estimate["currency"],
            ],
        }
        try:
            copy = await self._writer.write_listing(facts)
            title, description, rationale = copy.title, copy.description, copy.rationale
        except Exception as exc:
            logger.warning("Gemini could not write the listing copy: %s", exc)
            title = estimate["generatedTitle"]
            description = estimate["generatedDescription"]
            rationale = estimate["rationale"]
        rationale = f"{rationale} Condition rated '{condition}' by Jev."

        st["stage"] = "selling_step_3_preview"
        out.messages = surfaces.preview(
            estimate=estimate, title=title, description=description, rationale=rationale
        )
        out.text = "Here is your listing preview."

    def _on_publish(
        self, st: dict[str, Any], ctx: dict[str, Any], out: TurnOutput
    ) -> None:
        st["stage"] = "selling_step_4_published"
        out.messages = surfaces.published(
            title=str(ctx.get("title", "Your listing")),
            price=ctx.get("askingPrice", ""),
            currency=str(ctx.get("currency", "USD")),
        )
        out.text = "Your listing is published."
