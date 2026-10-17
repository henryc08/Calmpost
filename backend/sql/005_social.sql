-- Multiplayer identities are separate from legacy demo users. Scores come from point_events.
CREATE TABLE IF NOT EXISTS social_profiles (
 user_id text PRIMARY KEY REFERENCES user_state(user_id) ON DELETE CASCADE,
 handle text UNIQUE NOT NULL CHECK (handle ~ '^[a-z0-9_]{3,24}$'),
 password_hash text NOT NULL,
 bio text NOT NULL DEFAULT '',
 is_private boolean NOT NULL DEFAULT true,
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS social_sessions (
 token_hash text PRIMARY KEY,
 user_id text NOT NULL REFERENCES social_profiles(user_id) ON DELETE CASCADE,
 expires_at timestamptz NOT NULL DEFAULT now() + interval '30 days'
);
CREATE INDEX IF NOT EXISTS social_sessions_user_idx ON social_sessions(user_id);
CREATE TABLE IF NOT EXISTS social_follows (
 follower_id text REFERENCES social_profiles(user_id) ON DELETE CASCADE,
 followed_id text REFERENCES social_profiles(user_id) ON DELETE CASCADE,
 accepted boolean NOT NULL DEFAULT false,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(follower_id, followed_id), CHECK(follower_id <> followed_id)
);
CREATE INDEX IF NOT EXISTS social_follows_target_idx ON social_follows(followed_id, accepted);
CREATE TABLE IF NOT EXISTS social_circles (
 id text PRIMARY KEY,
 owner_id text NOT NULL REFERENCES social_profiles(user_id),
 name text NOT NULL CHECK(length(name) BETWEEN 1 AND 48),
 created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS social_circle_members (
 circle_id text REFERENCES social_circles(id) ON DELETE CASCADE,
 user_id text REFERENCES social_profiles(user_id) ON DELETE CASCADE,
 joined_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(circle_id, user_id)
);
CREATE INDEX IF NOT EXISTS social_members_user_idx ON social_circle_members(user_id);
CREATE TABLE IF NOT EXISTS social_invites (
 token_hash text PRIMARY KEY,
 creator_id text NOT NULL REFERENCES social_profiles(user_id) ON DELETE CASCADE,
 circle_id text REFERENCES social_circles(id) ON DELETE CASCADE,
 expires_at timestamptz NOT NULL DEFAULT now() + interval '7 days'
);
CREATE TABLE IF NOT EXISTS social_cheers (
 event_id bigint NOT NULL,
 event_time timestamptz NOT NULL,
 user_id text REFERENCES social_profiles(user_id) ON DELETE CASCADE,
 PRIMARY KEY(event_id, event_time, user_id)
);
CREATE TABLE IF NOT EXISTS social_auth_attempts (
 scope text PRIMARY KEY,
 attempts integer NOT NULL DEFAULT 0,
 reset_at timestamptz NOT NULL
);
