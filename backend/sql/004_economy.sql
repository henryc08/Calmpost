-- Economy: reward crates, the Seed Packet collection, and every gacha pull.
-- Rules in app/rules/game.py (crates, daily goal) and app/rules/gacha.py
-- (odds, pity, refunds), mirroring app/lib/state/game.dart and
-- app/lib/domain/gacha.dart. Loam moves through point_events (002).

-- ---------------------------------------------------------------------------
-- crates: earned from achievements, streak milestones and the daily goal.
-- opened_at IS NULL means it is waiting in the rewards inbox. dedupe_key
-- (e.g. 'ach:hot_streak:1') makes earning a crate idempotent.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS crates (
    id              bigserial   PRIMARY KEY,
    user_id         text        NOT NULL,
    tier            text        NOT NULL CHECK (tier IN ('sprout', 'grove', 'canopy')),
    source          text        NOT NULL,
    dedupe_key      text,
    earned_at       timestamptz NOT NULL DEFAULT now(),
    opened_at       timestamptz,
    loam_awarded    integer,
    packets_awarded integer
);

CREATE UNIQUE INDEX IF NOT EXISTS crates_dedupe_uniq ON crates (user_id, dedupe_key) WHERE dedupe_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS crates_unopened_idx ON crates (user_id, earned_at) WHERE opened_at IS NULL;

-- ---------------------------------------------------------------------------
-- collection: copies of each collectible a player owns (plain table).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS collection (
    user_id        text        NOT NULL,
    collectible_id text        NOT NULL,
    copies         integer     NOT NULL DEFAULT 1 CHECK (copies >= 0),
    first_at       timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, collectible_id)
);

-- ---------------------------------------------------------------------------
-- gacha_pulls: every Seed Packet opened (hypertable). An audit trail that
-- lets anyone check the advertised odds against what actually happened.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS gacha_pulls (
    id             bigserial,
    time           timestamptz NOT NULL DEFAULT now(),
    user_id        text        NOT NULL,
    collectible_id text        NOT NULL,
    rarity         text        NOT NULL CHECK (rarity IN ('common', 'uncommon', 'rare', 'epic', 'legendary')),
    -- How it was paid for: an owned packet, or Loam.
    paid_with      text        NOT NULL CHECK (paid_with IN ('packet', 'loam')),
    -- Which batch (1-pull or 10-pull) it came from.
    batch_id       text        NOT NULL,
    is_new         boolean     NOT NULL,
    refund_loam    integer     NOT NULL DEFAULT 0,
    -- True when a pity counter forced this rarity.
    pity           boolean     NOT NULL DEFAULT false,
    PRIMARY KEY (time, id)
);

SELECT create_hypertable('gacha_pulls', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS gacha_pulls_user_time_idx ON gacha_pulls (user_id, time DESC);

-- Observed odds per day, to compare with the published ones.
CREATE MATERIALIZED VIEW IF NOT EXISTS gacha_odds_1d
WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT
    time_bucket('1 day', time) AS bucket,
    rarity,
    count(*) AS pulls
FROM gacha_pulls
GROUP BY bucket, rarity
WITH NO DATA;

SELECT add_continuous_aggregate_policy('gacha_odds_1d',
    start_offset      => INTERVAL '30 days',
    end_offset        => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists     => TRUE);
