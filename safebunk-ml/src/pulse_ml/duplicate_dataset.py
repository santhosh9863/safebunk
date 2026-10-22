"""Loading, validating, and building the synthetic duplicate-detection benchmark."""

from __future__ import annotations

import csv
import hashlib
import io
import json
import re
from collections.abc import Collection, Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Final

from sklearn.feature_extraction.text import ENGLISH_STOP_WORDS

from pulse_ml.categories import CATEGORY_SET, SUPPORTED_CATEGORIES

COMPLAINT_COLUMNS: Final[tuple[str, ...]] = (
    "complaint_id",
    "group_id",
    "description",
    "category",
    "location",
    "split",
)
PAIR_COLUMNS: Final[tuple[str, ...]] = (
    "pair_id",
    "left_complaint_id",
    "right_complaint_id",
    "split",
    "label",
    "difficulty",
    "same_category",
    "same_location",
    "token_overlap",
)
TRAIN_SPLIT: Final[str] = "train"
VALIDATION_SPLIT: Final[str] = "validation"
TEST_SPLIT: Final[str] = "test"
SPLIT_ORDER: Final[tuple[str, ...]] = (TRAIN_SPLIT, VALIDATION_SPLIT, TEST_SPLIT)
VALID_SPLITS: Final[frozenset[str]] = frozenset(SPLIT_ORDER)
LEGACY_SPLITS: Final[frozenset[str]] = frozenset({TRAIN_SPLIT, TEST_SPLIT})
MIN_DESCRIPTION_LENGTH: Final[int] = 10

_WHITESPACE_RE = re.compile(r"\s+")
_NON_WORD_RE = re.compile(r"[^\w\s]", re.UNICODE)
_TOKEN_RE = re.compile(r"[a-z0-9]+")


class DuplicateDatasetError(ValueError):
    """Raised when a duplicate-detection benchmark is not usable."""

    def __init__(self, issues: list[str]) -> None:
        self.issues = issues
        message = "Duplicate dataset validation failed:\n" + "\n".join(
            f"- {issue}" for issue in issues
        )
        super().__init__(message)


@dataclass(frozen=True)
class DuplicateComplaint:
    complaint_id: str
    group_id: str
    description: str
    category: str
    location: str
    split: str


@dataclass(frozen=True)
class DuplicateDataset:
    path: Path
    sha256: str
    complaints: tuple[DuplicateComplaint, ...]

    @property
    def groups(self) -> dict[str, tuple[DuplicateComplaint, ...]]:
        grouped: dict[str, list[DuplicateComplaint]] = {}
        for complaint in self.complaints:
            grouped.setdefault(complaint.group_id, []).append(complaint)
        return {group_id: tuple(values) for group_id, values in grouped.items()}

    @property
    def split_complaints(self) -> dict[str, tuple[DuplicateComplaint, ...]]:
        present_splits = sorted({complaint.split for complaint in self.complaints})
        return {
            split: tuple(complaint for complaint in self.complaints if complaint.split == split)
            for split in present_splits
        }


@dataclass(frozen=True)
class DuplicatePair:
    pair_id: str
    left_complaint_id: str
    right_complaint_id: str
    split: str
    label: int
    difficulty: str
    same_category: bool
    same_location: bool
    token_overlap: float


def _normalize_for_duplicate_check(text: str) -> str:
    normalized = _WHITESPACE_RE.sub(" ", _NON_WORD_RE.sub(" ", text.casefold()))
    return normalized.strip()


def _tokens(text: str) -> set[str]:
    return {
        token for token in _TOKEN_RE.findall(text.casefold()) if token not in ENGLISH_STOP_WORDS
    }


def _jaccard(left: set[str], right: set[str]) -> float:
    if not left or not right:
        return 0.0
    return len(left & right) / len(left | right)


