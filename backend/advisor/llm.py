import json
import logging
import os
from pathlib import Path
from typing import TypeVar

from dotenv import load_dotenv
from pydantic import BaseModel

try:
    from google import genai
except ImportError:  # keeps non-AI API paths usable before optional AI setup
    genai = None


PROJECT_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(PROJECT_ROOT / ".env")

logger = logging.getLogger(__name__)

DEFAULT_GEMINI_MODEL = "gemini-3.5-flash"
DEFAULT_GEMINI_FALLBACK_MODELS = ("gemini-3.5-flash-lite",)
RETRYABLE_GEMINI_STATUS_CODES = {429, 500, 502, 503, 504}


class AdvisorConfigurationError(RuntimeError):
    """Raised when Advisor AI is not configured."""


ModelT = TypeVar("ModelT", bound=BaseModel)


def _gemini_models() -> tuple[str, ...]:
    primary = os.getenv("GEMINI_MODEL", DEFAULT_GEMINI_MODEL).strip()
    configured_fallbacks = os.getenv("GEMINI_FALLBACK_MODELS")
    fallbacks = (
        tuple(model.strip() for model in configured_fallbacks.split(","))
        if configured_fallbacks is not None
        else DEFAULT_GEMINI_FALLBACK_MODELS
    )
    return tuple(dict.fromkeys(model for model in (primary, *fallbacks) if model))


def _is_retryable_gemini_error(error: Exception) -> bool:
    status_code = getattr(error, "code", None)
    if status_code is None:
        status_code = getattr(error, "status_code", None)
    try:
        return int(status_code) in RETRYABLE_GEMINI_STATUS_CODES
    except (TypeError, ValueError):
        return False


def _generate_content(prompt: str, *, config: dict[str, str] | None = None):
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"])
    models = _gemini_models()

    for index, model in enumerate(models):
        try:
            return client.models.generate_content(
                model=model,
                contents=prompt,
                config=config,
            )
        except Exception as error:
            has_fallback = index + 1 < len(models)
            if not has_fallback or not _is_retryable_gemini_error(error):
                raise
            logger.warning(
                "Gemini model %s is temporarily unavailable; trying %s.",
                model,
                models[index + 1],
            )

    raise RuntimeError("No Gemini models are configured.")


def ask_gemini(prompt: str) -> str:
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key or genai is None:
        raise AdvisorConfigurationError(
            "Advisor AI is not configured. Add GEMINI_API_KEY to the project .env file."
        )

    response = _generate_content(prompt)

    if not response.text:
        raise RuntimeError("Gemini returned an empty response.")

    return response.text.strip()


def ask_gemini_structured(prompt: str, schema: type[ModelT]) -> ModelT:
    """Use the configured Gemini client for a small validated JSON response."""
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key or genai is None:
        raise AdvisorConfigurationError(
            "Advisor AI is not configured. Add GEMINI_API_KEY to the project .env file."
        )
    response = _generate_content(
        prompt,
        config={"response_mime_type": "application/json"},
    )
    if not response.text:
        raise RuntimeError("Gemini returned an empty response.")
    try:
        return schema.model_validate(json.loads(response.text))
    except (json.JSONDecodeError, ValueError) as error:
        raise RuntimeError("Gemini returned an invalid structured recommendation.") from error
