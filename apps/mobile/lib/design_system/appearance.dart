import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appearanceProvider = StateNotifierProvider<AppearanceController, ThemeMode>((ref) => AppearanceController());

class AppearanceController extends StateNotifier<ThemeMode> {
  AppearanceController() : super(ThemeMode.system) { _load(); }
  static const _key = 'appearance_theme';
  bool _changed = false;
  Future<void> _pending = Future.value();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_key);
      if (mounted && !_changed) {
        state = ThemeMode.values.where((mode) => mode.name == value).firstOrNull ?? ThemeMode.system;
      }
    } catch (_) {
      // Default to the system theme if preferences are unavailable.
    }
  }

  Future<bool> setMode(ThemeMode mode) async {
    _changed = true;
    state = mode;
    var saved = true;
    _pending = _pending.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        saved = await prefs.setString(_key, mode.name);
      } catch (_) { saved = false; }
    });
    await _pending;
    return saved;
  }
}