def load_duplicate_complaints(
    path: str | Path,
    *,
    required_splits: Collection[str] = LEGACY_SPLITS,
    min_groups_per_category: int = 2,
) -> DuplicateDataset:
    """Load a complaint-group benchmark and reject split or group leakage.

    ``required_splits`` defaults to the Phase 2 train/test layout so existing
    artifacts keep validating exactly as before. Phase 2.1 passes train,
    validation, and test explicitly.
    """

    configured_splits = frozenset(required_splits)
    if not configured_splits:
        raise DuplicateDatasetError(["required_splits must not be empty"])
    unknown_splits = sorted(configured_splits - VALID_SPLITS)
    if unknown_splits:
        raise DuplicateDatasetError(
            [f"unknown required splits: {unknown_splits}; expected {sorted(VALID_SPLITS)}"]
        )
    if min_groups_per_category < 1:
        raise DuplicateDatasetError(["min_groups_per_category must be at least 1"])

    dataset_path = Path(path)
    try:
        raw = dataset_path.read_bytes()
    except OSError as exc:
        raise DuplicateDatasetError([f"could not read {dataset_path}: {exc}"]) from exc

    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise DuplicateDatasetError([f"{dataset_path} is not valid UTF-8: {exc}"]) from exc

    issues: list[str] = []
    complaints: list[DuplicateComplaint] = []
    seen_ids: set[str] = set()
    seen_descriptions: dict[str, str] = {}

    try:
        reader = csv.DictReader(io.StringIO(text))
        if reader.fieldnames is None or tuple(reader.fieldnames) != COMPLAINT_COLUMNS:
            raise DuplicateDatasetError(
                [f"header must be exactly {COMPLAINT_COLUMNS}; found {reader.fieldnames}"]
            )
        for row_number, row in enumerate(reader, start=2):
            if None in row:
                issues.append(f"row {row_number}: unexpected extra field")
                continue
            if not row or all(not (value or "").strip() for value in row.values()):
                issues.append(f"row {row_number}: blank record")
                continue

            values = {name: (row.get(name) or "").strip() for name in COMPLAINT_COLUMNS}
            complaint_id = values["complaint_id"]
            group_id = values["group_id"]
            description = values["description"]
            category = values["category"]
            location = values["location"]
            split = values["split"]

            if not complaint_id:
                issues.append(f"row {row_number}: missing complaint_id")
            elif complaint_id in seen_ids:
                issues.append(f"row {row_number}: duplicate complaint_id {complaint_id!r}")
            else:
                seen_ids.add(complaint_id)

            if not group_id:
                issues.append(f"row {row_number}: missing group_id")
            if len(description) < MIN_DESCRIPTION_LENGTH:
                issues.append(
                    f"row {row_number}: description is shorter than "
                    f"{MIN_DESCRIPTION_LENGTH} characters"
                )
            if category not in CATEGORY_SET:
                issues.append(f"row {row_number}: unknown category {category!r}")
            if not location:
                issues.append(f"row {row_number}: missing location")
            if split not in configured_splits:
                issues.append(
                    f"row {row_number}: split must be one of "
                    f"{sorted(configured_splits)}; found {split!r}"
                )

            normalized = _normalize_for_duplicate_check(description)
            if normalized in seen_descriptions:
                issues.append(
                    f"row {row_number}: duplicate description already used by "
                    f"{seen_descriptions[normalized]}"
                )
            else:
                seen_descriptions[normalized] = complaint_id

            if (
                complaint_id
                and group_id
                and description
                and category in CATEGORY_SET
                and location
                and split in configured_splits
            ):
                complaints.append(
                    DuplicateComplaint(
                        complaint_id=complaint_id,
                        group_id=group_id,
                        description=description,
                        category=category,
                        location=location,
                        split=split,
                    )
                )
    except csv.Error as exc:
        raise DuplicateDatasetError([f"malformed CSV: {exc}"]) from exc

    if not complaints and not issues:
        issues.append("dataset has no data rows")

    grouped: dict[str, list[DuplicateComplaint]] = {}
    for complaint in complaints:
        grouped.setdefault(complaint.group_id, []).append(complaint)

    for group_id, group_rows in grouped.items():
        if len(group_rows) < 2:
            issues.append(f"group {group_id}: needs at least 2 complaint variants")
        group_splits = {row.split for row in group_rows}
        if len(group_splits) != 1:
            issues.append(
                f"group {group_id}: variants must not cross splits; found {sorted(group_splits)}"
            )
        if len({row.category for row in group_rows}) != 1:
            issues.append(f"group {group_id}: variants must share one category")
        if len({row.location for row in group_rows}) != 1:
            issues.append(f"group {group_id}: variants must share one location")

    for split in sorted(configured_splits):
        split_rows = [row for row in complaints if row.split == split]
        if not split_rows:
            issues.append(f"split {split}: has no complaints")
            continue
        split_categories = {row.category for row in split_rows}
        missing = sorted(set(SUPPORTED_CATEGORIES) - split_categories)
        if missing:
            issues.append(f"split {split}: missing categories {missing}")
        for category in SUPPORTED_CATEGORIES:
            category_groups = {row.group_id for row in split_rows if row.category == category}
            if category in split_categories and len(category_groups) < min_groups_per_category:
                issues.append(
                    f"split {split}: category {category} needs at least "
                    f"{min_groups_per_category} groups for hard-negative coverage"
                )

    groups_by_split = {
        split: {row.group_id for row in complaints if row.split == split}
        for split in configured_splits
    }
    split_names = sorted(configured_splits)
    for left_index, left_split in enumerate(split_names):
        for right_split in split_names[left_index + 1 :]:
            overlap = sorted(groups_by_split[left_split] & groups_by_split[right_split])
            if overlap:
                issues.append(f"groups appear in both {left_split} and {right_split}: {overlap}")

    if issues:
        raise DuplicateDatasetError(issues)

    return DuplicateDataset(
        path=dataset_path,
        sha256=hashlib.sha256(raw).hexdigest(),
        complaints=tuple(complaints),
    )


