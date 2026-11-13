import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/share_intent.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ShareIntentChannel.instance.init();
  runApp(const ProviderScope(child: RefractApp()));
}
