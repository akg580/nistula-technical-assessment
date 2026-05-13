-- =============================================================================
-- NISTULA UNIFIED MESSAGING PLATFORM — PostgreSQL Schema
-- Part 2 of the Technical Assessment
-- =============================================================================
-- TABLES IN THIS FILE (in dependency order):
--   1. properties              — villa/property master data
--   2. guests                  — one canonical record per human guest
--   3. guest_channel_identities— maps channel IDs (phone/Airbnb/email) → guest
--   4. reservations            — one record per confirmed booking
--   5. conversations           — groups messages into threads per guest
--   6. messages                — every inbound + outbound message, all channels
--   7. ai_processing_log       — append-only audit of every Claude API call
--
-- DESIGN COMMENTARY is at the bottom of this file.
-- =============================================================================
-- Design philosophy:
--   1. Normalise aggressively: guests and properties are referenced by FK,
--      never duplicated inline. One source of truth per entity.
--   2. Audit everything: every message carries who wrote it, when,
--      whether AI drafted it, and whether a human touched it.
--   3. Extensible: JSONB columns (raw_payload, metadata) absorb channel-
--      specific fields without requiring schema migrations.
--   4. Performance by default: indexes on every foreign key and every
--      column that appears in WHERE or ORDER BY clauses.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- EXTENSIONS
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";   -- uuid_generate_v4()
CREATE EXTENSION IF NOT EXISTS "pg_trgm";     -- trigram index for name search


-- ---------------------------------------------------------------------------
-- ENUMS
-- Design decision: ENUMs for fixed vocabulary fields (source_channel,
-- query_type, action). This enforces validity at the DB level, not just
-- the application layer. If a new channel is added, ALTER TYPE is simple.
-- ---------------------------------------------------------------------------

CREATE TYPE source_channel AS ENUM (
    'whatsapp',
    'booking_com',
    'airbnb',
    'instagram',
    'direct'
);

CREATE TYPE query_type AS ENUM (
    'pre_sales_availability',
    'pre_sales_pricing',
    'post_sales_checkin',
    'special_request',
    'complaint',
    'general_enquiry'
);

CREATE TYPE message_action AS ENUM (
    'auto_send',      -- confidence >= 0.85, sent without human review
    'agent_review',   -- confidence 0.60-0.84, queued for human editing
    'escalate'        -- confidence < 0.60 or complaint, requires human intervention
);

CREATE TYPE message_status AS ENUM (
    'received',       -- Inbound message stored, not yet processed
    'ai_drafted',     -- AI has produced a draft reply
    'agent_edited',   -- A human agent modified the AI draft
    'sent',           -- Reply has been sent to guest
    'escalated',      -- Flagged for manager attention
    'resolved'        -- Issue closed
);


-- ---------------------------------------------------------------------------
-- TABLE: properties
-- Stores villa/property master data. Referenced by messages and reservations.
-- ---------------------------------------------------------------------------

