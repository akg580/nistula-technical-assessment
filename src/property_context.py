"""
property_context.py — Mock property data store.

"""

from typing import Optional


PROPERTY_DATA: dict[str, dict] = {
    "villa-b1": {
        "name": "Villa B1",
        "location": "Assagao, North Goa",
        "bedrooms": 3,
        "max_guests": 6,
        "private_pool": True,
        "check_in": "2:00 PM",
        "check_out": "11:00 AM",
        "base_rate_inr": 18_000,
        "base_rate_guest_limit": 4,
        "extra_guest_rate_inr": 2_000,
        "wifi_password": "Nistula@2024",
        "caretaker_hours": "8am to 10pm",
        "caretaker_contact": "+91-XXXXXXXXXX",  # masked for assessment
        "chef_on_call": True,
        "chef_note": "Pre-booking required, available for all meals",
        "cancellation_policy": "Free cancellation up to 7 days before check-in. 50% charge within 7 days.",
        "pets_allowed": False,
        "parking": True,
        # Date-keyed availability: True = available, False = blocked
        "availability": {
            "2026-04-20": True,
            "2026-04-21": True,
            "2026-04-22": True,
            "2026-04-23": True,
            "2026-04-24": True,
        },
    }
}


def get_property_context_string(property_id: str) -> str:
    """
    Returns a formatted plain-text block of property context for injection
    into the Claude system prompt.

    Falls back to a generic message if property_id is unknown, so the AI
    can still draft a partial reply rather than crashing.

    Args:
        property_id: The property identifier (e.g. 'villa-b1').

    Returns:
        A multi-line string ready for prompt injection.
    """
    data = PROPERTY_DATA.get(property_id)

    if not data:
        return (
            f"Property ID '{property_id}' not found in the system. "
            "Please advise the guest you will confirm details shortly."
        )

    avail_block = (
        "Availability April 20–24, 2026: All dates available"
        if all(data["availability"].values())
        else "Availability: Please check with the team for specific dates"
    )

    return f"""Property: {data['name']}, {data['location']}
Bedrooms: {data['bedrooms']} | Max guests: {data['max_guests']} | Private pool: {'Yes' if data['private_pool'] else 'No'}
Check-in: {data['check_in']} | Check-out: {data['check_out']}
Base rate: INR {data['base_rate_inr']:,} per night (up to {data['base_rate_guest_limit']} guests)
Extra guest charge: INR {data['extra_guest_rate_inr']:,} per night per additional person
WiFi password: {data['wifi_password']}
Caretaker: Available {data['caretaker_hours']}
Chef on call: {'Yes' if data['chef_on_call'] else 'No'} — {data['chef_note']}
Pets: {'Allowed' if data['pets_allowed'] else 'Not allowed'}
Parking: {'Available' if data['parking'] else 'Not available'}
{avail_block}
Cancellation policy: {data['cancellation_policy']}""".strip()