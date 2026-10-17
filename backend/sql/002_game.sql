-- Game schema: the XP/Loam ledger, per-player state, leagues.
-- Rules live in app/rules/game.py, which mirrors app/lib/domain/xp_rules.dart.

-- ---------------------------------------------------------------------------
-- point_events: the XP and Loam ledger (hypertable), append-only, so totals,
-- streaks, the daily goal and league standings are always recomputed rather
-- than stored and drifting.
--
-- loam is negative for spending (Seed Packets, Lid Locks), so a balance is
-- sum(loam). dedupe_key makes once-only awards (quests, daily goal rewards,
-- achievements, streak milestones) safe to re-evaluate on every request.
--
-- kinds: followed_suggestion, avoided_bad_add, check_in, healthy_layer_day,
--   weekly_balance, harvest, daily_quest, daily_goal, streak_milestone,
--   league_finish, crate_open, gacha_spend, gacha_refund, lid_lock_buy,
--   lid_lock_used
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS point_events (
    id         bigserial,
    time       timestamptz NOT NULL DEFAULT now(),
    user_id    text        NOT NULL,
    bin_id     text        REFERENCES bins (bin_id) ON DELETE CASCADE,
    kind       text        NOT NULL,
    xp         integer     NOT NULL DEFAULT 0,
    loam       integer     NOT NULL DEFAULT 0,
    dedupe_key text,
    meta       jsonb       NOT NULL DEFAULT '{}'::jsonb,
    PRIMARY KEY (time, id)
);

SELECT create_hypertable('point_events', 'time', if_not_exists => TRUE);
CREATE INDEX IF NOT EXISTS point_events_user_time_idx ON point_events (user_id, time DESC);
CREATE INDEX IF NOT EXISTS point_events_user_kind_idx ON point_events (user_id, kind, time DESC);
CREATE INDEX IF NOT EXISTS point_events_dedupe_idx    ON point_events (user_id, dedupe_key)
    WHERE dedupe_key IS NOT NULL;

-- ---------------------------------------------------------------------------
-- user_state: current per-player state that is not an event (plain table).
-- Inventory counts and the gacha pity counters live here; the row is locked
-- (SELECT ... FOR UPDATE) while spending so two taps cannot double-spend.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_state (
    user_id              text PRIMARY KEY,
    display_name         text        NOT NULL DEFAULT 'You',
    lid_locks            integer     NOT NULL DEFAULT 0 CHECK (lid_locks BETWEEN 0 AND 2),
    -- Unopened Seed Packets (from crates).
    packets              integer     NOT NULL DEFAULT 0 CHECK (packets >= 0),
    -- Gacha pity: pulls since the last Epic+ / Legendary.
    pity_since_epic      integer     NOT NULL DEFAULT 0 CHECK (pity_since_epic >= 0),
    pity_since_legendary integer     NOT NULL DEFAULT 0 CHECK (pity_since_legendary >= 0),
    -- Equipped cosmetics (collectible ids, see app/catalog/collectibles.py).
    equipped_finish      text        NOT NULL DEFAULT 'finish_classic',
    equipped_title       text,
    created_at           timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Leagues: weekly 30-person cohorts, Sunday reset. Tier names match
-- leagueTiers in xp_rules.dart.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS leagues (
    id         bigserial PRIMARY KEY,
    tier       text NOT NULL CONSTRAINT leagues_tier_check
               CHECK (tier IN ('Seedling', 'Sprout', 'Fern', 'Sapling', 'Oak', 'Sequoia')),
    week_start date NOT NULL,
    UNIQUE (tier, week_start)
);

CREATE TABLE IF NOT EXISTS league_members (
    league_id    bigint  NOT NULL REFERENCES leagues (id) ON DELETE CASCADE,
    user_id      text    NOT NULL,
    display_name text    NOT NULL,
    is_bot       boolean NOT NULL DEFAULT false,
    is_friend    boolean NOT NULL DEFAULT false,
    -- Shown beside the name in the cohort list; flavour for bots.
    streak       integer NOT NULL DEFAULT 0,
    PRIMARY KEY (league_id, user_id)
);

CREATE INDEX IF NOT EXISTS league_members_user_idx ON league_members (user_id);

-- ---------------------------------------------------------------------------
-- xp_weekly: weekly XP per player, the league table (continuous aggregate).
-- origin is a Sunday so buckets line up with the Sunday reset.
-- ---------------------------------------------------------------------------
CREATE MATERIALIZED VIEW IF NOT EXISTS xp_weekly
WITH (timescaledb.continuous, timescaledb.materialized_only = false) AS
SELECT
    time_bucket('7 days', time, origin => '2024-01-07 00:00:00+00'::timestamptz) AS week,
    user_id,
    sum(xp)::bigint   AS xp,
    sum(loam)::bigint AS loam,
    count(*)          AS events
FROM point_events
GROUP BY week, user_id
WITH NO DATA;

SELECT add_continuous_aggregate_policy('xp_weekly',
    start_offset      => INTERVAL '21 days',
    end_offset        => INTERVAL '1 minute',
    schedule_interval => INTERVAL '5 minutes',
    if_not_exists     => TRUE);
