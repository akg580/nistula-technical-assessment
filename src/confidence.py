from typing import Tuple


def compute_confidence(query_type: str, ai_used: bool, property_found: bool) -> float:
    score = 0.4

    if query_type != "unknown":
        score += 0.3
    if property_found:
        score += 0.2
    if ai_used:
        score += 0.1

    return round(min(score, 1.0), 2)


def route_action(confidence: float) -> str:
    if confidence >= 0.8:
        return "auto_reply"
    if confidence >= 0.55:
        return "manual_review"
    return "escalate"


def evaluate(query_type: str, ai_used: bool, property_found: bool) -> Tuple[float, str, bool]:
    confidence = compute_confidence(query_type, ai_used, property_found)
    action = route_action(confidence)
    escalation_required = action == "escalate" or query_type == "unknown"
    return confidence, action, escalation_required
