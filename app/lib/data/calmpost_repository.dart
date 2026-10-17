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

  // --- camera drop-in (AGENTS.md 2.4) ---------------------------------------
  //
  // The app never calls Gemini itself and never holds its key: vision/ runs
  // the camera and the model, the backend stores the detection and applies
  // the category rules. The app arms a session, watches for detections, then
  // sends back what the user says was really added.

  /// POST /bins/{id}/drops/session: 'drop something in', arming the camera for
  /// about a minute. Arming again replaces an open session.
  Future<DropSession> startDropSession();

  /// Detections waiting on the user, oldest first. Emits the current list on
  /// every tick, including an empty one, so a UI can tell 'nothing yet' from
  /// 'no longer pending'. Runs until the subscription is cancelled.
  Stream<List<CameraDrop>> watchDrops();

  /// POST /drops/{id}/confirm: the user submitted the sheet. Each item becomes
  /// a log row and gets a verdict, so XP follows the usual rules.
  Future<DropResult> confirmDrop(int dropId, List<DropConfirmation> items);

  /// POST /drops/{id}/dismiss: nothing was added, the trigger was false. Kept
  /// for the accuracy stat.
  Future<void> dismissDrop(int dropId);

  // --- Trunc, the compost assistant -----------------------------------------

  /// POST /bins/{id}/chat: ask Trunc a question.
  ///
  /// Stateless on the server, so pass the conversation so far in [history],
  /// oldest first, excluding the question being asked. The backend adds the
  /// sensor readings, what was recently added and the last camera photos.
  ///
  /// Set [includePhotos] false for a cheaper, faster turn when the question
  /// plainly does not need them.
  ///
  /// Always returns something sayable: an off-topic question comes back with
  /// `onTopic` false and a ready-made redirect, and an unreachable model comes
  /// back as `isFallback` with a sensor summary. Neither is an error state.
  Future<TruncReply> askTrunc(
    String message, {
    List<TruncTurn> history,
    bool includePhotos,
  });

  FoodItem? food(String id);
}
