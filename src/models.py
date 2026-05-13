"""
models.py — Pydantic data models for the Nistula message pipeline.

Three models map to the three stages of the pipeline:
  InboundMessage   → raw webhook payload (exactly as received)
  NormalisedMessage→ unified internal schema (what we pass to AI and store)
  WebhookResponse  → what we return to the caller
"""

from pydantic import BaseModel, Field
from typing import Optional, Literal
from datetime import datetime

# ── Type aliases ─────────────────────────────────────────────────────────────

SourceType = Literal["whatsapp", "booking_com", "airbnb", "instagram", "direct"]

QueryType = Literal[
    "pre_sales_availability",
    "pre_sales_pricing",
    "post_sales_checkin",
    "special_request",
    "complaint",
    "general_enquiry",
]

ActionType = Literal["auto_send", "agent_review", "escalate"]


# ── Models ────────────────────────────────────────────────────────────────────

class InboundMessage(BaseModel):
    """
    Exact shape of the incoming webhook payload.
    booking_ref and property_id are optional — not all channels send them.
    """
    source: SourceType
    guest_name: str = Field(..., min_length=1)
    message: str = Field(..., min_length=1)
    timestamp: datetime
    booking_ref: Optional[str] = None
    property_id: Optional[str] = None


class NormalisedMessage(BaseModel):
    """
    Unified internal schema. Every message, regardless of source channel,
    is converted into this before AI processing or database storage.
    """
    message_id: str                       # UUID generated at ingestion
    source: SourceType
    guest_name: str
    message_text: str                     # renamed from 'message' for clarity
    timestamp: datetime
    booking_ref: Optional[str] = None
    property_id: Optional[str] = None
    query_type: QueryType                 # classifier output


class WebhookResponse(BaseModel):
    """
    Final response returned to the webhook caller.
    """
    message_id: str
    query_type: QueryType
    drafted_reply: str
    confidence_score: float = Field(..., ge=0.0, le=1.0)
    action: ActionType