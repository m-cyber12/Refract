import 'dart:async';

import 'package:flutter/services.dart';

/// Receives content shared into REFRACT from other apps via the native
/// Android Share Intent / iOS Share Extension, delivered over a method channel.
class ShareIntentChannel {
  ShareIntentChannel._();

  static final ShareIntentChannel instance = ShareIntentChannel._();

  static const _channel = MethodChannel('dev.refract/shared');

  /// Emitted whenever the OS delivers shared content (text or URL).
  final Stream<String> sharedContent = _sharedController.stream;
  final _sharedController = StreamController<String>.broadcast();

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
