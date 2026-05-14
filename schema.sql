-- =============================================================================
-- NISTULA UNIFIED MESSAGING PLATFORM — PostgreSQL Schema
-- Part 2 of the Technical Assessment
-- =============================================================================
--
-- TABLES (in FK dependency order):
--   1. properties               — villa master data
--   2. guests                   — one canonical record per human guest
--   3. guest_channel_identities — maps channel IDs (phone/Airbnb/email) to guest
--   4. reservations             — one booking per row; links guest + property
--   5. conversations            — thread grouping; links guest + reservation
--   6. messages                 — every inbound + outbound message, all channels
--   7. ai_processing_log        — append-only audit of every Claude API call
--
-- DESIGN COMMENTARY is at the bottom of this file.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- EXTENSIONS
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  -- uuid_generate_v4()
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- trigram index for fuzzy name search


-- ===========================================================================
-- ENUMS
-- Using ENUMs for every fixed-vocabulary field enforces valid values at the
-- DB level, not just in application code. Adding a new channel requires an
-- ALTER TYPE — a deliberate, trackable migration.
-- ===========================================================================

CREATE TYPE source_channel AS ENUM (
    'whatsapp',
    'booking_com',
    'airbnb',
    'instagram',
    'direct'
);

-- Query types exactly matching the Part 1 classifier spec
CREATE TYPE query_type AS ENUM (
    'pre_sales_availability',
    'pre_sales_pricing',
    'post_sales_checkin',
    'special_request',
    'complaint',
    'general_enquiry'
);

-- Action values exactly matching the Part 1 response contract
CREATE TYPE message_action AS ENUM (
    'auto_send',    -- confidence >= 0.85 AND not a complaint: sent without review
    'agent_review', -- confidence 0.60-0.84: queued for human editing
    'escalate'      -- confidence < 0.60 OR complaint: human intervention required
);

-- ---------------------------------------------------------------------------
-- MESSAGE STATE MACHINE
-- ---------------------------------------------------------------------------
-- Tracks the exact lifecycle stage of every message from receipt to closure.
--
-- INBOUND message flow:
--
--   [received]
--       |
--       v
--   [ai_drafted] --(confidence >= 0.85, non-complaint)--> [auto_sent]
--       |
--       +--(confidence 0.60-0.84)--> [agent_review] --> [agent_edited] --> [sent]
--       |
--       +--(complaint OR confidence < 0.60)--> [escalated] --> [resolved]
--
-- OUTBOUND messages (replies) start at [sent] — they are the reply, not incoming.
--
-- State definitions:
--   received     : Webhook received and stored. AI not yet called.
--   ai_drafted   : Claude produced a draft. Action field populated. Awaiting dispatch.
--   auto_sent    : Draft dispatched to guest with NO human review (confidence >= 0.85).
--   agent_review : Draft queued for a human agent to read and optionally edit.
--   agent_edited : Human modified the AI draft. Ready to send.
--   sent         : Reply dispatched after agent_review / agent_edited path.
--   escalated    : Complaint, low confidence, or no human response in 30 min.
--   resolved     : Issue fully closed. Conversation can be archived.
-- ---------------------------------------------------------------------------

CREATE TYPE message_status AS ENUM (
    'received',     -- stored; AI not yet called
    'ai_drafted',   -- Claude produced a draft; awaiting dispatch decision
    'auto_sent',    -- sent without human review (confidence >= 0.85, non-complaint)
    'agent_review', -- queued for human agent (confidence 0.60-0.84)
    'agent_edited', -- human modified the AI draft before sending
    'sent',         -- reply dispatched via agent path
    'escalated',    -- complaint / low confidence / 30-min timeout with no response
    'resolved'      -- fully closed
);


-- ===========================================================================
-- TABLE: properties
-- ===========================================================================
-- Villa/property master data. Referenced by reservations, conversations,
-- and messages. One record here means one UPDATE fixes all replies.
-- ---------------------------------------------------------------------------

