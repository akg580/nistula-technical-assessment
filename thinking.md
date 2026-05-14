# Part 3 — Thinking Questions

## Question A — The Immediate Response
**Message to send at 3am:**

Hi [Guest Name], I am very sorry you are facing this, and I understand how urgent it is with breakfast guests arriving soon.  
I have escalated this as a priority to our on-call caretaker right now, and you will receive a call update within 15 minutes.  
We will resolve the hot water issue first and then review your refund request with our duty manager immediately after.  
— Priya, Guest Relations Manager, Nistula

**Why this wording (2-3 lines):**  
It acknowledges emotion first, gives a concrete next step with a clear time commitment, and avoids making an unauthorized refund promise. It is calm, accountable, and action-oriented, which helps de-escalate at 3am.

## Question B — The System Design
Beyond sending the message, the platform should:

1. Classify as `complaint` and force `action = escalate` (no auto-send path).  
2. Open a P1 incident linked to guest, property, reservation, and message ID.  
3. Trigger parallel alerts: caretaker (call/SMS/WhatsApp), duty manager, and backup operations lead.  
4. Start SLA timers:  
   - 15 min: acknowledgement required from caretaker  
   - 30 min: if no acknowledgement, auto-escalate to backup caretaker + property manager and place an automated voice call  
5. Log every event with timestamps (received, classified, notified, acknowledged, resolved), including who acted and when.  
6. Send proactive guest updates every 15 minutes until resolution.  
7. Keep incident open until both conditions are met: (a) issue marked fixed by ops, and (b) guest confirms restoration or does not contest after follow-up.

## Question C — The Learning
If this is the third hot-water complaint in two months at Villa B1, the system should treat it as a recurring failure pattern, not isolated incidents.

What I would build:

1. Pattern detector: rolling 60-day complaint clustering by property + issue type.  
2. Auto-created preventive maintenance ticket with due date and owner when threshold is hit.  
3. Pre-check workflow before each check-in (geyser test, pressure check, backup heater check) with mandatory completion proof.  
4. Root-cause coding on incident closure and monthly reliability dashboard by property.  
5. Escalation policy that blocks instant-booking on the property if unresolved critical utilities exceed threshold.

This converts complaint history into preventive operations and reduces repeat guest impact.
