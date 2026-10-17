import '../domain/drop.dart';
import '../domain/models.dart';

/// Everything the app needs from the outside world. Screens only ever talk to
/// this interface: MockRepository (demo scenarios) or ApiRepository (the real
/// bin, through FastAPI + Tiger Data). Method shapes mirror the backend
/// endpoints in AGENTS.md section 5.
abstract class CalmpostRepository {
  /// GET /bins/{id}/live, polled.
  Stream<BinSnapshot> watchBin();

  /// GET /bins/{id}/trends?range=24h
  Future<List<TrendPoint>> trends(Zone zone, Metric metric);

  /// POST /bins/{id}/advice/check
  Future<Advice> checkItem(FoodItem item);

  /// POST /bins/{id}/logs: the user actually added this to the bin.
  Future<void> logItem(FoodItem item);

  /// GET /bins/{id}/advice
  Suggestion suggestions(BinSnapshot snapshot);

  /// Local catalog search (backend: Gemini lookup for unknown items).
  List<FoodItem> searchFoods(String query);

  /// Photo logging: Gemini vision on the backend.
  Future<FoodItem> identifyPhoto();

  /// GET /leagues/current (everyone except you).
  Future<List<LeagueMember>> leagueCohort();

  FoodItem? food(String id);

  // --- camera drop-in (AGENTS.md 2.4) ---------------------------------------

  /// POST /bins/{id}/drops/session: arm the camera for 60 s.
  Future<DropSession> startDropSession();

  /// What the camera reports for [session]: one [DropSeen], or [DropNothing]
  /// when the window closes empty; then the stream ends. Cancel to stop.
  Stream<DropEvent> watchDrop(DropSession session);

  /// POST /drops/{id}/confirm with the rows the user accepted or edited.
  /// Returns a verdict for every row, in order. [advisedIds] are today's
  /// suggestions, so following one earns its XP.
  Future<List<Advice>> confirmDrop(Drop drop, List<DropLine> lines, {Set<String> advisedIds = const {}});

  /// POST /drops/{id}/dismiss: "Nothing was added".
  Future<void> dismissDrop(Drop drop);
}
