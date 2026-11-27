"""The bank of form fields an agent can put on the "detected item" screen.

Instead of one fixed form per category, each photo gets its own form: a small
required base plus the candidate fields that fit *this* item. The same bank
drives both variants:

* Express: the bank is rendered into the prompt and Gemini picks the fields.
* Jev: every candidate becomes a yes/no question (`field_<key>`) and code keeps
  the ones Jev rates as worth asking.

Every field renders with Basic Catalog components (`TextField`, `ChoicePicker`,
`CheckBox`, `Slider`) bound to `/details/<key>`, so the Flutter client needs no
new widgets. `price_adjustments()` makes the answers count in the price.

This file is identical in `snap_sell_express/agent/app` and `snap_sell_jev/agent/app`.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

VEHICLES = ("car", "motorcycle")

#: Extra (non-base) fields shown at most, so the form stays short.
MAX_EXTRA_FIELDS = 4


@dataclass(frozen=True)
class FieldSpec:
    key: str
    label: str
    #: "number" | "text" | "choice" | "checkbox" | "slider"
    widget: str
    categories: tuple[str, ...]
    #: When the field is worth asking, phrased as a statement about the photo.
    #: Express shows it to Gemini; Jev answers it as a `noul` question.
    when: str = ""
    options: tuple[tuple[str, str], ...] = ()
    default: Any = ""
    #: Base fields are always shown for their category (and powertrain).
    base: bool = False
    #: "ice" or "ev" restricts the field, for vehicles only, to one powertrain.
    powertrain: str | None = None

    @property
    def path(self) -> str:
        return f"/details/{self.key}"


FIELD_BANK: tuple[FieldSpec, ...] = (
    # -- Vehicle base -------------------------------------------------------
    FieldSpec("mileageKm", "Mileage (km)", "number", VEHICLES, base=True),
    FieldSpec(
        "engineCc", "Engine displacement (cc)", "number", VEHICLES,
        base=True, powertrain="ice",
    ),
    FieldSpec(
        "batteryRangeKm", "Battery range (km)", "number", VEHICLES,
        base=True, powertrain="ev",
    ),
    # -- Vehicle candidates -------------------------------------------------
    FieldSpec(
        "ownersCount", "Number of owners", "choice", VEHICLES,
        when="The vehicle looks used rather than brand new, so buyers will ask how many owners it had.",
        options=(("1st owner", "1"), ("2 owners", "2"), ("3+ owners", "3+")),
        default=["1"],
    ),
    FieldSpec(
        "papersUpToDate", "Registration & inspection papers up to date", "checkbox", VEHICLES,
        when="The vehicle looks more than about 2 years old, so registration renewals and technical inspection matter.",
        default=True,
    ),
    FieldSpec(
        "transmission", "Transmission", "choice", ("car",),
        when="The item is a car whose gearbox type (manual or automatic) cannot be seen in the photo.",
        options=(("Manual", "manual"), ("Automatic", "automatic")),
        default=["automatic"],
    ),
    FieldSpec(
        "serviceHistory", "Service history", "choice", VEHICLES,
        when="The vehicle looks between about 2 and 15 years old, the age at which buyers ask for maintenance records.",
        options=(("Dealer", "dealer"), ("Independent shop", "independent"), ("No records", "none")),
        default=["dealer"],
    ),
    FieldSpec(
        "tiresCondition", "Tire condition", "choice", VEHICLES,
        when="The tires are visible in the photo and look worn, or the vehicle looks heavily used.",
        options=(("New", "new"), ("Good", "good"), ("Worn", "worn")),
        default=["good"],
    ),
    FieldSpec(
        "originalParts", "All original parts (matching numbers)", "checkbox", VEHICLES,
        when="The vehicle looks like a classic or vintage model, roughly 25 or more years old.",
        default=False,
    ),
    FieldSpec(
        "restoration", "Restoration", "choice", VEHICLES,
        when="The vehicle looks like a classic or vintage model that may have been restored.",
        options=(("None", "none"), ("Partial", "partial"), ("Full", "full")),
        default=["none"],
    ),
    FieldSpec(
        "modifications", "Modifications (exhaust, suspension, wheels…)", "text", VEHICLES,
        when="The vehicle looks sporty, tuned, or modified: aftermarket wheels, exhaust, lowered stance, or decals.",
    ),
    FieldSpec(
        "includesHelmet", "Helmet included", "checkbox", ("motorcycle",),
        when="The item is a motorcycle or scooter sold to an everyday rider, who will ask about a helmet.",
        default=False,
    ),
    FieldSpec(
        "chainCondition", "Chain & sprockets", "choice", ("motorcycle",),
        when="The item is a motorcycle with a visible chain drive (not a scooter with an enclosed belt).",
        options=(("New", "new"), ("Good", "good"), ("Needs replacement", "replace")),
        default=["good"],
    ),
    # -- Phone base ---------------------------------------------------------
    FieldSpec(
        "storageGb", "Internal storage", "choice", ("phone",), base=True,
        options=(("128 GB", "128"), ("256 GB", "256"), ("512 GB", "512"), ("1 TB", "1024")),
        default=["128"],
    ),
    # -- Phone candidates ---------------------------------------------------
    FieldSpec(
        "batteryHealthPct", "Battery health (%)", "slider", (*VEHICLES, "phone"),
        when="The item has a battery that wears out (a phone, or an electric vehicle) and looks more than about a year old.",
        default=90, powertrain="ev",
    ),
    FieldSpec(
        "unlocked", "Factory unlocked for all carriers", "checkbox", ("phone",),
        when="The phone shows carrier branding, or it is unclear whether it is locked to a carrier.",
        default=True,
    ),
    FieldSpec(
        "screenCondition", "Screen condition", "choice", ("phone",),
        when="The phone's screen is visible and shows scratches or cracks.",
        options=(("Perfect", "perfect"), ("Light scratches", "scratches"), ("Cracked", "cracked")),
        default=["perfect"],
    ),
    FieldSpec(
        "biometricsWork", "Face ID / fingerprint works", "checkbox", ("phone",),
        when="The phone looks damaged or repaired, so buyers will ask whether Face ID or the fingerprint sensor still work.",
        default=True,
    ),
    FieldSpec(
        "includesBoxCharger", "Original box & charger included", "checkbox", ("phone",),
        when="The phone looks recent or premium (a flagship model), where the original box and accessories add resale value.",
        default=False,
    ),
    FieldSpec(
        "warrantyActive", "Factory warranty still active", "checkbox", (*VEHICLES, "phone"),
        when="The item looks recent, about 3 years old or less, so it may still be under factory warranty.",
        default=False,
    ),
    # -- Always last (or first when damage is visible) ----------------------
    FieldSpec("hasDamage", "Has visible damage or known issues", "checkbox", (*VEHICLES, "phone"), base=True, default=False),
)

BANK: dict[str, FieldSpec] = {spec.key: spec for spec in FIELD_BANK}


def _fits(spec: FieldSpec, category: str, is_ev: bool) -> bool:
    if category not in spec.categories:
        return False
    if category not in VEHICLES:
        return True
    if spec.powertrain == "ev":
        return is_ev
    if spec.powertrain == "ice":
        return not is_ev
    return True


def base_fields(category: str, is_ev: bool) -> list[str]:
    """Fields every form of this category shows (damage is placed separately)."""
    return [
        s.key for s in FIELD_BANK
        if s.base and s.key != "hasDamage" and _fits(s, category, is_ev)
    ]


def candidate_fields(category: str, is_ev: bool) -> list[FieldSpec]:
    """Optional fields the agent may add for this category."""
    return [s for s in FIELD_BANK if not s.base and _fits(s, category, is_ev)]


def all_candidates() -> list[FieldSpec]:
    return [s for s in FIELD_BANK if not s.base]


def assemble(
    category: str, is_ev: bool, extra: list[str], *, damage_first: bool
) -> list[str]:
    """Orders the final form: [damage?] base, extra (capped), [damage]."""
    allowed = {s.key for s in candidate_fields(category, is_ev)}
    extras = [k for k in extra if k in allowed][:MAX_EXTRA_FIELDS]
    body = base_fields(category, is_ev) + extras
    return ["hasDamage", *body] if damage_first else [*body, "hasDamage"]


def default_details(keys: list[str], *, has_damage: bool) -> dict[str, Any]:
    details = {k: BANK[k].default for k in keys if k in BANK}
    if "hasDamage" in details:
        details["hasDamage"] = has_damage
    return details


def component_for(spec: FieldSpec, cid: str) -> dict[str, Any]:
    """The Basic Catalog component (A2UI v1.0 JSON) that edits one field."""
    value = {"@path": spec.path}
    if spec.widget == "checkbox":
        return {"id": cid, "component": "CheckBox", "label": spec.label, "value": value}
    if spec.widget == "choice":
        return {
            "id": cid,
            "component": "ChoicePicker",
            "label": spec.label,
            "variant": "mutuallyExclusive",
            "displayStyle": "chips",
            "options": [{"label": lbl, "value": val} for lbl, val in spec.options],
            "value": value,
        }
    if spec.widget == "slider":
        return {
            "id": cid, "component": "Slider", "label": spec.label,
            "min": 50, "max": 100, "value": value,
        }
    field = {"id": cid, "component": "TextField", "label": spec.label, "value": value}
    if spec.widget == "number":
        field["variant"] = "number"
    return field


def prompt_reference() -> str:
    """The bank as text for an LLM prompt (used by the Express variant)."""
    lines = []
    for s in FIELD_BANK:
        scope = "/".join(s.categories)
        if s.powertrain:
            scope += f" ({'EV' if s.powertrain == 'ev' else 'non-EV'} only)"
        widget = s.widget
        if s.options:
            widget += " [" + ", ".join(f'"{lbl}"="{val}"' for lbl, val in s.options) + "]"
        rule = "BASE: always" if s.base else f"ADD WHEN: {s.when}"
        lines.append(
            f"- `{s.key}` ({scope}) {widget}, label \"{s.label}\", default {s.default!r}. {rule}"
        )
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Pricing: the answers have to matter
# ---------------------------------------------------------------------------


def _first(value: Any) -> Any:
    if isinstance(value, list):
        return value[0] if value else None
    return value


#: (key, value) -> (price factor, spec label shown in the preview)
_ADJUSTMENTS: dict[tuple[str, Any], tuple[float, str]] = {
    ("serviceHistory", "dealer"): (1.04, "Dealer service history"),
    ("serviceHistory", "none"): (0.95, "No service records"),
    ("tiresCondition", "new"): (1.02, "New tires"),
    ("tiresCondition", "worn"): (0.97, "Worn tires"),
    ("warrantyActive", True): (1.05, "Factory warranty active"),
    ("originalParts", True): (1.08, "All original parts"),
    ("restoration", "partial"): (1.04, "Partially restored"),
    ("restoration", "full"): (1.10, "Fully restored"),
    ("includesHelmet", True): (1.01, "Helmet included"),
    ("chainCondition", "replace"): (0.97, "Chain needs replacement"),
    ("screenCondition", "scratches"): (0.93, "Light screen scratches"),
    ("screenCondition", "cracked"): (0.70, "Cracked screen"),
    ("biometricsWork", False): (0.80, "Face ID / fingerprint not working"),
    ("includesBoxCharger", True): (1.03, "Original box & charger"),
}


def price_adjustments(draft: dict[str, Any]) -> tuple[float, list[str]]:
    """Combined price factor and the reasons, from the extra fields that were asked."""
    factor = 1.0
    reasons: list[str] = []
    for (key, expected), (mult, reason) in _ADJUSTMENTS.items():
        if key in draft and _first(draft[key]) == expected:
            factor *= mult
            reasons.append(reason)
    return factor, reasons
