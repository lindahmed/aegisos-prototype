from types import SimpleNamespace

import pytest

from backend.advisor import llm


class GeminiError(RuntimeError):
    def __init__(self, code: int) -> None:
        super().__init__(f"Gemini failed with {code}")
        self.code = code


class FakeModels:
    def __init__(self, responses: dict[str, object]) -> None:
        self.responses = responses
        self.calls: list[tuple[str, dict[str, str] | None]] = []

    def generate_content(self, *, model, contents, config=None):
        self.calls.append((model, config))
        result = self.responses[model]
        if isinstance(result, Exception):
            raise result
        return result


def install_fake_client(monkeypatch, responses: dict[str, object]) -> FakeModels:
    models = FakeModels(responses)
    monkeypatch.setattr(
        llm,
        "genai",
        SimpleNamespace(Client=lambda api_key: SimpleNamespace(models=models)),
    )
    monkeypatch.setenv("GEMINI_API_KEY", "test-key")
    return models


def test_ask_gemini_falls_back_after_transient_error(monkeypatch) -> None:
    models = install_fake_client(
        monkeypatch,
        {
            "primary-model": GeminiError(503),
            "fallback-model": SimpleNamespace(text="Fallback answer"),
        },
    )
    monkeypatch.setenv("GEMINI_MODEL", "primary-model")
    monkeypatch.setenv("GEMINI_FALLBACK_MODELS", "fallback-model")

    assert llm.ask_gemini("Hello") == "Fallback answer"
    assert models.calls == [("primary-model", None), ("fallback-model", None)]


def test_ask_gemini_does_not_hide_non_retryable_error(monkeypatch) -> None:
    models = install_fake_client(
        monkeypatch,
        {
            "primary-model": GeminiError(400),
            "fallback-model": SimpleNamespace(text="Should not be used"),
        },
    )
    monkeypatch.setenv("GEMINI_MODEL", "primary-model")
    monkeypatch.setenv("GEMINI_FALLBACK_MODELS", "fallback-model")

    with pytest.raises(GeminiError, match="400"):
        llm.ask_gemini("Hello")

    assert models.calls == [("primary-model", None)]


def test_structured_generation_keeps_config_when_falling_back(monkeypatch) -> None:
    class Result(llm.BaseModel):
        value: str

    models = install_fake_client(
        monkeypatch,
        {
            "primary-model": GeminiError(429),
            "fallback-model": SimpleNamespace(text='{"value":"ok"}'),
        },
    )
    monkeypatch.setenv("GEMINI_MODEL", "primary-model")
    monkeypatch.setenv("GEMINI_FALLBACK_MODELS", "fallback-model")

    result = llm.ask_gemini_structured("Hello", Result)

    expected_config = {"response_mime_type": "application/json"}
    assert result.value == "ok"
    assert models.calls == [
        ("primary-model", expected_config),
        ("fallback-model", expected_config),
    ]
