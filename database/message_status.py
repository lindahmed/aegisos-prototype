"""Sent / delivered / seen status for the messages a person has sent.

The database stores two facts per recipient:
  * delivered: the recipient's app or website fetched their inbox (portal_message_deliveries),
  * seen: the recipient opened the message (portal_message_reads).

Only the sender gets a status.  A direct message is "seen" once its recipient has read it; a
broadcast to all students reports how many students it was delivered to and seen by.
"""

from __future__ import annotations

from typing import Any

# Extra columns the repositories add to the message query (counted in SQL).
STATUS_COLUMNS_SQL = """
    (SELECT COUNT(*) FROM portal_message_deliveries d
      WHERE d.message_id = m.message_id) AS delivered_count,
    (SELECT COUNT(*) FROM portal_message_reads rr
      WHERE rr.message_id = m.message_id
        AND NOT (rr.reader_type = m.sender_type AND rr.reader_id = m.sender_id)) AS read_count,
    CASE WHEN m.is_broadcast THEN (SELECT COUNT(*) FROM students) ELSE 1 END AS recipient_count
"""


def apply_message_status(
    messages: list[dict[str, Any]], actor_type: str, actor_id: str
) -> list[dict[str, Any]]:
    """Turn the raw counts into `status` ("sent" | "delivered" | "seen") for the actor's own messages."""
    for message in messages:
        delivered = int(message.pop("delivered_count", 0) or 0)
        seen = int(message.pop("read_count", 0) or 0)
        total = int(message.pop("recipient_count", 0) or 0)
        own = (
            message["sender_type"] == actor_type
            and str(message["sender_id"]) == str(actor_id)
        )
        if not own:
            message["status"] = None
            continue
        delivered = max(delivered, seen)  # a message that was opened was certainly delivered
        if total > 0 and seen >= total:
            status = "seen"
        elif seen > 0 and not message.get("is_broadcast"):
            status = "seen"
        elif delivered > 0:
            status = "delivered"
        else:
            status = "sent"
        message.update(
            status=status, delivered_count=delivered, seen_count=seen, recipient_count=total
        )
    return messages
