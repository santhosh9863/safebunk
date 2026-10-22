"""Dataset loading, validation, and leakage-safe split helpers."""

from __future__ import annotations

import csv
import hashlib
import io
import random
import re
import unicodedata
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Final

from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

from pulse_ml.categories import (
    CATEGORY_SET,
    MAX_DESCRIPTION_LENGTH,
    MIN_TRAINING_DESCRIPTION_LENGTH,
    SUPPORTED_CATEGORIES,
)

BASE_COLUMNS: Final[tuple[str, ...]] = ("description", "category")
SOURCE_COLUMN: Final[str] = "source"
ALLOWED_HEADERS: Final[tuple[tuple[str, ...], ...]] = (
    BASE_COLUMNS,
    (*BASE_COLUMNS, SOURCE_COLUMN),
)
NEAR_DUPLICATE_THRESHOLD: Final[float] = 0.85

_WHITESPACE_RE = re.compile(r"\s+")
_NON_WORD_RE = re.compile(r"[^\w\s]", re.UNICODE)


class DatasetValidationError(ValueError):
    """Raised when a dataset cannot be used for reproducible training."""

    def __init__(self, issues: list[str]) -> None:
        self.issues = issues
        message = "Dataset validation failed:\n" + "\n".join(f"- {issue}" for issue in issues)
        super().__init__(message)


class InsufficientDataError(ValueError):
    """Raised when there is not enough independent data for a safe split."""


@dataclass(frozen=True)
class DatasetRow:
    row_number: int
    description: str
    category: str
    source: str | None = None


@dataclass(frozen=True)
class Dataset:
    path: Path
    sha256: str
    rows: tuple[DatasetRow, ...]
    category_counts: dict[str, int]

    @property
    def size(self) -> int:
        return len(self.rows)

    @property
    def source_counts(self) -> dict[str, int]:
        counts: dict[str, int] = {}
        for row in self.rows:
            if row.source is not None:
                counts[row.source] = counts.get(row.source, 0) + 1
        return counts


@dataclass(frozen=True)
class DatasetSplit:
    train_indices: tuple[int, ...]
    test_indices: tuple[int, ...]
    groups: tuple[int, ...]
    n_groups: int
    test_fraction: float
    random_state: int
    method: str = "category-stratified grouped holdout"


def _normalize_for_duplicate_check(text: str) -> str:
    normalized = unicodedata.normalize("NFKC", text).casefold()
    normalized = _NON_WORD_RE.sub(" ", normalized)
    return _WHITESPACE_RE.sub(" ", normalized).strip()


def load_and_validate_dataset(
    path: str | Path,
    *,
    require_all_categories: bool = True,
) -> Dataset:
    """Load the CSV and fail with a complete list of validation issues.

    Validation is intentionally strict because the training command must never
    quietly learn from malformed, unlabeled, duplicated, or out-of-scope rows.
    Focused addition files may set ``require_all_categories=False`` while still
    receiving every per-row check.
    """

    dataset_path = Path(path)
    try:
        raw = dataset_path.read_bytes()
    except OSError as exc:
        raise DatasetValidationError([f"could not read {dataset_path}: {exc}"]) from exc

    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise DatasetValidationError([f"{dataset_path} is not valid UTF-8: {exc}"]) from exc

    issues: list[str] = []
    rows: list[DatasetRow] = []
    seen_descriptions: dict[str, int] = {}

    try:
        reader = csv.reader(io.StringIO(text))
        header = next(reader)
    except StopIteration as exc:
        raise DatasetValidationError([f"{dataset_path} is empty"]) from exc
    except csv.Error as exc:
        raise DatasetValidationError([f"{dataset_path} has a malformed CSV header: {exc}"]) from exc

    normalized_header = tuple(column.strip() for column in header)
    if normalized_header not in ALLOWED_HEADERS:
        raise DatasetValidationError(
            [
                f"header must be exactly {BASE_COLUMNS} or {ALLOWED_HEADERS[1]}; "
                f"found {normalized_header}",
            ]
        )

    expected_field_count = len(normalized_header)
    has_source = SOURCE_COLUMN in normalized_header

    try:
        for row_number, raw_row in enumerate(reader, start=2):
            if not raw_row or all(not cell.strip() for cell in raw_row):
                issues.append(f"row {row_number}: blank record")
                continue
            if len(raw_row) != expected_field_count:
                issues.append(
                    f"row {row_number}: expected {expected_field_count} fields, "
                    f"found {len(raw_row)}"
                )
                continue

            description = raw_row[0].strip()
            category = raw_row[1].strip()
            source = raw_row[2].strip() if has_source else None
            row_issue_count = len(issues)

            if not description:
                issues.append(f"row {row_number}: missing description")
            elif len(description) < MIN_TRAINING_DESCRIPTION_LENGTH:
                issues.append(
                    f"row {row_number}: description is shorter than "
                    f"{MIN_TRAINING_DESCRIPTION_LENGTH} characters"
                )
            elif len(description) > MAX_DESCRIPTION_LENGTH:
                issues.append(
                    f"row {row_number}: description exceeds {MAX_DESCRIPTION_LENGTH} characters"
                )

            if not category:
                issues.append(f"row {row_number}: missing category")
            elif category not in CATEGORY_SET:
                issues.append(f"row {row_number}: unknown category {category!r}")

            if has_source and not source:
                issues.append(f"row {row_number}: missing source")

            normalized = _normalize_for_duplicate_check(description)
            if normalized and normalized in seen_descriptions:
                issues.append(
                    f"row {row_number}: duplicate description (first seen on row "
                    f"{seen_descriptions[normalized]})"
                )
            elif normalized:
                seen_descriptions[normalized] = row_number

            if len(issues) == row_issue_count:
                rows.append(
                    DatasetRow(
                        row_number=row_number,
                        description=description,
                        category=category,
                        source=source,
                    )
                )
    except csv.Error as exc:
        issues.append(f"malformed CSV near row {reader.line_num}: {exc}")

    if not rows and not issues:
        issues.append("dataset has no data rows")

    category_counts = {category: 0 for category in SUPPORTED_CATEGORIES}
    for row in rows:
        category_counts[row.category] += 1

    missing_categories = [category for category, count in category_counts.items() if count == 0]
    if require_all_categories and missing_categories:
        issues.append(f"missing categories: {', '.join(missing_categories)}")

    undersized_categories = [
        f"{category} ({count})" for category, count in category_counts.items() if 0 < count < 2
    ]
    if undersized_categories:
        issues.append(
            "each category needs at least 2 independent examples for a safe split: "
            + ", ".join(undersized_categories)
        )

    if issues:
        raise DatasetValidationError(issues)

    return Dataset(
        path=dataset_path,
        sha256=hashlib.sha256(raw).hexdigest(),
        rows=tuple(rows),
        category_counts=category_counts,
    )


