from fastapi import FastAPI

from src.ai_handler import generate_ai_response
from src.classifier import classify_query
from src.confidence import evaluate
from src.models import WebhookRequest, WebhookResponse
from src.property_context import format_property_context, get_property_context

app = FastAPI(title="Nistula Technical Assessment", version="1.0.0")


@app.get("/health")
def health_check() -> dict:
    return {"status": "ok"}


@app.post("/webhook", response_model=WebhookResponse)
def webhook(payload: WebhookRequest) -> WebhookResponse:
    query_text = payload.message.text
    query_type = classify_query(query_text)

    property_data = get_property_context(payload.message.property_id)
    context_text = format_property_context(property_data)

    ai_response, ai_used = generate_ai_response(query_text, context_text, query_type)
    confidence, action, escalation_required = evaluate(
        query_type=query_type,
        ai_used=ai_used,
        property_found=property_data is not None,
    )

    return WebhookResponse(
        action=action,
        confidence=confidence,
        query_type=query_type,
        response=ai_response,
        escalation_required=escalation_required,
    )
