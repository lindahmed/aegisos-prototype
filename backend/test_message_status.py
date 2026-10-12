"""Sent / delivered / seen status on messages."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

from database.repository import StudentRepository

ANA, BOB, STAFF = "231027905", "231027906", "104217"


def _repository(tmp_path: Path) -> StudentRepository:
    repository = StudentRepository(tmp_path / "messages.db")
    repository.initialize()
    return repository


def _send(repository, sender, recipient=None, sender_type="student", broadcast=False) -> str:
    message_id = str(uuid4())
    repository.create_portal_message({
        "message_id": message_id, "sender_type": sender_type, "sender_id": sender,
        "recipient_type": None if broadcast else "student",
        "recipient_id": None if broadcast else recipient, "is_broadcast": broadcast,
        "body": "hello", "created_at": datetime.now(UTC).isoformat(),
    })
    return message_id


def _mine(repository, actor_type, actor_id, message_id) -> dict:
    return next(m for m in repository.list_portal_messages(actor_type, actor_id)
                if m["message_id"] == message_id)


def test_direct_message_goes_sent_then_delivered_then_seen(tmp_path: Path) -> None:
    repository = _repository(tmp_path)
    message_id = _send(repository, ANA, BOB)
    assert _mine(repository, "student", ANA, message_id)["status"] == "sent"

    repository.mark_portal_messages_delivered("student", BOB)   # Bob's app fetched his inbox
    assert _mine(repository, "student", ANA, message_id)["status"] == "delivered"

    repository.mark_portal_messages_read("student", BOB, [message_id])   # Bob opened it
    sent = _mine(repository, "student", ANA, message_id)
    assert sent["status"] == "seen" and sent["seen_count"] == 1


def test_only_the_sender_gets_a_status_and_you_never_deliver_to_yourself(tmp_path: Path) -> None:
    repository = _repository(tmp_path)
    message_id = _send(repository, ANA, BOB)
    assert _mine(repository, "student", BOB, message_id)["status"] is None
    repository.mark_portal_messages_delivered("student", ANA)    # the sender polling changes nothing
    assert _mine(repository, "student", ANA, message_id)["status"] == "sent"


def test_marking_delivered_twice_is_harmless(tmp_path: Path) -> None:
    repository = _repository(tmp_path)
    message_id = _send(repository, ANA, BOB)
    repository.mark_portal_messages_delivered("student", BOB)
    repository.mark_portal_messages_delivered("student", BOB)
    assert _mine(repository, "student", ANA, message_id)["delivered_count"] == 1


def test_broadcast_reports_how_many_students_received_and_saw_it(tmp_path: Path) -> None:
    repository = _repository(tmp_path)
    message_id = _send(repository, STAFF, sender_type="staff", broadcast=True)
    announcement = _mine(repository, "staff", STAFF, message_id)
    assert announcement["status"] == "sent" and announcement["recipient_count"] >= 2

    repository.mark_portal_messages_delivered("student", ANA)
    repository.mark_portal_messages_delivered("student", BOB)
    repository.mark_portal_messages_read("student", ANA, [message_id])
    announcement = _mine(repository, "staff", STAFF, message_id)
    assert announcement["delivered_count"] == 2 and announcement["seen_count"] == 1
    assert announcement["status"] == "delivered"      # not everyone has seen it yet