def build_duplicate_pairs(dataset: DuplicateDataset) -> tuple[DuplicatePair, ...]:
    """Create every within-split complaint pair with an explicit difficulty label."""

    pairs: list[DuplicatePair] = []
    split_rows = dataset.split_complaints
    for split in sorted(split_rows):
        rows = split_rows[split]
        for left_index, left in enumerate(rows):
            for right in rows[left_index + 1 :]:
                same_group = left.group_id == right.group_id
                same_category = left.category == right.category
                same_location = left.location == right.location
                token_overlap = round(
                    _jaccard(_tokens(left.description), _tokens(right.description)),
                    6,
                )

                if same_group:
                    label = 1
                    difficulty = "duplicate"
                else:
                    label = 0
                    if same_category or same_location or token_overlap >= 0.30:
                        difficulty = "hard_negative"
                    elif token_overlap >= 0.15:
                        difficulty = "medium_negative"
                    else:
                        difficulty = "easy_negative"

                pairs.append(
                    DuplicatePair(
                        pair_id=f"DP{len(pairs) + 1:04d}",
                        left_complaint_id=min(left.complaint_id, right.complaint_id),
                        right_complaint_id=max(left.complaint_id, right.complaint_id),
                        split=split,
                        label=label,
                        difficulty=difficulty,
                        same_category=same_category,
                        same_location=same_location,
                        token_overlap=token_overlap,
                    )
                )
    return tuple(pairs)


def _canonical_sha256(payload: Any) -> str:
    encoded = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def test_fingerprint(
    dataset: DuplicateDataset,
    pairs: Collection[DuplicatePair],
) -> dict[str, Any]:
    """Return a deterministic fingerprint of the frozen test partition."""

    test_complaints = sorted(
        (
            {
                "complaint_id": complaint.complaint_id,
                "group_id": complaint.group_id,
                "description": complaint.description,
                "category": complaint.category,
                "location": complaint.location,
                "split": complaint.split,
            }
            for complaint in dataset.complaints
            if complaint.split == TEST_SPLIT
        ),
        key=lambda row: str(row["complaint_id"]),
    )
    test_pairs = sorted(
        (
            {
                "pair_id": pair.pair_id,
                "left_complaint_id": pair.left_complaint_id,
                "right_complaint_id": pair.right_complaint_id,
                "split": pair.split,
                "label": pair.label,
                "difficulty": pair.difficulty,
                "same_category": pair.same_category,
                "same_location": pair.same_location,
                "token_overlap": pair.token_overlap,
            }
            for pair in pairs
            if pair.split == TEST_SPLIT
        ),
        key=lambda row: str(row["pair_id"]),
    )
    if not test_complaints:
        raise DuplicateDatasetError(["test split has no complaints"])
    if not test_pairs:
        raise DuplicateDatasetError(["test split has no pairs"])

    return {
        "split": TEST_SPLIT,
        "group_ids": sorted({row["group_id"] for row in test_complaints}),
        "complaint_ids": [row["complaint_id"] for row in test_complaints],
        "complaint_count": len(test_complaints),
        "pair_count": len(test_pairs),
        "complaints_sha256": _canonical_sha256(test_complaints),
        "pairs_sha256": _canonical_sha256(test_pairs),
    }


def verify_test_freeze(
    dataset: DuplicateDataset,
    pairs: Collection[DuplicatePair],
    freeze: Mapping[str, Any],
) -> None:
    """Reject evaluation if the frozen test partition changed."""

    expected = test_fingerprint(dataset, pairs)
    issues: list[str] = []
    if freeze.get("frozen_before_tuning") is not True:
        issues.append("freeze record must set frozen_before_tuning to true")
    for key in (
        "group_ids",
        "complaint_ids",
        "complaint_count",
        "pair_count",
        "complaints_sha256",
        "pairs_sha256",
    ):
        if freeze.get(key) != expected[key]:
            issues.append(f"frozen test {key} does not match the current dataset")
    if issues:
        raise DuplicateDatasetError(issues)


