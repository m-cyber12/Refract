import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_page.dart';
import '../features/import/import_page.dart';
import '../features/library/library_page.dart';
import '../features/reader/reader_page.dart';
import '../features/settings/settings_page.dart';
import '../features/sense/sense_page.dart';
import '../features/vault/vault_page.dart';
import '../features/xray/xray_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
      GoRoute(path: '/library', builder: (context, state) => const LibraryPage()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
      GoRoute(path: '/sense', builder: (context, state) => const SensePage()),
      GoRoute(path: '/xray', builder: (context, state) => const XrayPage()),
      GoRoute(path: '/vault', builder: (context, state) => const VaultPage()),
      GoRoute(path: '/import', builder: (context, state) => const ImportPage()),
      GoRoute(
        path: '/reader/:id',
        builder: (context, state) => ReaderPage(itemId: state.pathParameters['id']!),
      ),
    ],
  );
});
