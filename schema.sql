-- Part 2: PostgreSQL schema for property support workflows

CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    external_id VARCHAR(100) UNIQUE NOT NULL,
    full_name VARCHAR(200),
    email VARCHAR(320),
    phone VARCHAR(32),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE properties (
    id BIGSERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(200) NOT NULL,
    city VARCHAR(120) NOT NULL,
    address TEXT,
    rent_starting NUMERIC(12, 2),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE inquiries (
    id BIGSERIAL PRIMARY KEY,
    event_id VARCHAR(100) UNIQUE NOT NULL,
    user_id BIGINT REFERENCES users(id),
    property_id BIGINT REFERENCES properties(id),
    channel VARCHAR(50) NOT NULL,
    raw_message TEXT NOT NULL,
    query_type VARCHAR(50) NOT NULL,
    confidence NUMERIC(4, 3) NOT NULL,
    action VARCHAR(50) NOT NULL,
    escalation_required BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE ai_responses (
    id BIGSERIAL PRIMARY KEY,
    inquiry_id BIGINT NOT NULL REFERENCES inquiries(id) ON DELETE CASCADE,
    model_name VARCHAR(120),
    prompt_tokens INT,
    completion_tokens INT,
    response_text TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE escalations (
    id BIGSERIAL PRIMARY KEY,
    inquiry_id BIGINT NOT NULL REFERENCES inquiries(id) ON DELETE CASCADE,
    status VARCHAR(40) NOT NULL DEFAULT 'open',
    assigned_to VARCHAR(120),
    reason TEXT,
    resolved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_inquiries_created_at ON inquiries (created_at DESC);
CREATE INDEX idx_inquiries_query_type ON inquiries (query_type);
CREATE INDEX idx_inquiries_action ON inquiries (action);
CREATE INDEX idx_escalations_status ON escalations (status);
