-- In-place migrations: bring a database created by an older schema up to the
-- current shape without a reset. Runs last, on every boot; every statement
-- is idempotent and a no-op on a fresh database.
-- (The seeds -> loam rename runs earlier, in 000_premigrate.sql.)

-- --- advice: headline/pair_with, and verdicts aligned with the app ---------
ALTER TABLE advice ADD COLUMN IF NOT EXISTS headline text;
ALTER TABLE advice ADD COLUMN IF NOT EXISTS pair_with jsonb NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE advice DROP CONSTRAINT IF EXISTS advice_verdict_check;
-- add -> great, add_with_browns -> careful (avoid is unchanged).
UPDATE advice SET verdict = 'great'   WHERE verdict = 'add';
UPDATE advice SET verdict = 'careful' WHERE verdict IN ('add_with_browns', 'add_with_greens');
UPDATE advice SET verdict = NULL WHERE verdict IS NOT NULL AND verdict NOT IN ('great', 'careful', 'avoid');
ALTER TABLE advice ADD CONSTRAINT advice_verdict_check
    CHECK (verdict IS NULL OR verdict IN ('great', 'careful', 'avoid'));

-- --- stage_history: the app's stages, including 'cooling' -----------------
ALTER TABLE stage_history DROP CONSTRAINT IF EXISTS stage_history_stage_check;
DELETE FROM stage_history
    WHERE stage NOT IN ('started', 'active', 'hot', 'cooling', 'curing', 'ready', 'harvested');
ALTER TABLE stage_history ADD CONSTRAINT stage_history_stage_check
    CHECK (stage IN ('started', 'active', 'hot', 'cooling', 'curing', 'ready', 'harvested'));

-- --- leagues: capitalised tier names, member extras -------------------------
ALTER TABLE leagues DROP CONSTRAINT IF EXISTS leagues_tier_check;
UPDATE leagues SET tier = initcap(tier) WHERE tier <> initcap(tier);
ALTER TABLE leagues ADD CONSTRAINT leagues_tier_check
    CHECK (tier IN ('Seedling', 'Sprout', 'Fern', 'Sapling', 'Oak', 'Sequoia'));

ALTER TABLE league_members ADD COLUMN IF NOT EXISTS is_friend boolean NOT NULL DEFAULT false;
ALTER TABLE league_members ADD COLUMN IF NOT EXISTS streak integer NOT NULL DEFAULT 0;

-- --- add_log: catalog ids and camera drops -------------------------------
ALTER TABLE add_log ADD COLUMN IF NOT EXISTS catalog_id text;
ALTER TABLE add_log ADD COLUMN IF NOT EXISTS drop_id bigint;
ALTER TABLE add_log DROP CONSTRAINT IF EXISTS add_log_source_check;
ALTER TABLE add_log ADD CONSTRAINT add_log_source_check
    CHECK (source IN ('manual', 'photo', 'seed', 'camera'));

-- --- user_state: inventory, gacha pity, equipped cosmetics ----------------
ALTER TABLE user_state ADD COLUMN IF NOT EXISTS display_name text NOT NULL DEFAULT 'You';
ALTER TABLE user_state ADD COLUMN IF NOT EXISTS packets integer NOT NULL DEFAULT 0;
ALTER TABLE user_state ADD COLUMN IF NOT EXISTS pity_since_epic integer NOT NULL DEFAULT 0;
ALTER TABLE user_state ADD COLUMN IF NOT EXISTS pity_since_legendary integer NOT NULL DEFAULT 0;
ALTER TABLE user_state ADD COLUMN IF NOT EXISTS equipped_finish text NOT NULL DEFAULT 'finish_classic';
ALTER TABLE user_state ADD COLUMN IF NOT EXISTS equipped_title text;

-- --- point_events: a lookup index added with the economy -------------------
CREATE INDEX IF NOT EXISTS point_events_user_kind_idx ON point_events (user_id, kind, time DESC);
