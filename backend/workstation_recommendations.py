"""AI assisted Python package suggestions for a student's selected course."""

from __future__ import annotations

import re

from pydantic import BaseModel, Field

from backend.advisor.llm import ask_gemini_structured
from workspace.manager import course_environment, validate_requirements


class PackageSuggestion(BaseModel):
    package: str
    reason: str = Field(max_length=180)


class PackageSuggestionList(BaseModel):
    suggestions: list[PackageSuggestion] = Field(max_length=5)


def recommend_course_packages(course: str) -> dict[str, object]:
    """Explain course requirements, allowing AI to rank only packages in the course profile."""
    profile = course_environment(course)
    allowed = ({item.lower().replace("_", "-"): item for item in profile.packages} if profile else None)
    try:
        requirement_context = (
            "Use only these course requirements: " + ", ".join(profile.packages) + "."
            if profile else
            "Infer only essential Python packages from the course title. If the title does not establish a real package need, return an empty list. Do not include general-purpose or merely helpful packages."
        )
        result = ask_gemini_structured(
            "Recommend only Python packages genuinely required by course work; never add optional "
            "or generally useful packages. If none are needed or there is not enough information, "
            "return an empty list. Preserve exact requirement strings when requirements are supplied. "
            + requirement_context + " "
            "Course: " + course,
            PackageSuggestionList,
        )
        accepted: list[dict[str, str]] = []
        seen: set[str] = set()
        for item in result.suggestions:
            try:
                validated = validate_requirements([item.package])[0]
            except ValueError:
                continue
            key = re.split(r"\s*(?:===|==|~=|!=|<=|>=|<|>)", validated, maxsplit=1)[0].lower().replace("_", "-")
            if allowed is not None and key not in allowed:
                continue
            package = allowed[key] if allowed is not None else validated
            if key in seen:
                continue
            accepted.append({"package": package, "reason": item.reason.strip()})
            seen.add(key)
            if len(accepted) == 5:
                break
        if accepted:
            return {"suggestions": accepted, "source": "AI course analysis", "requirements_known": bool(profile)}
    except Exception:
        pass

    if profile and profile.packages:
        return {
            "suggestions": [{"package": requirement, "reason": f"Required for {profile.label}."} for requirement in profile.packages],
            "source": "course requirements",
            "requirements_known": True,
        }
    return {"suggestions": [], "source": "course requirements", "requirements_known": bool(profile)}
