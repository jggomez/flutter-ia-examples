# ui/core/widgets

Shared, feature-agnostic widgets (e.g. a reusable confidence-bar widget used
by both the "Tú vs. IA" reveal animation and the "Práctica libre" meters).

Nothing here should import from `ui/features/**`, `data/**`, or
`domain/repositories/**` — this layer only depends on `domain/models` and
Flutter.