CREATE TABLE properties (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    property_code   VARCHAR(50)  NOT NULL UNIQUE,  -- e.g. 'villa-b1'
    name            VARCHAR(200) NOT NULL,
    location        TEXT,
    bedrooms        SMALLINT,
    max_guests      SMALLINT,
    has_pool        BOOLEAN DEFAULT FALSE,
    check_in_time   TIME,
    check_out_time  TIME,
    base_rate_inr   NUMERIC(10, 2),
    extra_guest_rate_inr NUMERIC(10, 2),
    metadata        JSONB DEFAULT '{}',            -- flexible: wifi_password, chef_contact, etc.
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_properties_code ON properties(property_code);


-- ---------------------------------------------------------------------------
-- TABLE: guests
-- HARDEST DESIGN DECISION (see README):
--   One record per real guest, regardless of how many channels they message on.
--   The challenge: WhatsApp gives a phone number, Airbnb gives an Airbnb ID,
--   Booking.com gives a booking email. These are different identifiers for the
--   same person.
--
--   Solution: a separate `guest_channel_identities` table maps each channel
--   identity to a canonical guest_id. On inbound message:
--     1. Look up guest_channel_identities by (channel, channel_guest_id).
--     2. If found → use existing guest_id.
--     3. If not found → create new guest, insert identity record.
--
--   This avoids creating duplicate guest records for the same person and
--   allows a full cross-channel message history per guest.
-- ---------------------------------------------------------------------------

CREATE TABLE guests (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    display_name    VARCHAR(200),                  -- best-known display name
    email           VARCHAR(320),                  -- optional, may be unknown
    phone           VARCHAR(30),                   -- optional, may be unknown
    preferred_channel source_channel,              -- channel they most often use
    notes           TEXT,                          -- internal notes from agents
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_guests_email ON guests(email) WHERE email IS NOT NULL;
CREATE INDEX idx_guests_phone ON guests(phone) WHERE phone IS NOT NULL;
-- Trigram index for fuzzy name search (e.g. "find guests named Rahul")
CREATE INDEX idx_guests_name_trgm ON guests USING GIN (display_name gin_trgm_ops);


-- ---------------------------------------------------------------------------
-- TABLE: guest_channel_identities
-- Maps a channel-specific identifier → canonical guest record.
-- One guest can have multiple rows here (one per channel they've used).
--
-- Example rows:
--   guest_id=abc, channel='whatsapp',   channel_guest_id='+919876543210'
--   guest_id=abc, channel='airbnb',     channel_guest_id='airbnb_user_77123'
--   guest_id=abc, channel='booking_com',channel_guest_id='rsharma@email.com'
-- ---------------------------------------------------------------------------

CREATE TABLE guest_channel_identities (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guest_id            UUID NOT NULL REFERENCES guests(id) ON DELETE CASCADE,
    channel             source_channel NOT NULL,
    channel_guest_id    VARCHAR(500) NOT NULL,     -- phone / platform user ID / email
    raw_profile         JSONB DEFAULT '{}',        -- channel-native profile data
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (channel, channel_guest_id)             -- one identity per channel per person
);

CREATE INDEX idx_gci_guest ON guest_channel_identities(guest_id);
CREATE INDEX idx_gci_lookup ON guest_channel_identities(channel, channel_guest_id);


-- ---------------------------------------------------------------------------
-- TABLE: reservations
-- One row per booking. Linked to a property and a primary guest.
-- Messages reference this via booking_ref.
-- ---------------------------------------------------------------------------

CREATE TABLE reservations (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_ref         VARCHAR(50) NOT NULL UNIQUE,  -- e.g. 'NIS-2024-0891'
    guest_id            UUID NOT NULL REFERENCES guests(id),
    property_id         UUID NOT NULL REFERENCES properties(id),
    check_in_date       DATE NOT NULL,
    check_out_date      DATE NOT NULL,
    num_adults          SMALLINT NOT NULL DEFAULT 2,
    num_children        SMALLINT NOT NULL DEFAULT 0,
    total_amount_inr    NUMERIC(12, 2),
    is_confirmed        BOOLEAN DEFAULT FALSE,
    special_notes       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT valid_dates CHECK (check_out_date > check_in_date)
);

CREATE INDEX idx_reservations_guest     ON reservations(guest_id);
CREATE INDEX idx_reservations_property  ON reservations(property_id);
CREATE INDEX idx_reservations_dates     ON reservations(check_in_date, check_out_date);
CREATE INDEX idx_reservations_ref       ON reservations(booking_ref);


-- ---------------------------------------------------------------------------
-- TABLE: conversations
-- Groups related messages into a single thread.
-- A conversation belongs to one guest and optionally one reservation.
-- A guest may have multiple conversations (e.g. pre-sales enquiry → booking).
-- ---------------------------------------------------------------------------

CREATE TABLE conversations (
    id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guest_id        UUID NOT NULL REFERENCES guests(id),
    reservation_id  UUID REFERENCES reservations(id),  -- NULL until booking confirmed
    property_id     UUID REFERENCES properties(id),
    channel         source_channel NOT NULL,
    subject         VARCHAR(500),                       -- auto-generated summary
    is_open         BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_message_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_conversations_guest        ON conversations(guest_id);
CREATE INDEX idx_conversations_reservation  ON conversations(reservation_id);
CREATE INDEX idx_conversations_property     ON conversations(property_id);
CREATE INDEX idx_conversations_open         ON conversations(is_open) WHERE is_open = TRUE;


-- ---------------------------------------------------------------------------
-- TABLE: messages
-- Central fact table. Every message ever received or sent lives here.
--
-- Design decisions:
--   - `direction`: 'inbound' (guest → us) or 'outbound' (us → guest).
--   - `raw_payload`: The original webhook JSON, stored intact for debugging
--     and replay. Does not duplicate the structured columns.
--   - `ai_drafted_reply`: The unedited AI output, preserved even if an agent
--     later edits it. This lets us train on the delta.
--   - `final_reply`: What was actually sent. May be identical to ai_drafted_reply
--     (auto_send) or an agent-edited version.
--   - `ai_confidence_score` / `ai_query_type`: Stored so we can analyse
--     classifier accuracy and confidence calibration over time.
--   - `sent_at` vs `created_at`: `created_at` is when we received/drafted it;
--     `sent_at` is when it was actually dispatched to the guest.
-- ---------------------------------------------------------------------------

CREATE TABLE messages (
    id                      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id         UUID NOT NULL REFERENCES conversations(id),
    guest_id                UUID NOT NULL REFERENCES guests(id),
    property_id             UUID REFERENCES properties(id),
    reservation_id          UUID REFERENCES reservations(id),

    -- Routing
    direction               VARCHAR(8) NOT NULL CHECK (direction IN ('inbound', 'outbound')),
    channel                 source_channel NOT NULL,
    status                  message_status NOT NULL DEFAULT 'received',

    -- Content
    message_text            TEXT NOT NULL,
    raw_payload             JSONB DEFAULT '{}',       -- original webhook body

    -- AI processing (inbound messages only)
    ai_query_type           query_type,               -- classifier output
    ai_confidence_score     NUMERIC(4, 3),            -- 0.000 to 1.000
    ai_drafted_reply        TEXT,                     -- raw AI output, never modified
    ai_action               message_action,           -- auto_send / agent_review / escalate

    -- Final reply (outbound messages)
    final_reply             TEXT,                     -- what was actually sent
    agent_edited            BOOLEAN DEFAULT FALSE,    -- TRUE if human changed ai_drafted_reply
    agent_id                UUID,                     -- FK to agents table (future)
    agent_notes             TEXT,                     -- internal note on edit reason

    -- Timestamps
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at                 TIMESTAMPTZ,              -- NULL until dispatched
    resolved_at             TIMESTAMPTZ               -- NULL until status = resolved
);

-- Core lookup indexes
CREATE INDEX idx_messages_conversation  ON messages(conversation_id);
CREATE INDEX idx_messages_guest         ON messages(guest_id);
CREATE INDEX idx_messages_property      ON messages(property_id);
CREATE INDEX idx_messages_reservation   ON messages(reservation_id);
CREATE INDEX idx_messages_status        ON messages(status);
CREATE INDEX idx_messages_query_type    ON messages(ai_query_type);
CREATE INDEX idx_messages_created       ON messages(created_at DESC);

-- Partial index: find all messages needing agent review quickly
CREATE INDEX idx_messages_pending_review
    ON messages(created_at DESC)
    WHERE status IN ('ai_drafted', 'escalated') AND direction = 'inbound';


-- ---------------------------------------------------------------------------
-- TABLE: ai_processing_log
-- Append-only audit trail for every AI API call made.
-- Separated from messages so the messages table stays clean.
-- Useful for: cost tracking, latency monitoring, prompt debugging.
-- ---------------------------------------------------------------------------

CREATE TABLE ai_processing_log (
    id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    message_id          UUID NOT NULL REFERENCES messages(id),
    model_used          VARCHAR(100) NOT NULL,          -- e.g. 'claude-sonnet-4-20250514'
    prompt_tokens       INTEGER,
    completion_tokens   INTEGER,
    latency_ms          INTEGER,                        -- end-to-end Claude API latency
    confidence_score    NUMERIC(4, 3),
    action_taken        message_action,
    error               TEXT,                           -- NULL if successful
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ai_log_message ON ai_processing_log(message_id);
CREATE INDEX idx_ai_log_created ON ai_processing_log(created_at DESC);


-- ---------------------------------------------------------------------------
-- HELPFUL VIEWS
-- ---------------------------------------------------------------------------

-- View: pending_review — all messages waiting for human action
CREATE OR REPLACE VIEW pending_review AS
SELECT
    m.id AS message_id,
    m.conversation_id,
    g.display_name AS guest_name,
    m.channel,
    m.ai_query_type,
    m.ai_confidence_score,
    m.ai_action,
    m.message_text,
    m.ai_drafted_reply,
    m.created_at
FROM messages m
JOIN guests g ON g.id = m.guest_id
WHERE m.status IN ('ai_drafted', 'escalated')
  AND m.direction = 'inbound'
ORDER BY
    -- Escalations always surface first, then by age
    CASE WHEN m.ai_action = 'escalate' THEN 0 ELSE 1 END,
    m.created_at ASC;


-- View: guest_message_history — full thread view per guest
CREATE OR REPLACE VIEW guest_message_history AS
SELECT
    g.id AS guest_id,
    g.display_name AS guest_name,
    c.id AS conversation_id,
    m.id AS message_id,
    m.direction,
    m.channel,
    m.message_text,
    m.final_reply,
    m.ai_query_type,
    m.ai_confidence_score,
    m.agent_edited,
    m.status,
    m.created_at
FROM guests g
JOIN conversations c ON c.guest_id = g.id
JOIN messages m ON m.conversation_id = c.id
ORDER BY g.id, c.created_at, m.created_at;


-- =============================================================================
-- DESIGN DECISION COMMENTARY
-- =============================================================================
--
-- HARDEST DECISION: Guest identity unification across channels.
--
-- The problem: A guest called "Rahul Sharma" might message via WhatsApp
-- (+919876543210), then book via Booking.com (user ID: bdc_92831), then send
-- a post-stay review via Airbnb (airbnb_user_77123). These are the same person
-- but arrive with completely different identifiers.
--
-- If we naively create a guest record per message, Rahul ends up with 3 guest
-- records and his history is fragmented — the agent reviewing his complaint
-- won't see his prior messages.
--
-- The solution — guest_channel_identities:
-- The guests table holds one canonical record per human. The
-- guest_channel_identities table holds N rows, one per channel identity,
-- each pointing to the same guest_id.
--
-- At inbound message time, the pipeline does:
--   1. SELECT guest_id FROM guest_channel_identities
--      WHERE channel = $1 AND channel_guest_id = $2
--   2. If found: use that guest_id
--   3. If not found: INSERT into guests, then INSERT into guest_channel_identities
--
-- The harder sub-problem: what if the same human messages on WhatsApp before
-- they book? They won't have a booking ref yet. We can't auto-merge the
-- pre-sales identity with the post-sales identity without a shared signal
-- (same email or phone number). The metadata JSONB column and a future
-- identity-merge job handle this: an agent can manually merge two guest records,
-- which re-points all guest_channel_identities rows to the surviving record.
-- =============================================================================