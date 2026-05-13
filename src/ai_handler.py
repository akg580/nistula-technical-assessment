"""
ai_handler.py — Claude API integration layer.

Responsibilities:
  1. Build a structured, context-rich prompt for every message type.
  2. Call the Anthropic /v1/messages endpoint via async httpx.
  3. Extract and return the drafted reply text.
  4. Raise a clear exception on failure so main.py can return a 502.

Design decisions:
  - max_tokens=350: Enough for a thorough reply; too much risks verbosity.
  - temperature not set (defaults to 1.0): Allows natural variation while
    the system prompt enforces format/tone constraints.
  - Separate SYSTEM_PROMPT vs user prompt: System = persona + rules,
    User = the actual data. This matches Anthropic best-practice prompting.
"""

import os
import httpx
from typing import Optional

CLAUDE_API_URL = "https://api.anthropic.com/v1/messages"
CLAUDE_MODEL = "claude-sonnet-4-20250514"
MAX_TOKENS = 350

# ── System prompt ─────────────────────────────────────────────────────────────
# This prompt defines WHO the AI is and HOW it should behave.
# It is injected once per request as the system role.

SYSTEM_PROMPT = """You are a professional guest relations assistant for Nistula Villas, a luxury villa rental company in Goa, India.

You draft warm, accurate, and concise replies to guest messages on behalf of the Nistula team.

TONE AND STYLE:
- Always address the guest by their first name in the opening.
- Tone: warm, calm, professional. Never robotic or corporate.
- Be specific: use actual numbers, times, and dates from the property context.
- Keep replies under 120 words unless the query genuinely requires more detail.
- End with "Warm regards, The Nistula Team" — EXCEPT for complaints, where you sign as "Priya, Guest Relations Manager, Nistula."

HANDLING EACH QUERY TYPE:
- pre_sales_availability: Confirm availability clearly. Mention check-in/check-out times and invite them to book.
- pre_sales_pricing: Give the exact rate calculation. Mention extras proactively (extra guests, chef).
- post_sales_checkin: Provide the specific operational info (WiFi, times, caretaker contact). Be direct and reassuring.
- special_request: Confirm you're happy to help and explain next steps. Do not over-commit.
- complaint: Acknowledge the issue immediately and empathetically. Apologise sincerely. Give a concrete next step. Do NOT be defensive.
- general_enquiry: Answer directly with whatever information is available from the property context.

IMPORTANT CONSTRAINTS:
- If specific information is not in the property context, say "I'll confirm this for you shortly" — never invent details.
- Do not make refund commitments. Acknowledge the concern and escalate language ("our team will review this").
- Return ONLY the reply text. No preamble, no labels, no "Here is the reply:" — just the message itself."""


# ── Prompt builder ────────────────────────────────────────────────────────────

def build_user_prompt(
    guest_name: str,
    source: str,
    query_type: str,
    booking_ref: Optional[str],
    message_text: str,
    property_context: str,
) -> str:
    """
    Constructs the user-turn prompt by injecting all available context.
    Structured clearly so Claude knows what each section is.
    """
    booking_info = (
        f"Booking Reference: {booking_ref}"
        if booking_ref
        else "No booking reference (likely a pre-sales enquiry)"
    )

    readable_query_type = query_type.replace("_", " ").upper()

    return f"""=== PROPERTY CONTEXT ===
{property_context}

=== GUEST DETAILS ===
Guest Name: {guest_name}
Channel: {source.replace('_', '.').title()}
Query Type: {readable_query_type}
{booking_info}

=== GUEST MESSAGE ===
"{message_text}"

Draft a reply to this guest message."""


# ── API call ──────────────────────────────────────────────────────────────────

async def get_claude_reply(
    guest_name: str,
    source: str,
    query_type: str,
    booking_ref: Optional[str],
    message_text: str,
    property_context: str,
) -> str:
    """
    Calls the Claude API and returns the drafted reply text.

    Args:
        guest_name:       Guest's full name.
        source:           Channel the message came from.
        query_type:       Classified query type string.
        booking_ref:      Booking reference if available.
        message_text:     The guest's actual message.
        property_context: Formatted property info string.

    Returns:
        The AI-drafted reply as a plain string.

    Raises:
        ValueError: If ANTHROPIC_API_KEY is not set.
        httpx.HTTPStatusError: If the API returns a non-2xx response.
        httpx.TimeoutException: If the request times out (30s limit).
    """
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        raise ValueError("ANTHROPIC_API_KEY environment variable is not set.")

    prompt = build_user_prompt(
        guest_name=guest_name,
        source=source,
        query_type=query_type,
        booking_ref=booking_ref,
        message_text=message_text,
        property_context=property_context,
    )

    payload = {
        "model": CLAUDE_MODEL,
        "max_tokens": MAX_TOKENS,
        "system": SYSTEM_PROMPT,
        "messages": [{"role": "user", "content": prompt}],
    }

    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }

    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(CLAUDE_API_URL, json=payload, headers=headers)
        response.raise_for_status()

    data = response.json()
    return data["content"][0]["text"].strip()