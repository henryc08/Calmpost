# Multiplayer

Calmpost's Social tab now connects real accounts through the backend. Invite friends,
follow their care progress, cheer activity, and compete in private groups.

## Run it

Use **Flutter 3.41.9** (Dart 3.11). The existing Phosphor icon package does not compile
with Flutter 3.47's final `IconData` class. No upgrade of the entire app is required.

1. Configure `backend/.env` as described in `backend/README.md` and install its requirements.
   The backend needs a reachable Tiger/Postgres database. Starting it applies the idempotent
   social migration automatically. Existing readings and demo users are preserved.
2. Start the backend:

   ```bash
   cd ~/Documents/Calmpost/backend
   source .venv/bin/activate
   uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```

3. Build/run the app pointing at that backend:

   ```bash
   cd ~/Documents/Calmpost/app
   flutter pub get
   flutter run --dart-define=API_URL=http://192.168.1.42:8000
   ```

   Replace the example LAN address with your laptop's address. Both phones must reach
   the same backend. Social uses per-person sessions and does not require `API_KEY`.
   The signed-out legacy live-bin demo still uses the old `API_KEY` configuration.
   Without a compiled URL, the account form lets you enter the community server address.

   Web development: run on `localhost` with `flutter run -d chrome`. Secure browser
   storage needs HTTPS or localhost. Public deployments require HTTPS; only private
   network/loopback addresses may use HTTP during local development.

## Try it with two people

1. Each person opens **Social** and creates their own username/password account.
2. Alice taps **Invite a friend**, copies the code and shares it with Bob.
3. Bob taps **Join with a code** and pastes it. They now follow each other.
4. Alice opens **Groups → Create a group → Invite to this group** and shares that code.
5. Bob joins. Both see the same private leaderboard.
6. Bob opens his profile using the person icon and taps **I checked on my compost**.
   Alice sees Bob's 5 care XP, updated rank, streak, and feed entry after refreshing
   or within 20 seconds. She can open his profile or cheer his activity.
7. Repeating the check-in does not award more XP that day. Weekly boards reset Sunday
   at 00:00 UTC; all-time progress remains.

Search by username in **People** to follow someone without an invitation. Private
profiles require approval. Requests and follower management are on the People tab.
Edit your name, bio and privacy setting from your progress page.

## Connect actual bin care

On your social profile, tap **Connect my bin** and enter the device token generated
when the bin was registered. Keep the sensor bridge running. Pairing changes the bin's
owner from its demo owner to your account, but does not transfer the demo owner's XP.
An already paired account's bin cannot be claimed by another account.

Home and Layers then read your bin using your account session. Opening Layers records
one daily check-in. Adding or skipping a catalog item in Log is saved to your account;
the backend determines whether it follows advice or keeps a harmful item out, applies
the existing action XP cap, and prevents retries from duplicating a saved log. Sensor
readings must be recent. Ordinary additions earn zero XP.

Social progress uses the saved server ledger. The existing local Home/Greenhouse reward
economy remains separate: local demo XP, Loam and crate rolls do not change multiplayer
rankings. Profile has a **My shared progress** link and labels those local demo rewards.

## Privacy and ownership

- New accounts are private. Search exposes only identity; accepted followers see care
  progress and history. Public profiles are an explicit choice.
- Joining a group shares its care-XP standings. It does not approve profile follows.
- Friend invites approve both directions; only share them with intended friends.
  Removing a follower also invalidates your old friend-invite code.
- Codes last 7 days. Creating a replacement invalidates the previous code.
- Group owners can remove members or delete their group. Members can leave. Removing
  someone invalidates group codes so an old invite cannot immediately undo removal.
- Tokens are hashed on the server and stored using Flutter secure storage on the device.
  Android backups are disabled to prevent restoring encrypted tokens without their key.
  Passwords are salted hashes. Logging out revokes that device's session.
- Accounts currently use username/password login; email delivery, password recovery,
  push notifications, and public hosting are not included.

## API

All routes below use `/social`. Registration/login are public and rate limited;
all other routes require `Authorization: Bearer <session token>`.

| Feature | Routes |
| --- | --- |
| Account | `POST /register`, `POST /login`, `POST /logout`, `GET/PATCH /me` |
| People | `GET /people?q=`, `GET /people/{id}`, `POST/DELETE /people/{id}/follow` |
| Requests | `GET /connections`, `POST /requests/{id}` with `accept`, `DELETE /followers/{id}` |
| Invites | `POST /invites`, `POST /join` with `code` |
| Groups | `GET/POST /circles`, `GET /circles/{id}?period=week|all`, `DELETE /circles/{id}` |
| Group membership | `POST /circles/{id}/invite`, `DELETE /circles/{id}/members/{user}` |
| Progress | `POST /check-in`, `POST /bin` with device token, `POST /care-log` |
| Feed | `GET /feed?target=&before=`, `POST /events/{id}/cheer` |

Profile and leaderboard responses never contain credentials, device tokens, or raw
sensor history. Legacy demo-key routes are scoped so knowing the shared demo API key
cannot impersonate a registered player or access their bin.
Player sessions use the social care endpoints for rewards; legacy demo reward endpoints
(including repeatable demo harvests) are unavailable to player accounts.

## Validation

```bash
cd backend
python -m pytest

cd ../app
flutter analyze
flutter test
```

Backend tests use an isolated Postgres server through `pgserver`, covering schema
idempotence, separate users, private profiles, invitation expiry/rotation, group
membership, equal ranks, week boundaries, concurrent check-ins, and bin ownership.
Widget tests cover the social flows at 360dp and 1.3× text. Repository tests cover
session storage, authentication, failures, and server URL validation.

An optional **write-enabled** smoke test creates two accounts on a disposable backend:

```bash
flutter test test/multiplayer_live_test.dart \
  --dart-define=MULTIPLAYER_TEST_URL=http://127.0.0.1:8765
```

Do not point that test at your production database. It exercises actual HTTP calls for
friend/group invitations, account progress, rankings, cheers, and membership revocation.
