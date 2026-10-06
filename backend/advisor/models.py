from typing import Literal

from pydantic import BaseModel, Field


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"]
    content: str = Field(min_length=1, max_length=4000)


class AdvisorRequest(BaseModel):
    student_id: str = Field(min_length=1, max_length=64)
    message: str = Field(
        min_length=1,
        max_length=2000,
        description="The student's latest message",
    )
    language: Literal["english", "arabic"] = Field(
        default="english",
        description="The language the advisor should use for the response",
    )
    history: list[ChatMessage] = Field(
        default_factory=list,
        max_length=10,
        description="The recent conversation history",
    )


class AdvisorResponse(BaseModel):
    intent: str
    response: str
    language: str = "english"


class AdvisorVoiceResponse(BaseModel):
    student_id: str
    transcript: str
    response: str
    intent: str
    language: str
    audio_base64: str
