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
    history: list[ChatMessage] = Field(
        default_factory=list,
        max_length=10,
        description="The recent conversation history",
    )


class AdvisorResponse(BaseModel):
    intent: str
    response: str
