# Nistula Guest Message Handler

A FastAPI backend that receives inbound guest messages from any channel, normalises them into a unified schema, drafts AI replies via the Claude API, and returns a confidence-scored response with an action recommendation.

---

## Repository Structure

```
nistula-technical-assessment/
├── src/
│   ├── main.py               # FastAPI app, webhook endpoint, pipeline orchestration
│   ├── models.py             # Pydantic data models (InboundMessage, NormalisedMessage, WebhookResponse)
│   ├── classifier.py         # Rule-based query type classifier (regex, no extra API call)
│   ├── property_context.py   # Mock property data store and context string builder
│   ├── ai_handler.py         # Claude API integration — prompt construction and async call
│   ├── confidence.py         # Confidence scoring and action routing logic
│   └── test_requests.py      # Manual test suite (7 test cases, all query types)
├── schema.sql                # Part 2 — PostgreSQL schema with design commentary
├── thinking.md               # Part 3 — Written answers to the 3am scenario
├── requirements.txt          # Python dependencies
├── .env.example              # Template — copy to .env and fill in your key
└── README.md
```

---

## Setup and Running

### Prerequisites
- Python 3.11+
- An Anthropic API key

### Steps

```bash
# 1. Clone the repository
git clone https://github.com/akg580/nistula-technical-assessment.git
cd nistula-technical-assessment

# 2. Create and activate a virtual environment
python -m venv venv
source venv/bin/activate        # macOS/Linux
# venv\Scripts\activate         # Windows

# 3. Install dependencies
pip install -r requirements.txt

# 4. Set up environment variables
cp .env.example .env
# Open .env and add your ANTHROPIC_API_KEY

# 5. Run the server
uvicorn src.main:app --reload --port 8000
```

The API will be available at `http://localhost:8000`.

Interactive docs: `http://localhost:8000/docs`

### Running Tests

With the server running in one terminal, open a second terminal:

```bash
cd nistula-technical-assessment
python src/test_requests.py
```

This runs 7 test cases covering all six query types, a missing-field edge case, and a complaint (which must always return `action: escalate`).

---

## API Reference

### `POST /webhook/message`

**Request body:**
```json
{
  "source": "whatsapp",
  "guest_name": "Rahul Sharma",
  "message": "Is the villa available from April 20 to 24? What is the rate for 2 adults?",
  "timestamp": "2026-05-05T10:30:00Z",
  "booking_ref": "NIS-2024-0891",
  "property_id": "villa-b1"
}
```

`source` must be one of: `whatsapp`, `booking_com`, `airbnb`, `instagram`, `direct`

`booking_ref` and `property_id` are optional.

**Response:**
```json
{
  "message_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
  "query_type": "pre_sales_availability",
  "drafted_reply": "Hi Rahul! Great news — Villa B1 is available from April 20 to 24...",
  "confidence_score": 0.96,
  "action": "auto_send"
}
```

### `GET /health`
Returns `{"status": "ok"}` — liveness check for monitoring.

---

## Confidence Scoring Logic

The confidence score answers: **"How likely is this AI reply to be correct, complete, and appropriate to send without human review?"**

It is deliberately NOT a measure of the AI's writing quality. It is a measure of whether our structured context is sufficient to trust the reply.

### Two-layer model

**Layer 1 — Base score (query type)**

The base score reflects how deterministic the answer is given the property context we have:

| Query Type | Base Score | Reasoning |
|---|---|---|
| `pre_sales_availability` | 0.92 | Availability data is explicit in context; answer is binary |
| `pre_sales_pricing` | 0.90 | Rates are fixed; calculation is straightforward |
| `post_sales_checkin` | 0.88 | WiFi, times, caretaker all in context; slight reduction for follow-up unknowns |
| `general_enquiry` | 0.80 | Most questions answerable, but category is open-ended |
| `special_request` | 0.68 | AI can draft acknowledgment; cannot confirm service delivery |
| `complaint` | 0.40 | Structurally requires human judgment; hard-capped at 0.55 |

**Layer 2 — Modifiers (signal quality)**

Applied after the base score:

| Modifier | Effect | Reasoning |
|---|---|---|
| `booking_ref` present | +0.04 | Guest is confirmed; context is grounded in a real record |
| No `property_id` | −0.08 | Used fallback/generic context; reply may not match actual property |
| Reply under 60 chars | −0.06 | Likely an error, API hiccup, or empty template |
| Hedging language in reply | −0.10 | AI signalled it couldn't find the answer — human should review |

**Final clamping:** Score is clamped to [0.30, 0.97]. A score of 1.0 is never returned — there is always some uncertainty.

**Complaint hard cap:** Complaint confidence is capped at 0.55 regardless of modifiers. No complaint reply should ever auto-send.

### Action routing

| Score | Action | Meaning |
|---|---|---|
| `complaint` (any score) | `escalate` | Hard rule — human always reviews complaints |
| ≥ 0.85 | `auto_send` | High confidence — send without review |
| 0.60–0.84 | `agent_review` | Moderate confidence — queue for human editing |
| < 0.60 | `escalate` | Low confidence or ambiguous — requires human intervention |

---

## Design Decisions

### Why regex classification instead of a second LLM call?
Speed, cost, and reliability. Regex runs in microseconds with zero token cost. The query categories are rule-based enough that pattern matching achieves ~95%+ accuracy. Most critically: complaints must always be caught reliably — regex never hallucinates. A second LLM call would add ~1s latency and cost on every request at scale.

### Why `httpx` async instead of the Anthropic SDK?
Explicit control. Using `httpx` directly makes the headers, versioning, and payload structure visible in the codebase. Anyone reading `ai_handler.py` sees exactly what is being sent to Claude without needing to understand an SDK's abstraction layer. For a production system, switching to the official SDK is straightforward.

### Why is `raw_payload` a JSONB column in the schema?
Different channels send different metadata fields. WhatsApp might send a phone number, Airbnb sends a listing ID, Booking.com sends a property manager ref. Storing the raw JSON preserves all this without requiring schema migrations every time a new channel is added. The normalised columns cover the fields we always need; JSONB covers the rest.

### Why separate `ai_drafted_reply` and `final_reply` in the schema?
To preserve the original AI output even when an agent edits it. The delta between `ai_drafted_reply` and `final_reply` is training data — over time it shows us exactly where the AI falls short and for which query types agents are making the most changes. This is how the system gets better.

---

## What I Would Add With More Time

- **Rate limiting** on the webhook endpoint (prevent abuse)
- **Webhook signature verification** (validate requests are from known sources)
- **Async task queue** (Celery + Redis) so the webhook returns immediately and AI processing happens in the background
- **Database integration** (replace in-memory mock with actual Postgres calls)
- **Retry logic** on Claude API calls with exponential backoff
- **Unit tests** with `pytest` and mocked API responses
- **Docker + docker-compose** for one-command local setup
