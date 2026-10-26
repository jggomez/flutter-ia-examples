import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/llm_engine_config.dart';
import '../../domain/models/saved_trip.dart';

/// Local persistence service backed by `SharedPreferences` for storing
/// finalized `SavedTrip` plans, `LlmEngineConfig` settings, and an optional
/// Hugging Face access token.
class AppStorageService {
  AppStorageService({SharedPreferences? sharedPreferences})
    : _prefsInstance = sharedPreferences;

  static const String savedTripsKey = 'pocket_squad.saved_trips.v1';
  static const String engineConfigKey = 'pocket_squad.engine_config.v1';
  static const String hfTokenKey = 'pocket_squad.hf_token.v1';

  SharedPreferences? _prefsInstance;

  Future<SharedPreferences> get _prefs async =>
      _prefsInstance ??= await SharedPreferences.getInstance();

  /// Loads all persisted [SavedTrip] records ordered newest-first.
  Future<List<SavedTrip>> loadSavedTrips() async {
    final prefs = await _prefs;
    final rawJson = prefs.getString(savedTripsKey);
    if (rawJson == null || rawJson.trim().isEmpty) {
      return const <SavedTrip>[];
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List) return const <SavedTrip>[];
      final trips = <SavedTrip>[];
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          trips.add(SavedTrip.fromJson(item));
        } else if (item is Map) {
          trips.add(SavedTrip.fromJson(Map<String, dynamic>.from(item)));
        }
      }
      return trips;
    } catch (_) {
      return const <SavedTrip>[];
    }
  }

  /// Alias for [loadSavedTrips].
  Future<List<SavedTrip>> getSavedTrips() => loadSavedTrips();

  /// Replaces the persisted [SavedTrip] list.
  Future<void> saveTrips(List<SavedTrip> trips) async {
    final prefs = await _prefs;
    final payload = jsonEncode(trips.map((trip) => trip.toJson()).toList());
    await prefs.setString(savedTripsKey, payload);
  }

  /// Inserts or updates a single [SavedTrip] at the top of the vault list.
  Future<List<SavedTrip>> saveTrip(SavedTrip trip) async {
    final existing = List<SavedTrip>.from(await loadSavedTrips());
    existing.removeWhere((item) => item.id == trip.id);
    existing.insert(0, trip);
    await saveTrips(existing);
    return existing;
  }

  /// Deletes a [SavedTrip] by [tripId] and returns the updated list.
  Future<List<SavedTrip>> deleteTrip(String tripId) async {
    final existing = List<SavedTrip>.from(await loadSavedTrips());
    existing.removeWhere((item) => item.id == tripId);
    await saveTrips(existing);
    return existing;
  }

  /// Clears all saved trips from storage.
  Future<void> clearSavedTrips() async {
    final prefs = await _prefs;
    await prefs.remove(savedTripsKey);
  }

  /// Loads the persisted [LlmEngineConfig], or returns default on-device config.
  Future<LlmEngineConfig> loadEngineConfig() async {
    final prefs = await _prefs;
    final rawJson = prefs.getString(engineConfigKey);
    if (rawJson == null || rawJson.trim().isEmpty) {
      return const LlmEngineConfig();
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is Map<String, dynamic>) {
        return LlmEngineConfig.fromJson(decoded);
      }
      if (decoded is Map) {
        return LlmEngineConfig.fromJson(Map<String, dynamic>.from(decoded));
      }
      return const LlmEngineConfig();
    } catch (_) {
      return const LlmEngineConfig();
    }
  }

  /// Alias for [loadEngineConfig].
  Future<LlmEngineConfig> getEngineConfig() => loadEngineConfig();

  /// Persists the active [LlmEngineConfig].
  Future<void> saveEngineConfig(LlmEngineConfig config) async {
    final prefs = await _prefs;
    await prefs.setString(engineConfigKey, jsonEncode(config.toJson()));
  }

  /// Loads an optional user-supplied Hugging Face token, or `null` if unset.
  Future<String?> loadHfToken() async {
    final prefs = await _prefs;
    final token = prefs.getString(hfTokenKey)?.trim();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  /// Alias for [loadHfToken].
  Future<String?> getHfToken() => loadHfToken();

  /// Saves or clears the optional Hugging Face access token.
  Future<void> saveHfToken(String? token) async {
    final prefs = await _prefs;
    final trimmed = token?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(hfTokenKey);
    } else {
      await prefs.setString(hfTokenKey, trimmed);
    }
  }
}

/// Concrete subclass alias for DI containers expecting `*Impl` naming.
class AppStorageServiceImpl extends AppStorageService {
  AppStorageServiceImpl({super.sharedPreferences});
}
