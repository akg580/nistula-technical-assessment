"""
classifier.py — Rule-based query type classifier.

Design decision: We use regex over a second LLM call.
Reasons:
  1. Speed — regex runs in microseconds; LLM call adds ~1s latency.
  2. Cost — every extra API call adds expense at scale.
  3. Reliability — complaints must ALWAYS be caught; regex doesn't hallucinate.
  4. The categories are clean enough that keyword matching is ~95%+ accurate.

Priority order matters: a message combining a complaint with a question
should route as a complaint (requires human escalation regardless).
"""

import re
from typing import Literal

QueryType = Literal[
    "pre_sales_availability",
    "pre_sales_pricing",
    "post_sales_checkin",
    "special_request",
    "complaint",
    "general_enquiry",
]

# ── Pattern dictionary ────────────────────────────────────────────────────────
# Each key is a QueryType; value is a list of regex patterns (OR logic within a type).
# Patterns are case-insensitive (applied after .lower()).

PATTERNS: dict[str, list[str]] = {
    "complaint": [
        r"\b(not working|broken|doesn'?t work|isn'?t working)\b",
        r"\b(unacceptable|disgusting|terrible|awful|horrible|dirty)\b",
        r"\b(refund|compensation|money back|charge back)\b",
        r"\b(not happy|unhappy|disappointed|furious|angry|livid)\b",
        r"\b(no hot water|no water|no power|no electricity|no ac|no wifi)\b",
        r"\b(worst|pathetic|useless|complain|complaint)\b",
        r"\b(this is not|this is completely|totally unacceptable)\b",
    ],
    "post_sales_checkin": [
        r"\b(wifi|wi-fi|password|internet)\b",
        r"\b(check.?in time|check.?out time|what time can we|when can we)\b",
        r"\b(key|access code|door|entrance|gate)\b",
        r"\b(address|directions?|how to (reach|get|find)|location)\b",
        r"\b(caretaker|contact (number|details)|emergency number)\b",
        r"\b(already booked|our booking|confirmed booking|we have a reservation)\b",
    ],
    "special_request": [
        r"\b(early check.?in|late check.?out)\b",
        r"\b(airport (transfer|pickup|pick.?up|drop)|cab|taxi)\b",
        r"\b(chef|cook|meal|dinner|breakfast|lunch|catering)\b",
        r"\b(birthday|anniversary|honeymoon|celebration|decor(ation)?)\b",
        r"\b(arrange|request|can you organise|could you organise)\b",
        r"\b(babysitter|cot|crib|high chair|extra bed)\b",
    ],
    "pre_sales_pricing": [
        r"\b(rate|price|pricing|cost|how much|charges?|fee|tariff)\b",
        r"\b(per night|nightly rate|total (cost|price|amount))\b",
        r"\b(inr|rupee|rs\.?|₹)\b",
        r"\b(\d+\s*(adult|guest|person|people|night|pax))\b",
        r"\b(what (would|will|does) it cost|quote|estimate)\b",
    ],
    "pre_sales_availability": [
        r"\b(available|availability|is (it|the villa) free|any (opening|slot))\b",
        r"\b(book|booking|want to (book|reserve|stay))\b",
        r"\b(from .{3,20} to .{3,20}|between .{3,20} and .{3,20})\b",
        r"\b(check.?in|check.?out|arrive|arrival|departure)\b",
        r"\b(april|may|june|july|august|september|october|november|december|january|february|march)\b",
        r"\b(\d{1,2}(st|nd|rd|th)?\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec))\b",
    ],
}

# Ordered by escalation priority — first match wins
PRIORITY_ORDER: list[str] = [
    "complaint",          # Must escalate — check first, always
    "post_sales_checkin", # Confirmed guest with specific operational need
    "special_request",    # Confirmed or pre-sales with service request
    "pre_sales_pricing",  # Pricing before availability (often asked together)
    "pre_sales_availability",
    # general_enquiry is the fallback — no pattern needed
]


def classify_query(message: str) -> QueryType:
    """
    Classify a guest message into a QueryType.

    Algorithm:
      1. Lowercase the message.
      2. Walk through PRIORITY_ORDER; for each type, try all its patterns.
      3. First match wins.
      4. If nothing matches → 'general_enquiry'.

    Args:
        message: The raw guest message string.

    Returns:
        A QueryType string literal.
    """
    msg_lower = message.lower()

    for query_type in PRIORITY_ORDER:
        patterns = PATTERNS.get(query_type, [])
        for pattern in patterns:
            if re.search(pattern, msg_lower):
                return query_type  # type: ignore[return-value]

    return "general_enquiry"