import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'repository.dart';

/// Drop stale projections after an explicit capture/removal; this does not erase
/// independent decisions, summaries or exported/shared copies.
void refreshLibrary(WidgetRef ref){
 ref.invalidate(itemsProvider);ref.invalidate(libraryPageProvider);ref.invalidate(itemProvider);ref.invalidate(searchProvider);
 ref.invalidate(annotationsProvider);ref.invalidate(dailyEditionProvider);ref.invalidate(relatedProvider);
 ref.invalidate(summaryProvider);ref.invalidate(suggestedTagsProvider);
 ref.invalidate(dailySignalProvider);ref.invalidate(signalContextProvider);
 ref.invalidate(consumerDocumentsProvider);ref.invalidate(consumerDocumentProvider);
 ref.invalidate(consumerSearchProvider);ref.invalidate(consumerCompareProvider);ref.invalidate(consumerHistoryProvider);
 ref.invalidate(topicsProvider);ref.invalidate(entitiesProvider);ref.invalidate(memoryTimelineProvider);ref.invalidate(relationshipsProvider);
 ref.invalidate(topicItemsProvider);ref.invalidate(topicEvolutionProvider);ref.invalidate(projectItemsProvider);ref.invalidate(projectTimelineProvider);
 ref.invalidate(recallProvider);ref.invalidate(decisionsProvider);ref.invalidate(decisionProvider);
 ref.invalidate(knowledgeGraphProvider);ref.invalidate(knowledgePathProvider);
 ref.invalidate(compressionsProvider);ref.invalidate(compressionProvider);ref.invalidate(sourceIntelligenceProvider);ref.invalidate(sourceDiffProvider);
 ref.invalidate(marginWorkspaceProvider);ref.invalidate(integrationCalendarProvider);ref.invalidate(integrationCopiesProvider);
}
