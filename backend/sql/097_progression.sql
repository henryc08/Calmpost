-- Additive and safe to rerun. Existing XP and collections are unchanged.
ALTER TABLE user_state ADD COLUMN IF NOT EXISTS equipped_seed text;
