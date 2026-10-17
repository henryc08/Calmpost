-- ---------------------------------------------------------------------------
-- A drop can now come from a photo the user submitted, not only from the bin's
-- camera noticing something. Everything downstream is shared -- confirm,
-- dismiss, history, the add_log rows, Trunc's photo context -- so the only new
-- thing needed is a way to tell the two apart.
--
-- It matters for one number: /drops/accuracy measures how often the CAMERA was
-- right. Counting photos the user deliberately framed would flatter it, so
-- that query filters on source = 'camera'.
--
-- Idempotent, like every file here: safe to re-run on a database that already
-- has the column.
-- ---------------------------------------------------------------------------

ALTER TABLE drop_events
    ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'camera';

-- ADD CONSTRAINT has no IF NOT EXISTS, so guard it by name.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'drop_events_source_check'
    ) THEN
        ALTER TABLE drop_events
            ADD CONSTRAINT drop_events_source_check
            CHECK (source IN ('camera', 'photo'));
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS drop_events_source_idx
    ON drop_events (bin_id, source, time DESC);
