import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design_system/theme.dart';
import 'router.dart';
import '../core/share_intent.dart';

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
      builder: (context, child) => AnimatedBuilder(animation: ShareIntentChannel.instance,
        builder: (context, _) {
          final shares = ShareIntentChannel.instance;
          return Column(children: [Expanded(child: child ?? const SizedBox()),
            if (shares.drafts.isNotEmpty || shares.notice != null) Material(color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: SafeArea(top: false, child: ListTile(dense: true,
                title: Text('${shares.drafts.length} shared drafts'),
                subtitle: const Text('Temporary; review before saving. No automatic import.'),
                trailing: TextButton(onPressed: () => router.push('/shares'), child: const Text('Review shares'))))),
          ]);
        }),
    );
  }
}
