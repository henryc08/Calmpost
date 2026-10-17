import '../domain/models.dart';

/// Everything the app needs from the outside world. Screens only ever talk to
/// this interface: MockRepository (demo scenarios) or ApiRepository (the real
/// bin, through FastAPI + Tiger Data). Method shapes mirror the backend
/// endpoints in AGENT.md section 5.
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
}
