# Multiplayer

Calmpost's Social tab now connects real accounts through the backend. Invite friends,
follow their care progress, cheer activity, and compete in private groups.

## Run it

Use **Flutter 3.41.9** (Dart 3.11). The existing Phosphor icon package does not compile
with Flutter 3.47's final `IconData` class. No upgrade of the entire app is required.

1. Configure `backend/.env` as described in `backend/README.md` and install its requirements.
   The backend needs a reachable Tiger/Postgres database. Starting it applies the idempotent
   social migration automatically. Existing readings and demo users are preserved.
2. Start the backend. Paths are relative to the repo root, so these work from any clone.

   Windows (PowerShell):

   ```powershell
   cd backend
   .venv\Scripts\Activate.ps1
   uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```

   macOS/Linux:

   ```bash
   cd backend
   source .venv/bin/activate
   uvicorn app.main:app --host 0.0.0.0 --port 8000
   ```

3. Build/run the app pointing at that backend:

   ```bash
   cd app
   flutter pub get
   flutter run -d chrome --dart-define=API_URL=http://localhost:8000
   ```

   Social uses per-person sessions and does not require `API_KEY`. The signed-out legacy
   live-bin demo still uses the old `API_KEY` configuration. Without a compiled URL, the
   account form lets you enter the community server address.

   Web development: run on `localhost`. Secure browser storage needs HTTPS or localhost,
   and `localhost:8000` is the simplest backend address for a browser test on one machine.

4. For two phones, swap `localhost` for the laptop's LAN address (`ipconfig` → IPv4
   Address) and both phones must reach that same backend:

   ```bash
   flutter run --dart-define=API_URL=http://172.20.10.3:8000
   ```

   **Use a phone hotspot, not campus Wi-Fi.** Two independent reasons:

   - `normalizeServer` in `app/lib/data/social_repository.dart` permits plain HTTP only
     for `localhost`, `127.x`, `10.x`, `192.168.x` and `172.16–31.x`. Campus Wi-Fi here
     hands out carrier-grade NAT addresses in `100.64.0.0/10` (this laptop on eduroam is
     `100.102.7.50`), which is **not** in that list, so sign-in fails with "Use HTTPS for
     a public server" before a request is even sent. A hotspot address such as
     `172.20.10.3` is inside the allowed range.
   - Campus networks commonly block device-to-device traffic, so a phone could not reach
     the laptop even if the address validated.

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
For the hackathon, a second account can enter the **same device token** on
**Profile → Your bin** (or Home → Connect bin). This joins the bin without changing
its owner. Two accounts maximum, one bin per account. Both see the same sensors,
graphs, advice, logs and camera photos, but keep separate XP, Loam, quests, seeds
and purchases. Inventory shows only your own contributions. Only the first account
can calibrate the probes. Sharing a friend invite alone does not grant bin access.
Update/restart the backend to apply `099_shared_bins.sql` before connecting account two.

Home and Layers then read your bin using your account session. Opening Layers records
one daily check-in. Adding or skipping a catalog item in Log is saved to your account;
the backend determines whether it follows advice or keeps a harmful item out, applies
the existing action XP cap, and prevents retries from duplicating a saved log. Sensor
readings need not be available to save a log; only advice bonuses require fresh
readings. Before the first reading, Log shows cautious advice without inventing
sensor values. Confirmed compostable additions earn 1 XP per
20 g, rounded cumulatively per day, plus verified care bonuses under the shared
60 XP daily action cap. Non-recommended compostables can still be logged. Identical
retries return the original award without saving twice; changed retry bodies conflict.

Camera capture supports paired player bins. Set the bin's `DEVICE_TOKEN` in
`vision/.env`; the camera service can report detections only for that bin.
Either paired account can review and confirm a detection, but only the confirming
account earns its XP and achievement progress. The drop can be confirmed only once;
retrying from the other account reports that it was already handled. There is still
one physical camera session, so starting another replaces the current one. Confirmed rows store
editable pieces/portions and total grams, and appear in **Compost inventory**
from Log or Profile. Counts do not multiply weight or XP. Private groups show
aggregate estimated kg, counted pieces/portions, and amount XP + care/reward XP;
ingredient inventories remain private. Older additions have unknown counts.

Social, Home, Profile and Greenhouse use the same saved server ledger in live account
mode. Layers reads actual saved additions. Account-scoped reward claims and spending
are allowed; demo harvest writes remain blocked. Explicit mock mode keeps a separate
local garden whose rewards never enter multiplayer rankings.

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

## Materials & help exchange

Open a private group and choose **Materials & help**. Members can request or offer
compostable catalog materials, finished compost, or help turning/harvesting a bin.
A post includes an amount/help description and optional details visible to the group.
The other participant reserves it; only the two participants can read handoff notes.
Both must confirm the actual handoff/help before either earns XP.

Each person can earn 10 XP on completion, up to 20 exchange XP/day and one reward
with the same person per UTC day across all groups, within the shared 60 action XP
cap. A cap may reduce XP to zero; the completion is still recorded. Posting,
reserving and cancelling earn no XP. Confirmations are self-reported by both people;
physical delivery is not sensor-verified. Sharing does not automatically log compost
or inflate inventory. Log received scraps only when adding them to your bin.

Posts and reservations expire after seven days. Unconfirmed reservations can be
released. Once either party confirms, close an unfinished exchange instead of
reopening it. Owners may close posts but cannot approve rewards for participants.
Removing a member cancels/reopens affected unfinished exchanges safely. Completed
rewards remain in the ledger after group deletion. Deploy migration
`098_materials_exchange.sql` with the backend before distributing the new app.
