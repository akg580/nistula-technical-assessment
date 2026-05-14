"""
main.py — FastAPI application entry point.

Pipeline for every incoming webhook:
  1. Validate inbound payload (Pydantic rejects bad shape automatically)
  2. Generate UUID for this message
  3. Classify query type (local regex — no API call)
  4. Build normalised message record
  5. Fetch property context
  6. Call Claude API → get drafted reply
  7. Calculate confidence score
  8. Determine action (auto_send / agent_review / escalate)
  9. Return WebhookResponse

"""

import uuid
import logging
from contextlib import asynccontextmanager
from dotenv import load_dotenv

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
import httpx

from src.models import InboundMessage, NormalisedMessage, WebhookResponse
from src.classifier import classify_query
from src.property_context import get_property_context_string
from src.ai_handler import get_claude_reply
from src.confidence import calculate_confidence, determine_action

# ── Bootstrap ─────────────────────────────────────────────────────────────────

load_dotenv()  # Loads .env file into os.environ at startup

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s  %(levelname)-8s  %(name)s — %(message)s",
)
logger = logging.getLogger("nistula.webhook")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Nistula webhook service starting up…")
    yield
    logger.info("Nistula webhook service shutting down.")


app = FastAPI(
    title="Nistula Guest Message Handler",
    description="Receives guest messages, normalises them, and drafts AI replies.",
    version="1.0.0",
    lifespan=lifespan,
)


# ── Health check ──────────────────────────────────────────────────────────────

@app.get("/health", tags=["ops"])
async def health():
    """Simple liveness check — returns 200 if the service is running."""
    return {"status": "ok", "service": "nistula-webhook"}


# ── Main webhook endpoint ─────────────────────────────────────────────────────

@app.post(
    "/webhook/message",
    response_model=WebhookResponse,
    tags=["webhook"],
    summary="Receive and process an inbound guest message",
)
async def handle_message(payload: InboundMessage):
    """
    Main pipeline endpoint.

    Accepts a raw guest message from any supported channel, runs it through
    classification + AI drafting, and returns a structured reply with confidence score.
    """

   
    message_id = str(uuid.uuid4())
    logger.info(
        f"[{message_id}] Received message — source={payload.source} "
        f"guest={payload.guest_name!r} property={payload.property_id}"
    )

    # ── Step 2: Classify query type ───────────────────────────────────────────
    query_type = classify_query(payload.message)
    logger.info(f"[{message_id}] Classified as: {query_type}")

    # ── Step 3: Build normalised message ──────────────────────────────────────
    # This is the canonical internal representation stored/passed forward.
    normalised = NormalisedMessage(
        message_id=message_id,
        source=payload.source,
        guest_name=payload.guest_name,
        message_text=payload.message,
        timestamp=payload.timestamp,
        booking_ref=payload.booking_ref,
        property_id=payload.property_id,
        query_type=query_type,
    )

    # ── Step 4: Get property context ──────────────────────────────────────────
    # Default to villa-b1 if property_id not provided — common for pre-sales.
    effective_property_id = normalised.property_id or "villa-b1"
    property_context = get_property_context_string(effective_property_id)

    # ── Step 5: Call Claude API ───────────────────────────────────────────────
    drafted_reply = await get_claude_reply(
        guest_name=normalised.guest_name,
        source=normalised.source,
        query_type=normalised.query_type,
        booking_ref=normalised.booking_ref,
        message_text=normalised.message_text,
        property_context=property_context,
    )
    logger.info(f"[{message_id}] AI reply drafted ({len(drafted_reply)} chars)")

    # ── Step 6: Score + route ─────────────────────────────────────────────────
    confidence = calculate_confidence(
        query_type=normalised.query_type,
        booking_ref=normalised.booking_ref,
        property_id=normalised.property_id,
        reply_text=drafted_reply,
    )
    action = determine_action(confidence, normalised.query_type)
    logger.info(f"[{message_id}] confidence={confidence} action={action}")

    # ── Step 7: Return response ───────────────────────────────────────────────
    return WebhookResponse(
        message_id=message_id,
        query_type=normalised.query_type,
        drafted_reply=drafted_reply,
        confidence_score=confidence,
        action=action,
    )


# ── Global error handlers ─────────────────────────────────────────────────────

@app.exception_handler(httpx.HTTPStatusError)
async def claude_api_error_handler(request: Request, exc: httpx.HTTPStatusError):
    """Claude API returned a non-2xx status (e.g. 401 invalid key, 529 overload)."""
    logger.error(f"Claude API error: {exc.response.status_code} — {exc.response.text}")
    return JSONResponse(
        status_code=502,
        content={
            "error": "AI service unavailable",
            "detail": f"Claude API returned {exc.response.status_code}",
        },
    )


@app.exception_handler(httpx.TimeoutException)
async def timeout_error_handler(request: Request, exc: httpx.TimeoutException):
    """Claude API timed out (> 30s)."""
    logger.error("Claude API request timed out")
    return JSONResponse(
        status_code=504,
        content={"error": "AI service timeout", "detail": "Claude API did not respond in time"},
    )


@app.exception_handler(ValueError)
async def value_error_handler(request: Request, exc: ValueError):
    """Catches missing API key and similar config errors."""
    logger.error(f"Configuration error: {exc}")
    return JSONResponse(
        status_code=500,
        content={"error": "Server configuration error", "detail": str(exc)},
    )


@app.exception_handler(Exception)
async def generic_error_handler(request: Request, exc: Exception):
    """Catch-all for unexpected errors — logs full traceback."""
    logger.exception(f"Unexpected error processing request: {exc}")
    return JSONResponse(
        status_code=500,
        content={"error": "Internal server error", "detail": "An unexpected error occurred"},
    )
