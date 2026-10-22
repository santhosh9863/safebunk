"""Canonical complaint categories shared with the current PULSE UI.

These values are the exact strings offered by
``lib/features/reports/presentation/screens/create_report_screen.dart``. Do not
rename them silently: a stored report category must remain comparable with the
model output.
"""

from __future__ import annotations

from typing import Final

SUPPORTED_CATEGORIES: Final[tuple[str, ...]] = (
    "Infrastructure",
    "Electrical",
    "Plumbing",
    "Cleanliness",
    "Safety",
    "Network / IT",
    "Academic",
    "Other",
)

if len(SUPPORTED_CATEGORIES) != len(set(SUPPORTED_CATEGORIES)):
    raise RuntimeError("SUPPORTED_CATEGORIES contains duplicates")

CATEGORY_SET: Final[frozenset[str]] = frozenset(SUPPORTED_CATEGORIES)

MIN_DESCRIPTION_LENGTH: Final[int] = 5
MAX_DESCRIPTION_LENGTH: Final[int] = 4000
MIN_TRAINING_DESCRIPTION_LENGTH: Final[int] = 10


def is_supported_category(value: str) -> bool:
    """Return whether *value* is one of the exact stored category labels."""

    return value in CATEGORY_SET
