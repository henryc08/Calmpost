-- Runs first on every boot. Fixes that must happen BEFORE the later files
-- create objects on top of the old shape. Idempotent, and a no-op on a fresh
-- database.

-- The soft currency was called "seeds" in the first schema; the app calls it
-- Loam. xp_weekly is built on that column, so drop the rollup first (002
-- recreates it on the renamed column), then rename. Nothing is lost: the
-- rollup is derived from point_events.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'point_events' AND column_name = 'seeds'
    ) THEN
        IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'xp_weekly') THEN
            -- A continuous aggregate on Tiger; a plain view on a test server.
            BEGIN
                EXECUTE 'DROP MATERIALIZED VIEW xp_weekly CASCADE';
            EXCEPTION WHEN wrong_object_type THEN
                EXECUTE 'DROP VIEW xp_weekly CASCADE';
            END;
        END IF;
        EXECUTE 'ALTER TABLE point_events RENAME COLUMN seeds TO loam';
    END IF;
END
$$;
