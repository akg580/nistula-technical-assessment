from typing import Literal, Optional

from pydantic import BaseModel, Field


class IncomingMessage(BaseModel):
    sender_id: str = Field(..., description="Unique identifier for the customer")
    text: str = Field(..., description="Customer message text")
    property_id: Optional[str] = Field(default=None, description="Optional property reference")
    channel: Optional[str] = Field(default="web", description="Source channel")


class WebhookRequest(BaseModel):
    event_id: str
    timestamp: str
    message: IncomingMessage


class WebhookResponse(BaseModel):
    action: Literal["auto_reply", "manual_review", "escalate"]
    confidence: float
    query_type: str
    response: str
    escalation_required: bool
