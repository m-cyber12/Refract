class MarginContact{
 MarginContact(this.data,this.signature);final Map<String,dynamic> data;final String signature;
 String get name=>data['name'] as String;String get key=>data['signing_key'] as String;
 factory MarginContact.fromJson(Map<String,dynamic> j)=>MarginContact(j['data'] as Map<String,dynamic>,j['signature'] as String);
 Map<String,dynamic> toJson()=>{'data':data,'signature':signature};
}
class MarginMember{
 MarginMember(this.contact,this.role);final MarginContact contact;final String role;
 factory MarginMember.fromJson(Map<String,dynamic> j)=>MarginMember(MarginContact.fromJson(j['contact'] as Map<String,dynamic>),j['role'] as String);
}
class MarginRevision{
 MarginRevision(this.json);final Map<String,dynamic> json;
 String get id=>json['id'] as String;String get entryId=>json['entry_id'] as String;
 String get title=>json['title'] as String;String get body=>json['body'] as String;String get kind=>json['kind'] as String;
 bool get deleted=>json['deleted'] as bool;bool get done=>json['done'] as bool;
 String? get replyTo=>json['reply_to'] as String?;String? get collectionId=>json['collection_id'] as String?;
 Map<String,dynamic>? get anchor=>json['anchor'] as Map<String,dynamic>?;
}
class MarginEntry{
 MarginEntry({required this.id,required this.versions,required this.conflict,required this.historyCount,required this.resolutions});
 final String id;final List<MarginRevision> versions;final bool conflict;final int historyCount;final Map<String,dynamic> resolutions;
 bool get deleted=>versions.every((r)=>r.deleted);
 factory MarginEntry.fromJson(Map<String,dynamic> j)=>MarginEntry(id:j['id'] as String,versions:(j['versions'] as List).map((v)=>MarginRevision(v as Map<String,dynamic>)).toList(),conflict:j['conflict'] as bool,historyCount:(j['history_count'] as num).toInt(),resolutions:Map<String,dynamic>.from((j['resolutions'] as Map?)??{}));
}
class MarginWorkspace{
 MarginWorkspace({required this.id,required this.name,required this.owner,required this.myKey,required this.role,required this.epoch,required this.localRevision,required this.members,required this.entries,required this.enabled,required this.pendingTransfers,required this.limitations});
 final String id,name,owner,myKey,role;final int epoch,localRevision,pendingTransfers;
 final List<MarginMember> members;final List<MarginEntry> entries;final bool enabled;final List<String> limitations;
 bool get canEdit=>role=='owner'||role=='editor';
 factory MarginWorkspace.fromJson(Map<String,dynamic> j)=>MarginWorkspace(id:j['id'] as String,name:j['name'] as String,owner:j['owner'] as String,myKey:j['my_key'] as String,role:j['role'] as String,epoch:(j['epoch'] as num).toInt(),localRevision:(j['local_revision'] as num).toInt(),members:(j['members'] as List).map((v)=>MarginMember.fromJson(v as Map<String,dynamic>)).toList(),entries:(j['entries'] as List).map((v)=>MarginEntry.fromJson(v as Map<String,dynamic>)).toList(),enabled:j['exchange_enabled'] as bool,pendingTransfers:(j['pending_transfers'] as num).toInt(),limitations:(j['limitations'] as List).cast<String>());
}
