from src.classifier import classify_query


def test_classifies_pre_sales_availability():
    message = "Is the villa available from April 20 to 24 for 2 adults?"
    assert classify_query(message) == "pre_sales_availability"


def test_classifies_pre_sales_pricing():
    message = "What is the price per night for 3 adults?"
    assert classify_query(message) == "pre_sales_pricing"


def test_classifies_post_sales_checkin():
    message = "What time is check-in and what is the WiFi password?"
    assert classify_query(message) == "post_sales_checkin"


def test_classifies_special_request():
    message = "Can you arrange airport pickup and an early check-in?"
    assert classify_query(message) == "special_request"


def test_complaint_has_priority():
    message = "What is the rate? Also no hot water and this is unacceptable."
    assert classify_query(message) == "complaint"


def test_falls_back_to_general_enquiry():
    message = "Thanks for sharing, noted."
    assert classify_query(message) == "general_enquiry"