def near_duplicate_groups(rows: tuple[DatasetRow, ...]) -> tuple[int, ...]:
    """Assign deterministic group ids so near-identical rows stay in one split.

    Exact duplicates are rejected during validation. This second guard catches
    paraphrases with very high TF-IDF cosine similarity, which would otherwise
    let the same complaint appear in both training and evaluation.
    """

    if not rows:
        return ()
    if len(rows) == 1:
        return (0,)

    descriptions = [row.description for row in rows]
    vectorizer = TfidfVectorizer(
        analyzer="word",
        ngram_range=(1, 2),
        stop_words="english",
        sublinear_tf=True,
    )
    try:
        matrix = vectorizer.fit_transform(descriptions)
    except ValueError as exc:
        raise DatasetValidationError(
            ["could not compute near-duplicate groups; descriptions lack usable text tokens"]
        ) from exc

    similarities = cosine_similarity(matrix)
    parent = list(range(len(rows)))

    def find(index: int) -> int:
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def union(left: int, right: int) -> None:
        left_root = find(left)
        right_root = find(right)
        if left_root != right_root:
            parent[right_root] = left_root

    for left in range(len(rows)):
        for right in range(left + 1, len(rows)):
            if float(similarities[left, right]) >= NEAR_DUPLICATE_THRESHOLD:
                union(left, right)

    root_to_group: dict[int, int] = {}
    groups: list[int] = []
    for index in range(len(rows)):
        root = find(index)
        if root not in root_to_group:
            root_to_group[root] = len(root_to_group)
        groups.append(root_to_group[root])
    return tuple(groups)


