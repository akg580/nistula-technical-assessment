"""
test_requests.py — Manual test suite for the /webhook/message endpoint.

Run with: python test_requests.py
Server must be running at localhost:8000.

Covers:
  1. Pre-sales availability query (the example from the brief)
  2. Pre-sales pricing query
  3. Post-sales check-in query (confirmed booking)
  4. Special request
  5. Complaint (should always return action=escalate)
  6. General enquiry (pets)
  7. Missing optional fields (no booking_ref, no property_id)
"""

import json
import httpx

BASE_URL = "http://localhost:8000"
SEPARATOR = "─" * 60


def pretty_print(label: str, payload: dict, response: dict | None, status: int):
    print(f"\n{SEPARATOR}")
    print(f"TEST: {label}")
    print(f"INPUT:  {json.dumps(payload, indent=2, default=str)}")
    print(f"STATUS: {status}")
    if response:
        print(f"OUTPUT: {json.dumps(response, indent=2, default=str)}")
    print(SEPARATOR)


TEST_CASES = [
    {
        "label": "1 — Pre-sales availability (example from brief)",
        "payload": {
            "source": "whatsapp",
            "guest_name": "Rahul Sharma",
            "message": "Is the villa available from April 20 to 24? What is the rate for 2 adults?",
            "timestamp": "2026-05-05T10:30:00Z",
            "booking_ref": "NIS-2024-0891",
            "property_id": "villa-b1",
        },
    },
    {
        "label": "2 — Pre-sales pricing enquiry",
        "payload": {
            "source": "booking_com",
            "guest_name": "Sneha Kapoor",
            "message": "What is the price for 5 adults for 3 nights in June? Do you charge extra per person?",
            "timestamp": "2026-05-06T14:00:00Z",
            "booking_ref": None,
            "property_id": "villa-b1",
        },
    },
    {
        "label": "3 — Post-sales check-in query (confirmed booking)",
        "payload": {
            "source": "whatsapp",
            "guest_name": "Arjun Mehta",
            "message": "Hi, we arrive tomorrow. What is the WiFi password and what time can we check in?",
            "timestamp": "2026-05-07T09:15:00Z",
            "booking_ref": "NIS-2024-1102",
            "property_id": "villa-b1",
        },
    },
    {
        "label": "4 — Special request (chef booking)",
        "payload": {
            "source": "airbnb",
            "guest_name": "Priya Nair",
            "message": "Can you arrange a private chef for dinner on Saturday night? It is our anniversary.",
            "timestamp": "2026-05-08T11:00:00Z",
            "booking_ref": "NIS-2024-1205",
            "property_id": "villa-b1",
        },
    },
    {
        "label": "5 — Complaint (should always escalate)",
        "payload": {
            "source": "whatsapp",
            "guest_name": "Vikram Patel",
            "message": "There is no hot water and we have guests arriving in 4 hours. This is completely unacceptable. I want a refund.",
            "timestamp": "2026-05-09T03:00:00Z",
            "booking_ref": "NIS-2024-0987",
            "property_id": "villa-b1",
        },
    },
    {
        "label": "6 — General enquiry (pets)",
        "payload": {
            "source": "instagram",
            "guest_name": "Neha Joshi",
            "message": "Do you allow pets at the villa? We have a small dog.",
            "timestamp": "2026-05-10T16:45:00Z",
            "booking_ref": None,
            "property_id": "villa-b1",
        },
    },
    {
        "label": "7 — No property_id (should still work via fallback)",
        "payload": {
            "source": "direct",
            "guest_name": "Amit Gupta",
            "message": "Hi, I want to check if you are available for the last week of May for 4 people.",
            "timestamp": "2026-05-11T10:00:00Z",
        },
    },
]


def run_tests():
    print("\n" + "═" * 60)
    print("  NISTULA WEBHOOK TEST SUITE")
    print("═" * 60)

    results_summary = []

    with httpx.Client(timeout=45.0) as client:
        for test in TEST_CASES:
            label = test["label"]
            payload = test["payload"]

            try:
                r = client.post(f"{BASE_URL}/webhook/message", json=payload)
                response_data = r.json()
                pretty_print(label, payload, response_data, r.status_code)

                if r.status_code == 200:
                    results_summary.append(
                        f"  ✓ {label} → {response_data.get('query_type')} "
                        f"| score={response_data.get('confidence_score')} "
                        f"| action={response_data.get('action')}"
                    )
                else:
                    results_summary.append(f"  ✗ {label} → HTTP {r.status_code}")

            except httpx.ConnectError:
                print(f"\n✗ CONNECT ERROR on '{label}'")
                print("  → Is the server running? Try: uvicorn src.main:app --reload")
                results_summary.append(f"  ✗ {label} → Connection refused")
            except Exception as e:
                print(f"\n✗ ERROR on '{label}': {e}")
                results_summary.append(f"  ✗ {label} → {e}")

    print("\n" + "═" * 60)
    print("  SUMMARY")
    print("═" * 60)
    for line in results_summary:
        print(line)
    print()


if __name__ == "__main__":
    run_tests()