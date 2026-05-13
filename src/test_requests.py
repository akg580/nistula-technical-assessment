import json

import requests

URL = "http://127.0.0.1:8000/webhook"

TEST_CASES = [
    {"text": "Is there any apartment available next month?", "property_id": "PROP-101"},
    {"text": "What is the monthly rent and deposit?", "property_id": "PROP-101"},
    {"text": "Do you have gym and pet-friendly options?", "property_id": "PROP-102"},
    {"text": "Can I book a site visit this Saturday?", "property_id": "PROP-102"},
    {"text": "There is a water leak in my kitchen", "property_id": "PROP-101"},
    {"text": "How far is this from the metro station?", "property_id": "PROP-101"},
    {"text": "Can you explain your cancellation policy?", "property_id": "PROP-999"},
]


def run_tests() -> None:
    for index, case in enumerate(TEST_CASES, start=1):
        payload = {
            "event_id": f"evt-{index}",
            "timestamp": "2026-05-13T12:00:00Z",
            "message": {
                "sender_id": f"user-{index}",
                "text": case["text"],
                "property_id": case["property_id"],
                "channel": "web",
            },
        }
        response = requests.post(URL, json=payload, timeout=20)
        print(f"Test {index}: {response.status_code}")
        print(json.dumps(response.json(), indent=2, ensure_ascii=False))
        print("-" * 60)


if __name__ == "__main__":
    run_tests()
