from __future__ import annotations

import base64
import io
from typing import Callable


class VoiceConfigurationError(RuntimeError):
    """Raised when voice dependencies are not installed or configured."""


class VoiceProcessingError(RuntimeError):
    """Raised when speech recognition or synthesis fails."""


LANGUAGE_CODES: dict[str, dict[str, str]] = {
    "english": {"stt": "en-US", "tts": "en"},
    "arabic": {"stt": "ar-SA", "tts": "ar"},
}


# Lazy imports so the API still starts when voice libraries are not installed.

def _get_speech_recognition():
    try:
        import speech_recognition as sr
        return sr
    except ImportError as error:
        raise VoiceConfigurationError(
            "Speech recognition requires the 'SpeechRecognition' package. "
            "Install backend requirements or disable voice features."
        ) from error


def _get_gtts():
    try:
        from gtts import gTTS
        return gTTS
    except ImportError as error:
        raise VoiceConfigurationError(
            "Text-to-speech requires the 'gTTS' package. "
            "Install backend requirements or disable voice features."
        ) from error


def _get_pydub():
    try:
        from pydub import AudioSegment
        return AudioSegment
    except ImportError:
        return None


def _normalize_to_wav(audio_bytes: bytes) -> bytes:
    """Convert uploaded audio to WAV for the speech recognizer."""
    sr = _get_speech_recognition()
    try:
        source = io.BytesIO(audio_bytes)
        with sr.AudioFile(source) as _:
            return audio_bytes
    except (ValueError, sr.exceptions.WaveError):
        AudioSegment = _get_pydub()
        if AudioSegment is None:
            raise VoiceProcessingError(
                "Uploaded audio is not a WAV file and pydub is not installed. "
                "Please upload WAV audio or install pydub with ffmpeg support."
            ) from None
        try:
            segment = AudioSegment.from_file(io.BytesIO(audio_bytes))
            output = io.BytesIO()
            segment.export(output, format="wav")
            return output.getvalue()
        except Exception as error:
            raise VoiceProcessingError(
                "Could not convert uploaded audio to WAV. "
                "Ensure the file is a valid audio format and ffmpeg is available."
            ) from error


def transcribe_audio(audio_bytes: bytes, language: str = "english") -> str:
    """Convert student speech to text.

    Supports english and arabic.  Audio should be WAV; other formats are
    converted if pydub is available.
    """
    sr = _get_speech_recognition()
    wav_bytes = _normalize_to_wav(audio_bytes)
    recognizer = sr.Recognizer()
    source = io.BytesIO(wav_bytes)

    try:
        with sr.AudioFile(source) as audio_source:
            audio_data = recognizer.record(audio_source)
        code = LANGUAGE_CODES.get(language, LANGUAGE_CODES["english"])["stt"]
        return recognizer.recognize_google(audio_data, language=code)
    except sr.UnknownValueError as error:
        raise VoiceProcessingError("Could not understand the audio. Please speak clearly and try again.") from error
    except sr.RequestError as error:
        raise VoiceProcessingError("Speech recognition service is unavailable. Try again later.") from error
    except Exception as error:
        raise VoiceProcessingError(f"Transcription failed: {error}") from error


def synthesize_speech(text: str, language: str = "english") -> bytes:
    """Convert advisor text response to speech.

    Returns MP3 audio bytes.  Supports english and arabic.
    """
    gTTS = _get_gtts()
    code = LANGUAGE_CODES.get(language, LANGUAGE_CODES["english"])["tts"]
    try:
        tts = gTTS(text=text, lang=code, slow=False)
        output = io.BytesIO()
        tts.write_to_fp(output)
        return output.getvalue()
    except Exception as error:
        raise VoiceProcessingError(f"Speech synthesis failed: {error}") from error


def encode_audio(audio_bytes: bytes) -> str:
    return base64.b64encode(audio_bytes).decode("utf-8")


def decode_audio(audio_base64: str) -> bytes:
    return base64.b64decode(audio_base64)


def get_voice_pipeline() -> tuple[Callable[[bytes, str], str], Callable[[str, str], bytes]]:
    """Return the (transcribe, synthesize) functions for dependency injection."""
    return transcribe_audio, synthesize_speech