def write_duplicate_pairs(pairs: tuple[DuplicatePair, ...], path: str | Path) -> None:
    """Write the generated pair benchmark with stable ordering and line endings."""

    output_path = Path(path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(PAIR_COLUMNS)
        for pair in pairs:
            writer.writerow(
                (
                    pair.pair_id,
                    pair.left_complaint_id,
                    pair.right_complaint_id,
                    pair.split,
                    pair.label,
                    pair.difficulty,
                    int(pair.same_category),
                    int(pair.same_location),
                    f"{pair.token_overlap:.6f}",
                )
            )


def load_duplicate_pairs(path: str | Path, dataset: DuplicateDataset) -> tuple[DuplicatePair, ...]:
    """Load a generated pair file and verify every row against complaint groups."""

    pairs_path = Path(path)
    try:
        raw = pairs_path.read_bytes()
    except OSError as exc:
        raise DuplicateDatasetError([f"could not read {pairs_path}: {exc}"]) from exc

    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise DuplicateDatasetError([f"{pairs_path} is not valid UTF-8: {exc}"]) from exc

    expected_pairs = build_duplicate_pairs(dataset)
    expected_by_complaints = {
        (pair.left_complaint_id, pair.right_complaint_id): pair for pair in expected_pairs
    }
    issues: list[str] = []
    pairs: list[DuplicatePair] = []
    seen_pair_ids: set[str] = set()
    seen_pairs: set[tuple[str, str]] = set()

    try:
        reader = csv.DictReader(io.StringIO(text))
        if reader.fieldnames is None or tuple(reader.fieldnames) != PAIR_COLUMNS:
            raise DuplicateDatasetError(
                [f"pair header must be exactly {PAIR_COLUMNS}; found {reader.fieldnames}"]
            )
        for row_number, row in enumerate(reader, start=2):
            if None in row:
                issues.append(f"row {row_number}: unexpected extra field")
                continue
            pair_id = (row.get("pair_id") or "").strip()
            left_id = (row.get("left_complaint_id") or "").strip()
            right_id = (row.get("right_complaint_id") or "").strip()
            split = (row.get("split") or "").strip()
            difficulty = (row.get("difficulty") or "").strip()

            if not pair_id or pair_id in seen_pair_ids:
                issues.append(f"row {row_number}: invalid or duplicate pair_id {pair_id!r}")
                continue
            seen_pair_ids.add(pair_id)

            if left_id >= right_id:
                issues.append(f"row {row_number}: pair IDs must be in canonical ascending order")
                continue
            pair_key = (left_id, right_id)
            if pair_key in seen_pairs:
                issues.append(f"row {row_number}: duplicate complaint pair")
                continue
            seen_pairs.add(pair_key)

            expected = expected_by_complaints.get(pair_key)
            if expected is None:
                issues.append(f"row {row_number}: pair is not in the expected within-split set")
                continue

            try:
                label = int(row.get("label") or "")
                same_category = bool(int(row.get("same_category") or ""))
                same_location = bool(int(row.get("same_location") or ""))
                token_overlap = float(row.get("token_overlap") or "")
            except ValueError:
                issues.append(f"row {row_number}: malformed numeric field")
                continue

            if pair_id != expected.pair_id:
                issues.append(
                    f"row {row_number}: pair_id {pair_id!r} should be {expected.pair_id!r}"
                )
            if label not in {0, 1}:
                issues.append(f"row {row_number}: label must be 0 or 1")
            if label != expected.label:
                issues.append(f"row {row_number}: label disagrees with complaint groups")
            if split != expected.split:
                issues.append(f"row {row_number}: split disagrees with complaint groups")
            if difficulty != expected.difficulty:
                issues.append(f"row {row_number}: difficulty disagrees with generation rules")
            if same_category != expected.same_category:
                issues.append(f"row {row_number}: same_category flag is inconsistent")
            if same_location != expected.same_location:
                issues.append(f"row {row_number}: same_location flag is inconsistent")
            if abs(token_overlap - expected.token_overlap) > 1e-6:
                issues.append(f"row {row_number}: token_overlap disagrees with generation rules")

            pairs.append(
                DuplicatePair(
                    pair_id=pair_id,
                    left_complaint_id=left_id,
                    right_complaint_id=right_id,
                    split=split,
                    label=label,
                    difficulty=difficulty,
                    same_category=same_category,
                    same_location=same_location,
                    token_overlap=token_overlap,
                )
            )
    except csv.Error as exc:
        raise DuplicateDatasetError([f"malformed pair CSV: {exc}"]) from exc

    if issues:
        raise DuplicateDatasetError(issues)

    if len(pairs) != len(expected_pairs):
        raise DuplicateDatasetError(
            [
                "pair file is incomplete: "
                f"found {len(pairs)} pairs but expected {len(expected_pairs)}"
            ]
        )

    return tuple(pairs)
