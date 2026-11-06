import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'ffi.dart';
import 'models.dart';

/// Owns the Rust store handle and exposes the library API to the UI.
class RefractRepository {
  RefractRepository._(this._bindings, this._handle);

  final RefractBindings _bindings;
  final Pointer<Void> _handle;

  static Future<RefractRepository> create() async {
    final dir = await getApplicationSupportDirectory();
    final bindings = RefractBindings.load();
    final handle = bindings.open('${dir.path}/refract.db');
    return RefractRepository._(bindings, handle);
  }

  Item importText(String text, {String? sourceUrl}) => _bindings.importText(_handle, text, sourceUrl);

  Item importHtml(String html, {String? sourceUrl}) => _bindings.importHtml(_handle, html, sourceUrl);

  Item importPdf(List<int> bytes, {String? sourceUrl}) => _bindings.importPdf(_handle, bytes, sourceUrl);

  List<Item> listItems({int limit = 50, int offset = 0}) => _bindings.listItems(_handle, limit: limit, offset: offset);

  Item? getItem(String id) => _bindings.getItem(_handle, id);

  List<Item> search(String query) => _bindings.search(_handle, query);

  void dispose() {
    if (Platform.isAndroid || Platform.isIOS) {
      _bindings.close(_handle);
    }
  }
}

final repositoryProvider = Provider<RefractRepository>((ref) {
  throw UnimplementedError('Initialized asynchronously in main/bootstrap');
});

/// Async bootstrap provider: opens the local store before first use.
final bootstrapProvider = FutureProvider<RefractRepository>((ref) async {
  final repo = await RefractRepository.create();
  ref.onDispose(repo.dispose);
  return repo;
});

final itemsProvider = FutureProvider<List<Item>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.listItems();
});

final itemProvider = FutureProvider.family<Item?, String>((ref, id) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.getItem(id);
});

final searchProvider = FutureProvider.family<List<Item>, String>((ref, query) async {
  if (query.trim().isEmpty) return [];
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.search(query);
});

final tagsProvider = FutureProvider<List<Tag>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.listTags();
});

final annotationsProvider = FutureProvider.family<List<Annotation>, String>((ref, itemId) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.listAnnotations(itemId);
});

final dailyEditionProvider = FutureProvider<List<Item>>((ref) async {
  final repo = await ref.watch(bootstrapProvider.future);
  return repo.dailyEdition(days: 7);
});
