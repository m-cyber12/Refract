import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_system/theme.dart';
import 'router.dart';

class RefractApp extends ConsumerWidget {
  const RefractApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'REFRACT',
      debugShowCheckedModeBanner: false,
      theme: RefractTheme.light(),
      darkTheme: RefractTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
