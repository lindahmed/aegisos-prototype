from __future__ import annotations

import hashlib
import math
import re


EMBEDDING_DIMENSIONS = 768
_WORD_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9_+.#-]*")
_REQUESTED_WEEK_RE = re.compile(
    r"\b(?:lecture|lec|week|w)\s*(?:number|no\.?|#)?\s*[-_:]?\s*(\d{1,2})\b",
    re.IGNORECASE,
)


def search_terms(text: str) -> list[str]:
    """Return normalized terms while discarding very short query noise."""
    return [
        token.casefold()
        for token in _WORD_RE.findall(text)
        if len(token) > 2 or token.isdigit()
    ]


def requested_week(text: str) -> int | None:
    """Return an explicitly requested lecture/week number, when present."""
    match = _REQUESTED_WEEK_RE.search(text)
    if not match:
        return None
    number = int(match.group(1))
    return number if 1 <= number <= 16 else None


def embed_text(text: str, dimensions: int = EMBEDDING_DIMENSIONS) -> list[float]:
    """Create a deterministic local embedding for offline and test operation.

    The feature-hashing representation keeps ingestion functional without an
    external model. The PostgreSQL schema uses the same fixed dimensions, so a
    hosted semantic provider can replace this implementation without a schema
    migration.
    """
    vector = [0.0] * dimensions
    terms = search_terms(text)
    for position, term in enumerate(terms):
        features = (term, f"{term}:{position % 7}")
        for weight, feature in ((1.0, features[0]), (0.2, features[1])):
            digest = hashlib.blake2b(feature.encode("utf-8"), digest_size=8).digest()
            value = int.from_bytes(digest, "big")
            index = value % dimensions
            vector[index] += weight if value & 1 else -weight
    magnitude = math.sqrt(sum(value * value for value in vector))
    if magnitude:
        vector = [value / magnitude for value in vector]
    return vector


def cosine_similarity(left: list[float], right: list[float]) -> float:
    if not left or len(left) != len(right):
        return 0.0
    return sum(a * b for a, b in zip(left, right, strict=True))