CREATE TABLE properties (
    id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_code        VARCHAR(50)  NOT NULL UNIQUE, -- e.g. 'villa-b1'
    name                 VARCHAR(200) NOT NULL,         -- e.g. 'Villa B1'
    location             TEXT,                          -- e.g. 'Assagao, North Goa'
    bedrooms             SMALLINT,
    max_guests           SMALLINT,
    has_pool             BOOLEAN DEFAULT FALSE,
    check_in_time        TIME,                          -- e.g. 14:00
    check_out_time       TIME,                          -- e.g. 11:00
    base_rate_inr        NUMERIC(10, 2),
    base_guest_limit     SMALLINT,                      -- guests covered by base rate
    extra_guest_rate_inr NUMERIC(10, 2),
    -- JSONB for flexible fields: wifi_password, chef_contact, caretaker_hours, etc.
    -- Avoids schema migrations when new property attributes are added.
    metadata             JSONB DEFAULT '{}',
    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_properties_code ON properties(property_code);


-- ===========================================================================
-- TABLE: guests
-- ===========================================================================
-- ONE canonical row per real human guest, regardless of how many channels
-- they use. See guest_channel_identities for cross-channel identity design.
-- ---------------------------------------------------------------------------

CREATE TABLE guests (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    display_name      VARCHAR(200),
    email             VARCHAR(320),   -- NULL for WhatsApp-only guests
    phone             VARCHAR(30),    -- NULL for Airbnb-only guests
    preferred_channel source_channel,
    vip_flag          BOOLEAN DEFAULT FALSE,
    notes             TEXT,           -- internal agent notes
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_guests_email ON guests(email) WHERE email IS NOT NULL;
CREATE INDEX idx_guests_phone ON guests(phone) WHERE phone IS NOT NULL;
-- Trigram index allows fuzzy name search: "find guests named Rahul"
CREATE INDEX idx_guests_name_trgm ON guests USING GIN (display_name gin_trgm_ops);


-- ===========================================================================
-- TABLE: guest_channel_identities
-- ===========================================================================
-- Maps a per-channel identifier to a canonical guest record.
-- One guest has many rows here — one per channel they have ever used.
--
-- Example rows for guest_id = 'abc-123':
--   channel = 'whatsapp',    channel_guest_id = '+919876543210'
--   channel = 'airbnb',      channel_guest_id = 'airbnb_user_77123'
--   channel = 'booking_com', channel_guest_id = 'rsharma@gmail.com'
--
-- Lookup on every inbound message:
--   1. SELECT guest_id WHERE channel = $1 AND channel_guest_id = $2
--   2. Found:     use existing guest_id
--   3. Not found: INSERT guests, then INSERT this row
-- ---------------------------------------------------------------------------

CREATE TABLE guest_channel_identities (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guest_id         UUID NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
    channel          source_channel NOT NULL,
    -- The channel-native identifier: phone number, Airbnb user ID, email, etc.
    channel_guest_id VARCHAR(500) NOT NULL,
    -- Stores the raw channel profile JSON for future identity-merge jobs
    raw_profile      JSONB DEFAULT '{}',
    first_seen_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- Guarantees uniqueness: one identity record per (channel, person)
    UNIQUE (channel, channel_guest_id)
);

CREATE INDEX idx_gci_guest  ON guest_channel_identities(guest_id);
-- This index is the hot path: every inbound message does this lookup
CREATE INDEX idx_gci_lookup ON guest_channel_identities(channel, channel_guest_id);


-- ===========================================================================
-- TABLE: reservations
-- ===========================================================================
-- One row per booking. Links a guest to a property for a date range.
-- Messages carry booking_ref; the application resolves it to this table.
-- A reservation being present means the guest is confirmed — the AI and
-- confidence engine treat confirmed guests differently from pre-sales enquiries.
-- ---------------------------------------------------------------------------

CREATE TABLE reservations (
    id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_ref      VARCHAR(50) NOT NULL UNIQUE,  -- e.g. 'NIS-2024-0891'
    guest_id         UUID NOT NULL REFERENCES guests(id),
    property_id      UUID NOT NULL REFERENCES properties(id),
    check_in_date    DATE NOT NULL,
    check_out_date   DATE NOT NULL,
    num_adults       SMALLINT NOT NULL DEFAULT 2,
    num_children     SMALLINT NOT NULL DEFAULT 0,
    total_amount_inr NUMERIC(12, 2),
    is_confirmed     BOOLEAN DEFAULT FALSE,
    source_channel   source_channel,  -- which channel the booking was made on
    special_notes    TEXT,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_stay_dates CHECK (check_out_date > check_in_date)
);

CREATE INDEX idx_reservations_guest    ON reservations(guest_id);
CREATE INDEX idx_reservations_property ON reservations(property_id);
CREATE INDEX idx_reservations_ref      ON reservations(booking_ref);
CREATE INDEX idx_reservations_dates    ON reservations(check_in_date, check_out_date);


-- ===========================================================================
-- TABLE: conversations
-- ===========================================================================
-- Groups related messages into a thread.
--
-- Linkage:
--   conversations.guest_id        -> guests           (always present)
--   conversations.reservation_id  -> reservations     (NULL for pre-sales)
--   conversations.property_id     -> properties       (NULL if unknown at start)
--
-- A single guest can have multiple conversations:
--   e.g. pre-sales enquiry (reservation_id NULL)
--     -> post-booking checkin queries (reservation_id set)
--     -> post-stay complaint (new conversation, same reservation_id)
--
-- Separating conversations from messages lets agents see open threads
-- without scanning the full messages table on every page load.
-- ---------------------------------------------------------------------------

CREATE TABLE conversations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    -- Required: every conversation belongs to one guest
    guest_id        UUID NOT NULL REFERENCES guests(id),
    -- Optional: linked when the guest has a confirmed booking
    reservation_id  UUID REFERENCES reservations(id),
    -- Optional: may be populated from property_id in the inbound message
    property_id     UUID REFERENCES properties(id),
    channel         source_channel NOT NULL,
    -- Auto-generated summary, e.g. 'Availability enquiry April 20-24'
    subject         VARCHAR(500),
    is_open         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_message_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_conversations_guest       ON conversations(guest_id);
CREATE INDEX idx_conversations_reservation ON conversations(reservation_id);
CREATE INDEX idx_conversations_property    ON conversations(property_id);
-- Partial index: only open threads (powers the agent dashboard efficiently)
CREATE INDEX idx_conversations_open
    ON conversations(last_message_at DESC)
    WHERE is_open = TRUE;


-- ===========================================================================
-- TABLE: agents
-- ===========================================================================
-- Internal team members who review, edit, and send messages.
-- agent_id in the messages table is a FK to this table.
-- Kept minimal — a full auth/identity system is out of scope, but the FK
-- must resolve or the schema is invalid SQL.
-- ---------------------------------------------------------------------------

CREATE TABLE agents (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name        VARCHAR(200) NOT NULL,
    email       VARCHAR(320) NOT NULL UNIQUE,
    role        VARCHAR(50)  NOT NULL DEFAULT 'agent', -- 'agent' | 'manager' | 'admin'
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_agents_email ON agents(email);


-- ===========================================================================
-- TABLE: messages
-- ===========================================================================
-- Central fact table. Every inbound message from any channel AND every
-- outbound reply we send lives here. All AI metadata stored per row.
--
-- DESIGN NOTES (see full commentary at the bottom of this file):
--   - ai_drafted_reply vs final_reply: two columns, never overwrite the AI draft
--   - agent_edited BOOLEAN: single flag for "did a human change the AI output?"
--   - ai_confidence_score: stored here so we can measure calibration over time
--   - raw_payload JSONB: original webhook body kept intact for replay/debugging
-- ---------------------------------------------------------------------------

CREATE TABLE messages (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

    -- Context linkage: conversations are linked to reservations, which are linked
    -- to guests and properties — the full chain is traversable from any message.
    conversation_id     UUID NOT NULL REFERENCES conversations(id),
    guest_id            UUID NOT NULL REFERENCES guests(id),
    property_id         UUID REFERENCES properties(id),
    reservation_id      UUID REFERENCES reservations(id),

    -- Routing metadata
    direction           VARCHAR(8) NOT NULL
                            CHECK (direction IN ('inbound', 'outbound')),
    channel             source_channel NOT NULL,

    -- State machine column (see enum definition and flow diagram above)
    status              message_status NOT NULL DEFAULT 'received',

    -- Raw content
    message_text        TEXT NOT NULL,      -- the guest's original message text
    raw_payload         JSONB DEFAULT '{}', -- full original webhook JSON, never modified

    -- -----------------------------------------------------------------------
    -- AI PROCESSING FIELDS (populated after Claude API call; inbound only)
    -- -----------------------------------------------------------------------
    ai_query_type       query_type,         -- output of the classifier
    ai_confidence_score NUMERIC(4, 3),      -- 0.000 to 1.000 from confidence engine
    ai_action           message_action,     -- auto_send / agent_review / escalate
    -- The raw, unedited Claude output. NEVER modified after insert.
    -- Preserved even when agent edits it, so the delta can be analysed.
    ai_drafted_reply    TEXT,

    -- -----------------------------------------------------------------------
    -- REPLY TRACKING FIELDS (populated when reply is dispatched)
    -- -----------------------------------------------------------------------
    -- What was actually sent to the guest.
    -- Identical to ai_drafted_reply when status = 'auto_sent'.
    -- Contains the agent's version when status = 'agent_edited' or 'sent'.
    final_reply         TEXT,
    -- TRUE if a human modified ai_drafted_reply before sending.
    -- The delta between ai_drafted_reply and final_reply is training data.
    agent_edited        BOOLEAN DEFAULT FALSE,
    -- Which agent acted on this message (FK to an agents table, future work)
    agent_id            UUID REFERENCES agents(id),  -- NULL until an agent acts
    -- Internal note explaining why the agent edited (optional but encouraged)
    agent_notes         TEXT,

    -- Timestamps
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ai_processed_at     TIMESTAMPTZ,        -- when the Claude API call returned
    sent_at             TIMESTAMPTZ,        -- when reply was dispatched to guest
    resolved_at         TIMESTAMPTZ         -- when status reached 'resolved'
);

-- Core FK indexes
CREATE INDEX idx_messages_conversation ON messages(conversation_id);
CREATE INDEX idx_messages_guest        ON messages(guest_id);
CREATE INDEX idx_messages_property     ON messages(property_id);
CREATE INDEX idx_messages_reservation  ON messages(reservation_id);

-- Operational indexes
CREATE INDEX idx_messages_status       ON messages(status);
CREATE INDEX idx_messages_query_type   ON messages(ai_query_type);
CREATE INDEX idx_messages_created      ON messages(created_at DESC);

-- Agent queue: all inbound messages currently waiting for human attention.
-- Partial index is much smaller and faster than a full table scan.
CREATE INDEX idx_messages_agent_queue
    ON messages(created_at ASC)
    WHERE direction = 'inbound'
      AND status IN ('ai_drafted', 'agent_review', 'escalated');

-- Analytics: which query types did humans most often correct?
CREATE INDEX idx_messages_agent_edited
    ON messages(ai_query_type, created_at DESC)
    WHERE agent_edited = TRUE;


-- ===========================================================================
-- TABLE: ai_processing_log
-- ===========================================================================
-- Append-only audit trail for every Claude API call made.
-- Kept separate from messages so the messages table stays clean and each
-- table has one clear responsibility. Enables cost tracking, latency
-- monitoring, error analysis, and prompt A/B testing.
-- ---------------------------------------------------------------------------

CREATE TABLE ai_processing_log (
    id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id        UUID NOT NULL REFERENCES messages(id),
    model_used        VARCHAR(100) NOT NULL,  -- e.g. 'claude-sonnet-4-20250514'
    prompt_tokens     INTEGER,
    completion_tokens INTEGER,
    latency_ms        INTEGER,               -- end-to-end API call duration
    confidence_score  NUMERIC(4, 3),
    action_taken      message_action,
    error_message     TEXT,                  -- NULL if call succeeded
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ai_log_message ON ai_processing_log(message_id);
CREATE INDEX idx_ai_log_created ON ai_processing_log(created_at DESC);


-- ===========================================================================
-- VIEWS
-- ===========================================================================

-- Agent queue view: escalations first, then oldest unreviewed messages
CREATE OR REPLACE VIEW v_agent_queue AS
SELECT
    m.id                  AS message_id,
    m.conversation_id,
    g.display_name        AS guest_name,
    r.booking_ref,
    p.property_code,
    m.channel,
    m.ai_query_type,
    m.ai_confidence_score,
    m.ai_action,
    m.status,
    m.message_text,
    m.ai_drafted_reply,
    m.created_at
FROM messages m
JOIN guests        g ON g.id = m.guest_id
LEFT JOIN reservations  r ON r.id = m.reservation_id
LEFT JOIN properties    p ON p.id = m.property_id
WHERE m.direction = 'inbound'
  AND m.status IN ('ai_drafted', 'agent_review', 'escalated')
ORDER BY
    CASE WHEN m.ai_action = 'escalate' THEN 0 ELSE 1 END,
    m.created_at ASC;


-- Full conversation thread: every message in a thread in order
CREATE OR REPLACE VIEW v_conversation_thread AS
SELECT
    c.id             AS conversation_id,
    g.display_name   AS guest_name,
    r.booking_ref,
    p.property_code,
    m.id             AS message_id,
    m.direction,
    m.channel,
    m.status,
    m.message_text,
    m.ai_query_type,
    m.ai_confidence_score,
    m.ai_action,
    m.ai_drafted_reply,
    m.final_reply,
    m.agent_edited,
    m.created_at,
    m.sent_at
FROM conversations c
JOIN guests             g ON g.id = c.guest_id
LEFT JOIN reservations  r ON r.id = c.reservation_id
LEFT JOIN properties    p ON p.id = c.property_id
JOIN messages           m ON m.conversation_id = c.id
ORDER BY c.id, m.created_at;


-- ===========================================================================
-- ┌─────────────────────────────────────────────────────────────────────────┐
-- │                      DESIGN DECISION COMMENTARY                        │
-- └─────────────────────────────────────────────────────────────────────────┘
-- ===========================================================================

-- ── Decision 1: Explicit message state machine ────────────────────────────
--
-- REQUIREMENT: Track whether a message was AI drafted, agent edited, or
-- auto-sent (Part 2 spec item 4).
--
-- DECISION: A single `message_status` enum with 8 states, plus two
-- supporting columns: agent_edited BOOLEAN and sent_at TIMESTAMPTZ.
--
-- WHY NOT a separate message_events table?
-- A normalised event-sourced approach gives perfect audit history but
-- requires a JOIN to check current status on every agent dashboard refresh.
-- For a queue that updates every few seconds, that JOIN cost compounds.
-- The enum gives O(1) status checks; ai_processing_log already covers the
-- AI-side audit trail; a future message_audit_log table can be added without
-- touching this schema.
--
-- WHY separate auto_sent from sent?
-- `auto_sent` = no human ever read the reply before it went out.
-- `sent`      = a human was involved (reviewed and/or edited the draft).
-- This distinction enables the key trust metric: "What % of replies by
-- query_type were auto-sent vs required human review?" Without this
-- separation you cannot measure whether the system is earning autonomy
-- over time.


-- ── Decision 2: ai_drafted_reply vs final_reply ───────────────────────────
--
-- REQUIREMENT: Track both AI-drafted and agent-edited versions (Part 2 spec item 4).
--
-- DECISION: Two separate TEXT columns. ai_drafted_reply is insert-once,
-- never updated. final_reply contains what was actually sent. agent_edited
-- BOOLEAN flags whether they differ.
--
-- WHY: The delta between ai_drafted_reply and final_reply is training signal.
-- A query like:
--   SELECT ai_query_type,
--          AVG(CASE WHEN agent_edited THEN 1 ELSE 0 END) AS edit_rate
--   FROM messages
--   WHERE direction = 'inbound'
--   GROUP BY ai_query_type
--   ORDER BY edit_rate DESC;
-- identifies which query types the AI handles worst — which drives prompt
-- engineering priorities. If we overwrote the AI draft on edit, this signal
-- would be permanently lost.


-- ── Decision 3 (HARDEST): Guest identity unification across channels ──────
--
-- PROBLEM: One human guest contacts us on multiple channels with completely
-- different identifiers. "Rahul Sharma" is:
--   - WhatsApp: +919876543210
--   - Airbnb:   airbnb_user_77123
--   - Booking.com: rsharma@gmail.com
-- Naive approach (guest row per message) creates 3 duplicate guest records.
-- An agent reviewing his complaint won't see his prior WhatsApp messages.
-- The AI drafting a reply won't know he's a repeat guest with prior issues.
--
-- DECISION: guest_channel_identities join table.
-- `guests` holds ONE canonical record per human.
-- `guest_channel_identities` holds N rows per guest — one per channel
-- identity — each referencing the same guest_id via FK.
--
-- Lookup on every inbound message:
--   1. SELECT guest_id FROM guest_channel_identities
--      WHERE channel = $1 AND channel_guest_id = $2
--   2. Found -> use existing guest_id; full cross-channel history available
--   3. Not found -> INSERT guests row, INSERT identity row (new guest)
--
-- The unresolved sub-problem: how do we merge a pre-sales WhatsApp identity
-- with a post-booking Booking.com identity for the same person before they
-- provide a shared signal (same email or phone)?
-- Answer: we can't do it automatically without a shared key. The raw_profile
-- JSONB column stores channel-native profile data for a future identity-merge
-- job. An agent can manually merge two guest records via a UI action that
-- re-points all guest_channel_identities rows to the surviving record and
-- deletes the duplicate. This is a deliberate two-phase design: auto-create
-- isolated records immediately (never block real-time message processing),
-- allow identity resolution asynchronously later.
-- ===========================================================================