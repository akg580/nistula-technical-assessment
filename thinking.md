# Part 3: Written Answers

## 1) Classification strategy
I used a lightweight regex classifier because it is deterministic, fast, and easy to debug. It provides clear behavior for common real-estate intents such as availability, pricing, booking, and maintenance.

## 2) Confidence and routing approach
Confidence is computed from three simple signals:
- Whether query type is recognized
- Whether valid property context exists
- Whether a model-generated response was used

This keeps routing interpretable:
- High confidence: auto-reply
- Medium confidence: manual review
- Low confidence or unknown intent: escalate

## 3) AI fallback and reliability
If Claude API credentials are unavailable (or API call fails), the service uses deterministic fallback responses. This avoids downtime and guarantees a response path for every request.

## 4) Data design choices
The SQL schema separates inquiries, AI responses, and escalations for observability and auditability. Each user request is traceable from intake to final handling action.

## 5) Production improvements
- Add authentication + request signature validation for webhook security
- Add structured logging and metrics (latency, confidence distribution, escalation rate)
- Replace regex-only classification with a hybrid model-based intent classifier
- Add retry/backoff and circuit-breaking for external AI API calls
- Add integration tests and load testing
