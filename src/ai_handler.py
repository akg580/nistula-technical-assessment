import os
from typing import Tuple

from dotenv import load_dotenv

load_dotenv()


def _fallback_response(query_type: str) -> str:
    fallback_map = {
        "availability": "I can help with availability. Please share your move-in timeline.",
        "pricing": "I can help with pricing. Please share your preferred property and budget range.",
        "amenities": "I can help with amenities. Tell me which facilities matter most to you.",
        "location": "I can help with location details. Tell me the city or neighborhood preference.",
        "maintenance": "I can help with maintenance. Please describe the issue and urgency.",
        "booking": "I can help schedule a tour. Please share your preferred date and time.",
        "greeting": "Hello! I can help with property availability, pricing, amenities, or tours.",
    }
    return fallback_map.get(
        query_type,
        "Thanks for reaching out. A team member will review your query shortly.",
    )


def generate_ai_response(query: str, context_text: str, query_type: str) -> Tuple[str, bool]:
    api_key = os.getenv("ANTHROPIC_API_KEY")
    model = os.getenv("CLAUDE_MODEL", "claude-3-5-sonnet-20241022")

    if not api_key:
        return _fallback_response(query_type), False

    try:
        from anthropic import Anthropic

        client = Anthropic(api_key=api_key)
        prompt = (
            "You are a real-estate support assistant.\n"
            f"Query type: {query_type}\n"
            f"Property context: {context_text}\n"
            f"User query: {query}\n"
            "Provide a concise, helpful response."
        )
        message = client.messages.create(
            model=model,
            max_tokens=300,
            temperature=0.2,
            messages=[{"role": "user", "content": prompt}],
        )
        response_text = message.content[0].text.strip()
        return response_text, True
    except Exception:
        return _fallback_response(query_type), False
