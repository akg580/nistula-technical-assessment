"""
confidence.py — Confidence scoring and action routing.

CONFIDENCE SCORE DESIGN
═══════════════════════
The confidence score answers: "How likely is this AI reply to be correct,
complete, and appropriate to send without a human reviewing it first?"

It is NOT a measure of the AI's linguistic quality. It is a measure of
whether we have enough reliable, structured context to trust the reply.

Two-layer model:
  Layer 1 — Base score (query type)
    How deterministic is the answer? If the property context contains
    everything needed to answer this question type with certainty,
    the base score is high. If the query type structurally requires
    human judgment (complaints, open-ended requests), it starts low.

  Layer 2 — Modifiers (signal quality)
    Positive signals: booking ref present (guest is real/confirmed),
    property_id known (we have correct property data).
    Negative signals: reply too short (likely an error), hedging
    language in reply (AI couldn't find the info), no property_id
    (we used generic context).

Action routing:
  complaint → always "escalate" (hard rule, score-independent)
  >= 0.85   → "auto_send"
  0.60–0.84 → "agent_review"
  < 0.60    → "escalate"
"""

from typing import Optional, Literal

ActionType = Literal["auto_send", "agent_review", "escalate"]


QUERY_TYPE_BASE_SCORES: dict[str, float] = {
    "pre_sales_availability": 0.92,
    "pre_sales_pricing": 0.90,
    "post_sales_checkin": 0.88,
    "general_enquiry": 0.80,
    "special_request": 0.68,
    "complaint": 0.40,
}


HEDGING_PHRASES: list[str] = [
    "i'll confirm",
    "i'll check",
    "will verify",
    "not sure",
    "cannot confirm",
    "i'm not certain",
    "please allow me",
    "i'll get back",
    "will get back",
    "let me check",
]

# Hard cap for complaints — never higher than this regardless of modifiers
COMPLAINT_CONFIDENCE_CAP = 0.55


def calculate_confidence(
    query_type: str,
    booking_ref: Optional[str],
    property_id: Optional[str],
    reply_text: str,
) -> float:
    """
    Calculate a confidence score for the drafted reply.

    Scoring walkthrough:
      1. Start with base score for this query type.
      2. +0.04 if booking_ref is present (confirmed guest context).
      3. -0.08 if no property_id (we used fallback generic context).
      4. -0.06 if reply is very short (<60 chars) — likely a partial or error.
      5. -0.10 if reply contains hedging language — AI signalled uncertainty.
      6. Hard cap at 0.55 for complaints.
      7. Clamp final score to [0.30, 0.97].

    Args:
        query_type:  Classified query type.
        booking_ref: Booking reference if present.
        property_id: Property ID if present.
        reply_text:  The AI-drafted reply text.

    Returns:
        Confidence score as a float rounded to 2 decimal places.
    """
    score = QUERY_TYPE_BASE_SCORES.get(query_type, 0.75)

    # Modifier 1: Booking reference present
    # A booking ref means we can tie the reply to a confirmed guest record.
    # This also means the AI has more grounding context, making errors less likely.
    if booking_ref:
        score += 0.04

    # Modifier 2: No property_id
    # Without a property_id, we used the fallback generic context or guessed villa-b1.
    # The reply may not reflect the correct property's actual details.
    if not property_id:
        score -= 0.08

    # Modifier 3: Reply quality — length check
    # A reply under 60 characters is suspicious (empty template, API hiccup, etc.)
    if len(reply_text) < 60:
        score -= 0.06

    # Modifier 4: Hedging language in the reply
    # If the AI used phrases like "I'll check" or "will confirm", it found a gap
    # in the property context. The reply is likely incomplete and needs human review.
    reply_lower = reply_text.lower()
    if any(phrase in reply_lower for phrase in HEDGING_PHRASES):
        score -= 0.10

    # Hard cap: complaints always need human oversight
    if query_type == "complaint":
        score = min(score, COMPLAINT_CONFIDENCE_CAP)

    # Clamp to valid range
    return round(max(0.30, min(0.97, score)), 2)


def determine_action(confidence: float, query_type: str) -> ActionType:
    """
    Map a confidence score and query type to an action.

    Rules (in priority order):
      1. complaint → always "escalate" (hard rule, confidence-independent).
      2. confidence >= 0.85 → "auto_send".
      3. confidence 0.60–0.84 → "agent_review".
      4. confidence < 0.60 → "escalate".

    Args:
        confidence: Score from calculate_confidence().
        query_type: Classified query type.

    Returns:
        An ActionType string literal.
    """
    if query_type == "complaint":
        return "escalate"

    if confidence >= 0.85:
        return "auto_send"

    if confidence >= 0.60:
        return "agent_review"

    return "escalate"