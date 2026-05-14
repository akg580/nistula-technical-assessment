# Part 3 — Thinking Questions

**Scenario:** 3am. Vikram at Villa B1: *"There is no hot water and we have guests arriving in 4 hours. This is unacceptable. I want a refund for tonight."*

---

## Question A — The Immediate Response

> Hi Vikram, I'm sincerely sorry — this is not the experience we want for you at all.
>
> I'm escalating this to our caretaker right now. You should receive a call within 15 minutes.
>
> We will make this right. I'll personally follow up on tonight's charges once the issue is fixed.
>
> — Priya, Guest Relations Manager, Nistula

**Why:** Three things in sequence: validate the anger without defensiveness; give a concrete time-boxed commitment (vague promises at 3am read as brush-offs); acknowledge the refund without granting it. Signing as a named manager signals escalation and reduces hostility.

---

## Question B — The System Design

The classifier hard-routes `complaint` to `escalate` regardless of confidence score. Within 30 seconds:

- P1 incident created, linked to Vikram's reservation and guest profile.
- SMS + WhatsApp fires simultaneously to the caretaker and duty manager.
- AI draft gets a 90-second edit window; auto-sends if untouched.

**15-minute timer:** If no caretaker acknowledgement — voice call fires to the property manager (Exotel/Twilio). At 30 minutes: backup caretaker is tried and Vikram receives: *"We haven't forgotten you — our team is on the way."*

Everything is timestamped: alert sent, acknowledged/not, calls attempted. Incident stays open until the caretaker resolves it and a follow-up confirms Vikram is satisfied.

---

## Question C — The Learning

A nightly job counts complaints by property + keyword cluster. On the third "hot water" occurrence at Villa B1 in 60 days it auto-creates a P1 maintenance ticket.

**To prevent a fourth complaint:**

1. **Pre-stay checklist:** Caretaker gets an automatic task 2 hours before every Villa B1 check-in — test the geyser, mark done. If uncompleted, duty manager is notified before the guest arrives.

2. **Proactive message (48hrs before check-in):** *"Hi [Guest], our caretaker has completed a pre-arrival check. If anything isn't right when you arrive, message us immediately."*

3. **Root cause on close:** Agent must select a root cause when closing any maintenance complaint. After three identical causes the system flags it as a structural defect requiring a contractor — not another temporary fix. Reactive complaint data becomes preventive maintenance.