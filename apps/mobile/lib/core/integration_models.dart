class IntegrationCapability {
 IntegrationCapability({required this.id,required this.name,required this.availability,required this.scope,required this.limitations,required this.categories,required this.enabled,required this.allowedCategories,required this.revision});
 final String id,name,availability,scope,limitations;final List<String> categories,allowedCategories;final bool enabled;final int revision;
 bool get available=>availability=='available_local';
 factory IntegrationCapability.fromJson(Map<String,dynamic> j){final p=Map<String,dynamic>.from(j['policy'] as Map);return IntegrationCapability(id:j['id'] as String,name:j['name'] as String,availability:j['availability'] as String,scope:j['scope'] as String,limitations:j['limitations'] as String,categories:(j['categories'] as List).cast<String>(),enabled:p['enabled'] as bool,allowedCategories:(p['categories'] as List).cast<String>(),revision:(p['revision'] as num).toInt());}
}
class IntegrationEmailPreview {
 IntegrationEmailPreview.fromJson(Map<String,dynamic> j):text=j['copy_text'] as String,hash=j['review_hash'] as String,statement=j['statement'] as String;
 final String text,hash,statement;
}
class IntegrationCalendarCandidate {
 IntegrationCalendarCandidate.fromJson(Map<String,dynamic> j):id=j['id'] as String,sourceId=j['source_id'] as String,block=(j['block_idx'] as num).toInt(),localTitle=j['local_title'] as String,date=j['date'] as String,evidence=j['evidence'] as String,current=j['source_current'] as bool;
 final String id,sourceId,localTitle,date,evidence;final int block;final bool current;
}
class IntegrationCalendarCandidates {
 IntegrationCalendarCandidates.fromJson(Map<String,dynamic> j):events=(j['events'] as List).map((v)=>IntegrationCalendarCandidate.fromJson(Map<String,dynamic>.from(v as Map))).toList(),limited=j['limited'] as bool;
 final List<IntegrationCalendarCandidate> events;final bool limited;
}
class IntegrationCalendarPreview {
 IntegrationCalendarPreview.fromJson(Map<String,dynamic> j):ics=j['ics'] as String,hash=j['review_hash'] as String,preparedTs=(j['prepared_ts'] as num).toInt(),statement=j['statement'] as String;
 final String ics,hash,statement;final int preparedTs;
}
