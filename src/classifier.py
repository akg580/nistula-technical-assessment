import re
from typing import Dict


QUERY_PATTERNS: Dict[str, re.Pattern[str]] = {
    "availability": re.compile(r"\b(available|availability|vacant|move in|move-in)\b", re.I),
    "pricing": re.compile(r"\b(price|pricing|rent|cost|deposit|fees?)\b", re.I),
    "amenities": re.compile(r"\b(amenities|gym|pool|parking|wifi|pet|pets)\b", re.I),
    "location": re.compile(r"\b(location|nearby|distance|neighborhood|area)\b", re.I),
    "maintenance": re.compile(r"\b(repair|maintenance|broken|leak|issue|problem)\b", re.I),
    "booking": re.compile(r"\b(schedule|book|tour|visit|appointment|viewing)\b", re.I),
    "greeting": re.compile(r"\b(hello|hi|hey|good morning|good afternoon)\b", re.I),
}


def classify_query(message_text: str) -> str:
    for query_type, pattern in QUERY_PATTERNS.items():
        if pattern.search(message_text):
            return query_type
    return "unknown"
