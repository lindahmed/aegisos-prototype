import os
import json
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


class AdvisorConfigurationError(RuntimeError):
    """Raised when Advisor AI is not configured."""


ModelT = TypeVar("ModelT", bound=BaseModel)


def ask_gemini(prompt: str) -> str:
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key or genai is None:
        raise AdvisorConfigurationError(
            "Advisor AI is not configured. Add GEMINI_API_KEY to the project .env file."
        )

    model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash-lite")
    client = genai.Client(api_key=api_key)
    response = client.models.generate_content(
        model=model,
        contents=prompt,
    )

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
    model = os.getenv("GEMINI_MODEL", "gemini-3.5-flash-lite")
    client = genai.Client(api_key=api_key)
    response = client.models.generate_content(
        model=model,
        contents=prompt,
        config={"response_mime_type": "application/json"},
    )
    if not response.text:
        raise RuntimeError("Gemini returned an empty response.")
    try:
        return schema.model_validate(json.loads(response.text))
    except (json.JSONDecodeError, ValueError) as error:
        raise RuntimeError("Gemini returned an invalid structured recommendation.") from error
