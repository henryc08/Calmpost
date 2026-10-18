-- Hackathon sharing: the original owner plus one invited-by-token account.
-- Keep ownership intact, and never share account ledgers or collections.
CREATE TABLE IF NOT EXISTS bin_guests (
    bin_id text PRIMARY KEY REFERENCES bins(bin_id) ON DELETE CASCADE,
    user_id text NOT NULL UNIQUE REFERENCES social_profiles(user_id) ON DELETE CASCADE
);

CREATE OR REPLACE VIEW bin_access AS
    SELECT bin_id, owner_id AS user_id FROM bins
    UNION
    SELECT bin_id, user_id FROM bin_guests;

ALTER TABLE drop_events ADD COLUMN IF NOT EXISTS confirmed_by text;
