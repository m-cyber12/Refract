import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/integrations/integrations_page.dart';
import '../features/integrations/email_copies_page.dart';
import '../features/integrations/email_copy_page.dart';
import '../features/integrations/calendar_export_page.dart';
import '../features/home/home_page.dart';
import '../features/import/import_page.dart';
import '../features/import/shared_drafts_page.dart';
import '../core/share_intent.dart';
import '../features/import/capture_jobs_page.dart';
import '../features/library/library_page.dart';
import '../features/memory/memory_page.dart';
import '../features/reader/reader_page.dart';
import '../features/recall/recall_page.dart';
import '../features/settings/settings_page.dart';
import '../features/sense/sense_page.dart';
import '../features/signal/signal_page.dart';
import '../features/vault/vault_page.dart';
import '../features/xray/xray_page.dart';
import '../features/xray/consumer_page.dart';

import '../features/knowledge/knowledge_page.dart';
import '../features/knowledge/decision_page.dart';
import '../features/knowledge/knowledge_map.dart';
import '../features/knowledge/compression_page.dart';
import '../features/knowledge/source_page.dart';

import '../features/margins/margins_page.dart';
import '../features/margins/margin_editor_page.dart';
import '../features/margins/margin_exchange_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
      GoRoute(path: '/library', builder: (context, state) => const LibraryPage()),
      GoRoute(path:'/integrations',builder:(context,state)=>const IntegrationsPage()),
      GoRoute(path:'/integrations/copies',builder:(context,state)=>const EmailCopiesPage()),
      GoRoute(path:'/integrations/email',builder:(context,state)=>const EmailCopyPage()),
      GoRoute(path:'/integrations/calendar',builder:(context,state)=>const CalendarExportPage()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsPage()),
      GoRoute(path: '/recall', builder: (context, state) => RecallPage(contextItemId: state.uri.queryParameters['context'])),
      GoRoute(path:'/margins',builder:(context,state)=>const MarginsPage()),
      GoRoute(path:'/margins/workspace/:id',builder:(context,state)=>MarginWorkspacePage(id:state.pathParameters['id']!)),
      GoRoute(path:'/margins/import',builder:(context,state)=>const MarginImportPage()),
      GoRoute(path:'/margins/member',builder:(context,state)=>MarginMemberPage(id:state.uri.queryParameters['workspace']??'')),
      GoRoute(path:'/margins/new',builder:(context,state)=>MarginNewPage(workspaceId:state.uri.queryParameters['workspace']??'',itemId:state.uri.queryParameters['source'],annotationId:state.uri.queryParameters['annotation'],replyTo:state.uri.queryParameters['reply'])),
      GoRoute(path:'/margins/edit',builder:(context,state)=>MarginEditPage(workspaceId:state.uri.queryParameters['workspace']??'',entryId:state.uri.queryParameters['entry']??'',revisionId:state.uri.queryParameters['revision']??'')),
      GoRoute(path:'/margins/thread',builder:(context,state)=>MarginThreadPage(workspaceId:state.uri.queryParameters['workspace']??'',entryId:state.uri.queryParameters['entry']??'')),
      GoRoute(path:'/knowledge',builder:(context,state)=>KnowledgePage(projectId:state.uri.queryParameters['project'])),
      GoRoute(path:'/knowledge/new',builder:(context,state)=>DecisionEditorPage(projectId:state.uri.queryParameters['project'],sourceId:state.uri.queryParameters['source'])),
      GoRoute(path:'/knowledge/edit/:id',builder:(context,state)=>DecisionEditorPage(id:state.pathParameters['id']!)),
      GoRoute(path:'/knowledge/decision/:id',builder:(context,state)=>DecisionPage(id:state.pathParameters['id']!)),
      GoRoute(path:'/knowledge/map',builder:(context,state)=>KnowledgeMapPage(kind:state.uri.queryParameters['kind']??'library',id:state.uri.queryParameters['id']??'')),
      GoRoute(path:'/knowledge/path',builder:(context,state)=>const KnowledgePathPage()),
      GoRoute(path:'/knowledge/compress',builder:(context,state)=>CompressionCreatePage(scopeKind:state.uri.queryParameters['kind']??'selected',scopeId:state.uri.queryParameters['id'],sourceId:state.uri.queryParameters['source'])),
      GoRoute(path:'/knowledge/compression/:id',builder:(context,state)=>CompressionPage(id:state.pathParameters['id']!)),
      GoRoute(path:'/knowledge/source/:id',builder:(context,state)=>SourceIntelligencePage(id:state.pathParameters['id']!)),
      GoRoute(path:'/knowledge/diff',builder:(context,state)=>SourceDiffPage(beforeId:state.uri.queryParameters['before']??'',afterId:state.uri.queryParameters['after']??'')),
      GoRoute(path: '/memory', builder: (context, state) => const MemoryPage()),
      GoRoute(path: '/memory/topic/:id', builder: (context, state) => MemoryTopicPage(topicId: state.pathParameters['id']!)),
      GoRoute(path: '/memory/project/:id', builder: (context, state) => MemoryProjectPage(projectId: state.pathParameters['id']!)),
      GoRoute(path: '/signal', builder: (context, state) => const DailySignalPage()),
      GoRoute(path: '/signal/settings', builder: (context, state) => const SignalSettingsPage()),
      GoRoute(path: '/sense', builder: (context, state) => const SensePage()),
      GoRoute(path: '/xray/documents', builder: (context, state) => const ConsumerDocumentsPage()),
      GoRoute(path: '/xray/document/:id', builder: (context, state) => ConsumerDocumentPage(itemId: state.pathParameters['id']!)),
      GoRoute(path: '/xray/compare', builder: (context, state) => ConsumerComparePage(idsJson: state.uri.queryParameters['ids'] ?? '[]')),
      GoRoute(path: '/xray', builder: (context, state) => const XrayPage()),
      GoRoute(path: '/vault', builder: (context, state) => const VaultPage()),
      GoRoute(path: '/capture/jobs', builder: (context, state) => const CaptureJobsPage()),
      GoRoute(path: '/shares', builder: (context, state) => const SharedDraftsPage()),
      GoRoute(path: '/import', builder: (context, state) => ImportPage(initialText: state.extra is String ? state.extra as String : '', initialFile: state.extra is SharedDraft ? (state.extra as SharedDraft).file : null, sharedDraftId: state.extra is SharedDraft ? (state.extra as SharedDraft).id : null, sharedDraftStaged: state.extra is SharedDraft && (state.extra as SharedDraft).staged)),
      GoRoute(
        path: '/reader/:id',
        builder: (context, state) => ReaderPage(itemId: state.pathParameters['id']!, focusBlock: int.tryParse(state.uri.queryParameters['block'] ?? '')),
      ),
    ],
  );
});
