/// Consumer candidates preserve evidence and review state independently of originals.
class ConsumerClaim {
  ConsumerClaim({required this.id,required this.itemId,required this.blockIdx,required this.category,required this.field,required this.value,required this.valueType,this.amountMinor,this.currency,this.dateTs,required this.quote,required this.startByte,required this.endByte,required this.confidence,required this.extractedTs,required this.extractorVersion,required this.sourceTextSha256,required this.status,required this.sourceMatches});
  final String id,itemId,category,field,value,valueType,quote,extractorVersion,sourceTextSha256,status;
  final int blockIdx,startByte,endByte,extractedTs;
  final int? amountMinor,dateTs;
  final String? currency;
  final double confidence;
  final bool sourceMatches;
  factory ConsumerClaim.fromJson(Map<String,dynamic> j)=>ConsumerClaim(id:j['id'] as String,itemId:j['item_id'] as String,blockIdx:(j['block_idx'] as num).toInt(),category:j['category'] as String,field:j['field'] as String,value:j['value'] as String,valueType:j['value_type'] as String,amountMinor:(j['amount_minor'] as num?)?.toInt(),currency:j['currency'] as String?,dateTs:(j['date_ts'] as num?)?.toInt(),quote:j['quote'] as String,startByte:(j['start_byte'] as num).toInt(),endByte:(j['end_byte'] as num).toInt(),confidence:(j['confidence'] as num).toDouble(),extractedTs:(j['extracted_ts'] as num).toInt(),extractorVersion:j['extractor_version'] as String,sourceTextSha256:j['source_text_sha256'] as String,status:j['status'] as String,sourceMatches:j['source_matches'] as bool);
}
class ConsumerSummary {
  ConsumerSummary({required this.itemId,required this.title,required this.categories,required this.claimCount,required this.unconfirmedCount,required this.scannedTs,required this.truncated});
  final String itemId,title;
  final List<String> categories;
  final int claimCount,unconfirmedCount,scannedTs;
  final bool truncated;
  factory ConsumerSummary.fromJson(Map<String,dynamic> j)=>ConsumerSummary(itemId:j['item_id'] as String,title:j['title'] as String,categories:(j['categories'] as List).cast<String>(),claimCount:(j['claim_count'] as num).toInt(),unconfirmedCount:(j['unconfirmed_count'] as num).toInt(),scannedTs:(j['scanned_ts'] as num).toInt(),truncated:j['truncated'] as bool);
}
class ConsumerDocument {
  ConsumerDocument({required this.itemId,required this.title,this.sourceUrl,required this.capturedTs,this.originalSha256,required this.claims,required this.scanned,required this.truncated,required this.limitations});
  final String itemId,title;
  final String? sourceUrl,originalSha256;
  final int capturedTs;
  final List<ConsumerClaim> claims;
  final bool scanned,truncated;
  final List<String> limitations;
  factory ConsumerDocument.fromJson(Map<String,dynamic> j)=>ConsumerDocument(itemId:j['item_id'] as String,title:j['title'] as String,sourceUrl:j['source_url'] as String?,capturedTs:(j['captured_ts'] as num).toInt(),originalSha256:j['original_sha256'] as String?,claims:(j['claims'] as List).map((v)=>ConsumerClaim.fromJson(v as Map<String,dynamic>)).toList(),scanned:j['scanned'] as bool,truncated:j['truncated'] as bool,limitations:(j['limitations'] as List).cast<String>());
}
class ConsumerComparisonField {
  ConsumerComparisonField({required this.field,required this.result,required this.claims,required this.missingItemIds});
  final String field,result;
  final List<ConsumerClaim> claims;
  final List<String> missingItemIds;
  factory ConsumerComparisonField.fromJson(Map<String,dynamic> j)=>ConsumerComparisonField(field:j['field'] as String,result:j['result'] as String,claims:(j['claims'] as List).map((v)=>ConsumerClaim.fromJson(v as Map<String,dynamic>)).toList(),missingItemIds:(j['missing_item_ids'] as List).cast<String>());
}
class ConsumerComparison {
  ConsumerComparison({required this.itemIds,required this.fields,required this.explanation});
  final List<String> itemIds;
  final List<ConsumerComparisonField> fields;
  final String explanation;
  factory ConsumerComparison.fromJson(Map<String,dynamic> j)=>ConsumerComparison(itemIds:(j['item_ids'] as List).cast<String>(),fields:(j['fields'] as List).map((v)=>ConsumerComparisonField.fromJson(v as Map<String,dynamic>)).toList(),explanation:j['explanation'] as String);
}
class ConsumerOriginalCheck {
  ConsumerOriginalCheck({required this.itemId,required this.status,this.recordedSha256,required this.explanation});
  final String itemId,status,explanation;
  final String? recordedSha256;
  factory ConsumerOriginalCheck.fromJson(Map<String,dynamic> j)=>ConsumerOriginalCheck(itemId:j['item_id'] as String,status:j['status'] as String,recordedSha256:j['recorded_sha256'] as String?,explanation:j['explanation'] as String);
}
class ConsumerReview {
  ConsumerReview({required this.fromStatus,required this.toStatus,required this.reviewedTs});
  final String fromStatus,toStatus;
  final int reviewedTs;
  factory ConsumerReview.fromJson(Map<String,dynamic> j)=>ConsumerReview(fromStatus:j['from_status'] as String,toStatus:j['to_status'] as String,reviewedTs:(j['reviewed_ts'] as num).toInt());
}
