import 'dart:async';

import 'package:flutter/services.dart';

/// Receives content shared into REFRACT from other apps via the native
/// Android Share Intent / iOS Share Extension, delivered over a method channel.
class ShareIntentChannel {
  ShareIntentChannel._();

  static final ShareIntentChannel instance = ShareIntentChannel._();

  static const _channel = MethodChannel('dev.refract/shared');

  final _sharedController = StreamController<String>.broadcast();

  /// Emitted whenever the OS delivers shared content (text or URL).
  Stream<String> get sharedContent => _sharedController.stream;

  void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') {
        final text = call.arguments as String?;
        if (text != null && text.trim().isNotEmpty) {
          _sharedController.add(text);
        }
      }
    });
  }
}
