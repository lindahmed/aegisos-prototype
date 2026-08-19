import os
from pathlib import Path

from dotenv import load_dotenv
from google import genai


PROJECT_ROOT = Path(__file__).resolve().parents[2]
load_dotenv(PROJECT_ROOT / ".env")


class AdvisorConfigurationError(RuntimeError):
    """Raised when Advisor AI is not configured."""


def ask_gemini(prompt: str) -> str:
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
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
