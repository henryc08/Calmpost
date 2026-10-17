-- Counts were not recorded historically. NULL means unknown, never one.
ALTER TABLE add_log ADD COLUMN IF NOT EXISTS piece_count integer
    CHECK (piece_count BETWEEN 1 AND 999);
CREATE INDEX IF NOT EXISTS add_log_inventory_idx ON add_log (user_id, bin_id, time DESC)
    WHERE action = 'added' AND category IN ('green', 'brown');
