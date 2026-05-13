from typing import Any, Dict, Optional


PROPERTY_STORE: Dict[str, Dict[str, Any]] = {
    "PROP-101": {
        "name": "Maple Heights",
        "city": "Bengaluru",
        "rent_starting": "₹35,000/month",
        "availability": "2 units available from June 1",
        "amenities": ["Gym", "Pool", "24x7 Security", "Covered Parking"],
    },
    "PROP-102": {
        "name": "Riverstone Residency",
        "city": "Hyderabad",
        "rent_starting": "₹28,000/month",
        "availability": "1 unit available immediately",
        "amenities": ["Clubhouse", "Children's Play Area", "Power Backup"],
    },
}


def get_property_context(property_id: Optional[str]) -> Optional[Dict[str, Any]]:
    if not property_id:
        return None
    return PROPERTY_STORE.get(property_id)


def format_property_context(property_data: Optional[Dict[str, Any]]) -> str:
    if not property_data:
        return "No property-specific context was found."

    amenities = ", ".join(property_data["amenities"])
    return (
        f"Property: {property_data['name']} ({property_data['city']}). "
        f"Starting rent: {property_data['rent_starting']}. "
        f"Availability: {property_data['availability']}. "
        f"Amenities: {amenities}."
    )
