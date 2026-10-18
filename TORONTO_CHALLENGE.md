# Calmpost Toronto Challenge

Calmpost helps Toronto residents understand the food-waste diversion problem,
learn the right destination for everyday scraps, and make sorting a repeatable habit.
The existing sensor bin, current-bin advice, camera confirmation and game remain central.
This is a focused extension of the existing app for Toronto's 2026 civic-tech challenge.

## What works

Open **Home → Toronto Challenge**, or **Log → Toronto Challenge**. No paired bin,
server, Gemini quota or network connection is needed for the Toronto guide or lessons.

- City context: about 40% of Toronto garbage could go in the Green Bin; 2025 overall
  diversion was 26.3% in City-serviced multi-residential buildings and 60.3% in houses.
- Search 24 reviewed materials, with City record IDs, current disposal summaries,
  condition/packaging caveats and copyable sources. Unmatched materials point to Waste Wizard.
- Log's existing verdict sheet adds municipal guidance while preserving bin-care rules.
  Camera/photo review offers the same guidance for keep-outs. Nothing changes the
  requirement to confirm identification and remove unsuitable items from the compost bin.
- Three baseline questions, three short lessons, then three different transfer questions.
  First attempts persist; completion earns the local **Toronto sorter** learning badge.
- Explicitly save a self-reported sorting action after using a route. Each reviewed
  material counts once. This counts practice, not measured mass or verified diversion.
- Copy a practical request for building management or a neutral election-discussion
  question with City sources. Copying never sends a message.

The learning badge is separate from XP, Loam and the plant collection. Confirmed additions
and care continue to earn the existing game rewards. Toronto practice never enters the
bin inventory, balance, sensor readings, streaks, score or private league rankings.

## Toronto data foundation

| Source | Use |
| --- | --- |
| [Waste Wizard dataset](https://open.toronto.ca/dataset/waste-wizard-lookup-table/) | Real municipal material IDs, categories and source instructions |
| [2025 diversion reports](https://www.toronto.ca/services-payments/recycling-organics-garbage/solid-waste-reports/) | Local problem and published comparison |
| [Green Bin guide](https://www.toronto.ca/services-payments/recycling-organics-garbage/houses/what-goes-in-my-green-bin/) | Current acceptance rules, preparation and 40% estimate |
| [Toronto residential recycling provider](https://www.circularmaterials.ca/resident-communities/toronto/) | Current clean paper/cardboard guidance after the 2026 collection transition |
| [City yard-waste guide](https://www.toronto.ca/services-payments/recycling-organics-garbage/houses/yard-waste/) | Leaves versus grass-clippings guidance |
| [City Waste Strategy](https://www.toronto.ca/services-payments/recycling-organics-garbage/waste-management/waste-strategy/) | Civic context and the question about improving apartment access/participation |

The downloadable Waste Wizard JSON contains **2,206 records** and its resource metadata
says **last modified December 12, 2023**. The app ships a curated subset, not a complete or
live Waste Wizard mirror. These summaries were manually cross-checked on **October 18,
2026** against current City/provider pages. Older original instructions remain in the
bundled audit data; the app presents reviewed summaries rather than blindly reusing them.
For example, old black-plastic recycling guidance is deliberately outside our subset.

The source metadata's licence is **License not specified**. We preserve that value and
attribution rather than claim a licence the record does not state.

The manifest records the resource URL, record count, modification date, SHA-256 and
review date. `testdata/toronto/waste_wizard_subset.json` preserves the exact imported rows.
`tools/toronto/curation.json` holds the reviewed mappings, civic stats and source URLs.
No new secret, external SDK, paid service or backend migration is required.

## Updating the snapshot

1. Download package metadata from the official CKAN `package_show` endpoint for
   `waste-wizard-lookup-table` and its JSON resource to local files.
2. Inspect source changes and cross-check each selected rule with current City/provider
   guidance. Update the curation, review date, expected hash/count and civic statistics
   only after that review. Do not infer current acceptance from an old category alone.
3. Rebuild with:

   ```sh
   python3 tools/toronto/import_waste_wizard.py --data /path/to/source.json --metadata /path/to/package_show.json
   ```

4. Run the checks below and update AGENTS.md in the same change. Changed source bytes
   or categories stop the importer until reviewed. The importer never calls the network.

## Boundaries and measurement

- Overall diversion includes recycling and other programs, with estimated Blue Bin
  tonnage. It is not an organics-only participation rate or evidence that knowledge alone
  causes the gap. The 40% figure is a City estimate, not a scan of the user's garbage.
- Quiz results are a small practice comparison on different questions. They do not
  establish durable behaviour change or a reduction in Toronto's waste.
- Learning and self-reported practices persist on this device per server/account, with
  a separate signed-out guest record. They do not sync or publish resident data.
- A published sorting rule does not prove a building has access to the relevant service.
- Unknowns remain unknown. Neither a Gemini label nor a home-compost category grants
  a municipal disposal route. A custom food label can be checked manually in the guide.

## Judging demo (about two minutes)

1. Open Toronto Challenge: show the sourced **40%**, **26.3%** and **60.3%** figures.
2. Search **cheese rind**: show **Toronto Green Bin**, the current City source, and the
   explanation that dairy stays out of a small Calmpost compost bin.
3. Use **Check my compost bin** to show Calmpost's existing keep-out verdict.
4. Search **compostable cup**: show why the label does not mean Green Bin acceptance.
5. Complete or revisit the learning challenge: show the lessons, local badge and
   first-attempt results. A returning completed run preserves its original scores.
6. Show the building request and election question: civic information becomes a
   concrete next step. Finish on the existing bin/camera demo to show the daily habit.

Use an actual disposal for the self-report action, or clearly identify a judging action
as a demonstration. Do not describe the prototype as changing the City's diversion rate.

## Verification and preview

```sh
cd app
flutter analyze --no-pub
flutter test --no-pub
flutter test --no-pub test/toronto_ui_test.dart --dart-define=CAPTURE_REVIEW=true
flutter build web --no-pub
```

Mock web preview: `?toronto=1`. Phone renders are in `artifacts/toronto/`.
Tests cover source traceability, difficult sorting cases, unknowns, bin-safety separation,
immutable quiz attempts, local persistence/failures, account scopes, navigation, civic
copying, and phone layouts. Real Android/hardware testing remains a separate check.
