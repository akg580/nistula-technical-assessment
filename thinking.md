# Part 3 — Thinking Questions

**Scenario:** 3am. A guest at Villa B1 sends a WhatsApp message: *"There is no hot water and we have guests arriving for breakfast in 4 hours. This is unacceptable. I want a refund for tonight."*

---

## Question A — The Immediate Response

**The actual message sent at 3am:**

> Hi [Guest Name], I'm so sorry — this is not the experience we want for you at all, and I completely understand how stressful this is with guests arriving soon.
>
> I'm escalating this to our caretaker right now to get the hot water fixed as quickly as possible. You should receive a call within the next 15 minutes.
>
> We will make this right. I'll personally follow up on your request regarding tonight's charges once the immediate issue is resolved.
>
> — Priya, Guest Relations Manager, Nistula

**Why this wording:** The opening validates the guest's anger without defensiveness — at 3am, feeling heard matters more than policy. The 15-minute callback commitment is concrete and time-boxed; vague promises ("someone will be in touch") read as brush-offs. The refund is acknowledged without being granted — "make this right" and "follow up on your request" keeps the door open without an AI making a financial commitment it has no authority to give. Signing as "Priya, Guest Relations Manager" (not the generic team sign-off) signals this has been escalated to a named person, which immediately de-escalates anger.

---

## Question B — The System Design

**What the platform does beyond sending the message:**

The classifier catches `complaint` and hard-routes `action = escalate` regardless of confidence score. Within 30 seconds of the webhook arriving:

- A P1 incident record is created in the database, linked to the reservation and guest profile.
- Push notification + SMS fires to the caretaker's phone and the duty manager's WhatsApp simultaneously.
- The AI drafts the holding reply; the duty manager has a 90-second edit window before it auto-sends.

After sending: a 15-minute countdown starts. If the caretaker has not acknowledged the alert, a second escalation fires — a voice call to the property manager's personal number via an automated call service (Exotel/Twilio). At 30 minutes with no human response, a backup caretaker contact is tried and the guest receives: *"We haven't forgotten you — our team is on the way. Please reply here if you need anything before they arrive."*

Everything is logged with timestamps: alert sent, acknowledged/not-acknowledged, call attempted, guest reply received. The incident stays open until the caretaker marks it resolved AND a follow-up message confirms the guest is satisfied.

---

## Question C — The Learning

**What the system does with the pattern (third complaint in two months):**

A nightly job queries: *complaints by property + keyword cluster in the last 60 days*. On the third occurrence of "hot water" at Villa B1, it auto-creates a P1 maintenance ticket and alerts the property manager.

**What I would build to prevent a fourth complaint:**

1. **Pre-stay check trigger:** Flag Villa B1 in the reservations flow so the caretaker receives an automatic checklist task 2 hours before every future check-in: manually test the geyser, confirm hot water is working, mark done. The task is tracked — if it isn't completed, the duty manager is notified.

2. **Proactive guest message (48 hours before check-in):** *"Hi [Guest], our caretaker has completed a full pre-arrival check of the villa. If anything isn't perfect when you arrive, please message us immediately — we're available until 10pm and our emergency line is always on."* This sets expectations and opens a channel before 3am crises happen.

3. **Root cause field on incident close:** Force the agent closing any maintenance complaint to select a root cause (e.g. "geyser tripped," "power fluctuation," "low pressure"). After three identical root causes at the same property, the system flags it as a structural defect requiring a contractor visit — not another temporary fix. This turns reactive complaint data into a preventive maintenance schedule.