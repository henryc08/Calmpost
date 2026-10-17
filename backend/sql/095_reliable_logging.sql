-- Idempotency records live outside hypertables so keys are truly unique.
CREATE TABLE IF NOT EXISTS log_requests (
    bin_id text NOT NULL REFERENCES bins(bin_id) ON DELETE CASCADE,
    request_id text NOT NULL,
    body jsonb NOT NULL,
    response jsonb NOT NULL,
    PRIMARY KEY (bin_id, request_id)
);
ALTER TABLE drop_events ADD COLUMN IF NOT EXISTS confirmation_body jsonb;
ALTER TABLE drop_events ADD COLUMN IF NOT EXISTS confirmation_response jsonb;
ALTER TABLE drop_sessions DROP CONSTRAINT IF EXISTS drop_sessions_close_reason_check;
ALTER TABLE drop_sessions ADD CONSTRAINT drop_sessions_close_reason_check
    CHECK (close_reason IS NULL OR close_reason IN ('no_motion', 'reported', 'replaced', 'cancelled'));
