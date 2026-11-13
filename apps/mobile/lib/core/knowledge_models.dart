class DecisionRecord {
  DecisionRecord({required this.id,required this.title,required this.context,required this.options,required this.selectedOption,required this.reasoning,required this.decisionTs,required this.expectedOutcome,this.reviewTs,this.projectId,required this.sourceIds,required this.createdTs,required this.updatedTs,required this.archived,required this.kind});
  final String id,title,context,selectedOption,reasoning,expectedOutcome,kind;
  final List<String> options,sourceIds;
  final int decisionTs,createdTs,updatedTs;
  final int? reviewTs;
  final String? projectId;
  final bool archived;
  factory DecisionRecord.fromJson(Map<String,dynamic> j)=>DecisionRecord(id:j['id'] as String,title:j['title'] as String,context:j['context'] as String,options:(j['options'] as List).cast<String>(),selectedOption:j['selected_option'] as String,reasoning:j['reasoning'] as String,decisionTs:(j['decision_ts'] as num).toInt(),expectedOutcome:j['expected_outcome'] as String,reviewTs:(j['review_ts'] as num?)?.toInt(),projectId:j['project_id'] as String?,sourceIds:(j['source_ids'] as List).cast<String>(),createdTs:(j['created_ts'] as num).toInt(),updatedTs:(j['updated_ts'] as num).toInt(),archived:j['archived'] as bool,kind:j['kind'] as String);
}
class KnowledgeNode {
  KnowledgeNode({required this.key,required this.kind,required this.id,required this.label,required this.ts,this.sourceItemId,this.blockIdx,required this.detail});
  final String key,kind,id,label,detail;
  final int ts;
  final String? sourceItemId;
  final int? blockIdx;
  factory KnowledgeNode.fromJson(Map<String,dynamic> j)=>KnowledgeNode(key:j['key'] as String,kind:j['kind'] as String,id:j['id'] as String,label:j['label'] as String,ts:(j['ts'] as num).toInt(),sourceItemId:j['source_item_id'] as String?,blockIdx:(j['block_idx'] as num?)?.toInt(),detail:j['detail'] as String);
}
class KnowledgeEdge {
  KnowledgeEdge({required this.sourceKey,required this.targetKey,required this.kind,required this.basis,required this.confidence,this.relationshipId});
  final String sourceKey,targetKey,kind,basis;
  final double confidence;
  final String? relationshipId;
  factory KnowledgeEdge.fromJson(Map<String,dynamic> j)=>KnowledgeEdge(sourceKey:j['source_key'] as String,targetKey:j['target_key'] as String,kind:j['kind'] as String,basis:j['basis'] as String,confidence:(j['confidence'] as num).toDouble(),relationshipId:j['relationship_id'] as String?);
}
class KnowledgeGraph {
  KnowledgeGraph({required this.focus,required this.nodes,required this.edges,this.nextOffset,required this.explanation});
  final KnowledgeNode focus;
  final List<KnowledgeNode> nodes;
  final List<KnowledgeEdge> edges;
  final int? nextOffset;
  final String explanation;
  factory KnowledgeGraph.fromJson(Map<String,dynamic> j)=>KnowledgeGraph(focus:KnowledgeNode.fromJson(j['focus'] as Map<String,dynamic>),nodes:(j['nodes'] as List).map((v)=>KnowledgeNode.fromJson(v as Map<String,dynamic>)).toList(),edges:(j['edges'] as List).map((v)=>KnowledgeEdge.fromJson(v as Map<String,dynamic>)).toList(),nextOffset:(j['next_offset'] as num?)?.toInt(),explanation:j['explanation'] as String);
}
