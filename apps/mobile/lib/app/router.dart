import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_page.dart';
import '../features/import/import_page.dart';
import '../features/library/library_page.dart';
import '../features/reader/reader_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
      GoRoute(path: '/library', builder: (context, state) => const LibraryPage()),
      GoRoute(path: '/import', builder: (context, state) => const ImportPage()),
      GoRoute(
        path: '/reader/:id',
        builder: (context, state) => ReaderPage(itemId: state.pathParameters['id']!),
      ),
    ],
  );
});