def stratified_group_split(
    dataset: Dataset,
    *,
    test_fraction: float = 0.25,
    random_state: int = 42,
) -> DatasetSplit:
    """Create a category-stratified holdout split with duplicate groups intact."""

    if not 0.0 < test_fraction < 1.0:
        raise ValueError("test_fraction must be between 0 and 1")

    groups = near_duplicate_groups(dataset.rows)
    group_categories: dict[int, set[str]] = {}
    for row, group in zip(dataset.rows, groups, strict=True):
        group_categories.setdefault(group, set()).add(row.category)

    mixed_groups = [group for group, categories in group_categories.items() if len(categories) > 1]
    if mixed_groups:
        raise InsufficientDataError(
            "near-identical descriptions have conflicting categories; "
            "resolve the labels before training"
        )

    test_groups: set[int] = set()
    for category_index, category in enumerate(SUPPORTED_CATEGORIES):
        category_groups = sorted(
            group for group, categories in group_categories.items() if categories == {category}
        )
        if len(category_groups) < 2:
            raise InsufficientDataError(
                f"{category} needs at least 2 independent examples to form train and test sets"
            )

        rng = random.Random(random_state + category_index)
        rng.shuffle(category_groups)
        n_test_groups = max(1, round(len(category_groups) * test_fraction))
        n_test_groups = min(n_test_groups, len(category_groups) - 1)
        test_groups.update(category_groups[:n_test_groups])

    train_indices = tuple(index for index, group in enumerate(groups) if group not in test_groups)
    test_indices = tuple(index for index, group in enumerate(groups) if group in test_groups)

    train_categories = {dataset.rows[index].category for index in train_indices}
    test_categories = {dataset.rows[index].category for index in test_indices}
    if train_categories != set(SUPPORTED_CATEGORIES):
        raise InsufficientDataError("training split is missing one or more categories")
    if test_categories != set(SUPPORTED_CATEGORIES):
        raise InsufficientDataError("test split is missing one or more categories")

    return DatasetSplit(
        train_indices=train_indices,
        test_indices=test_indices,
        groups=groups,
        n_groups=len(set(groups)),
        test_fraction=test_fraction,
        random_state=random_state,
    )


def fixed_holdout_split(
    dataset: Dataset,
    holdout_row_numbers: tuple[int, ...],
    *,
    random_state: int = 42,
) -> DatasetSplit:
    """Use an explicit, frozen holdout while enforcing duplicate-group purity."""

    if not holdout_row_numbers:
        raise ValueError("fixed holdout must contain at least one row")

    known_row_numbers = {row.row_number for row in dataset.rows}
    unknown_row_numbers = sorted(set(holdout_row_numbers) - known_row_numbers)
    if unknown_row_numbers:
        raise ValueError(f"holdout row numbers are not in the dataset: {unknown_row_numbers}")

    holdout_numbers = set(holdout_row_numbers)
    test_indices = tuple(
        index for index, row in enumerate(dataset.rows) if row.row_number in holdout_numbers
    )
    train_indices = tuple(
        index for index, row in enumerate(dataset.rows) if row.row_number not in holdout_numbers
    )
    if not test_indices or not train_indices:
        raise ValueError("fixed holdout must leave both training and test rows")

    groups = near_duplicate_groups(dataset.rows)
    train_groups = {groups[index] for index in train_indices}
    test_groups = {groups[index] for index in test_indices}
    leaked_groups = sorted(train_groups & test_groups)
    if leaked_groups:
        leaked_rows = [
            dataset.rows[index].row_number
            for index, group in enumerate(groups)
            if group in leaked_groups
        ]
        raise InsufficientDataError(
            "near-duplicate group crosses the fixed holdout; adjust the synthetic additions "
            f"or holdout. Affected CSV rows: {leaked_rows}"
        )

    train_categories = {dataset.rows[index].category for index in train_indices}
    test_categories = {dataset.rows[index].category for index in test_indices}
    if train_categories != set(SUPPORTED_CATEGORIES):
        raise InsufficientDataError("training split is missing one or more categories")
    if test_categories != set(SUPPORTED_CATEGORIES):
        raise InsufficientDataError("fixed holdout is missing one or more categories")

    return DatasetSplit(
        train_indices=train_indices,
        test_indices=test_indices,
        groups=groups,
        n_groups=len(set(groups)),
        test_fraction=len(test_indices) / len(dataset.rows),
        random_state=random_state,
        method="fixed holdout",
    )


def split_from_metadata(dataset: Dataset, metadata: dict[str, Any]) -> DatasetSplit:
    """Recreate the exact evaluation split recorded in model metadata."""

    split_metadata = metadata.get("split")
    if not isinstance(split_metadata, dict):
        raise ValueError("model metadata has no split block")

    random_state = int(split_metadata.get("random_state", 42))
    holdout_row_numbers = split_metadata.get("holdout_row_numbers")
    if holdout_row_numbers is not None:
        if not isinstance(holdout_row_numbers, list) or not all(
            isinstance(value, int) for value in holdout_row_numbers
        ):
            raise ValueError("model metadata holdout_row_numbers must be a list of integers")
        return fixed_holdout_split(
            dataset,
            tuple(holdout_row_numbers),
            random_state=random_state,
        )

    test_fraction = split_metadata.get("test_fraction")
    if not isinstance(test_fraction, (int, float)):
        raise ValueError("model metadata split is missing test_fraction")
    return stratified_group_split(
        dataset,
        test_fraction=float(test_fraction),
        random_state=random_state,
    )


def dataset_display_path(path: Path) -> str:
    """Return a non-sensitive, useful path for model metadata."""

    resolved = path.resolve()
    for base in (Path.cwd().resolve(), Path(__file__).resolve().parents[2]):
        try:
            return resolved.relative_to(base).as_posix()
        except ValueError:
            continue
    return path.name
