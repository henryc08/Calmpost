-- Durable group exchanges; requests are deduplicated independently of the XP ledger.
CREATE TABLE IF NOT EXISTS exchange_posts (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    circle_id text NOT NULL REFERENCES social_circles(id) ON DELETE CASCADE,
    creator_id text NOT NULL REFERENCES social_profiles(user_id),
    request_id text NOT NULL,
    create_payload jsonb NOT NULL,
    kind text NOT NULL CHECK (kind IN ('request','offer')),
    material_id text NOT NULL,
    quantity text NOT NULL CHECK (length(quantity) BETWEEN 1 AND 80),
    details text NOT NULL DEFAULT '' CHECK (length(details) <= 500),
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','reserved','completed','cancelled')),
    version integer NOT NULL DEFAULT 1,
    created_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL DEFAULT now() + interval '7 days',
    responder_id text REFERENCES social_profiles(user_id),
    reservation_id text,
    claim_payload jsonb,
    creator_note text NOT NULL DEFAULT '',
    responder_note text NOT NULL DEFAULT '',
    creator_confirmed boolean NOT NULL DEFAULT false,
    responder_confirmed boolean NOT NULL DEFAULT false,
    completed_at timestamptz,
    creator_xp integer NOT NULL DEFAULT 0 CHECK (creator_xp BETWEEN 0 AND 10),
    responder_xp integer NOT NULL DEFAULT 0 CHECK (responder_xp BETWEEN 0 AND 10),
    UNIQUE (creator_id, request_id),
    CHECK (responder_id IS NULL OR responder_id <> creator_id),
    CHECK (status NOT IN ('reserved','completed') OR (responder_id IS NOT NULL AND reservation_id IS NOT NULL)),
    CHECK (status <> 'completed' OR (creator_confirmed AND responder_confirmed AND completed_at IS NOT NULL))
);
CREATE INDEX IF NOT EXISTS exchange_circle_idx ON exchange_posts (circle_id, id DESC);
CREATE INDEX IF NOT EXISTS exchange_creator_idx ON exchange_posts (creator_id, created_at DESC);
