//! Consumer X-Ray: derived claims, unchanged originals, explicit review and
//! cautious source comparison. No legal verification, authenticity or active
//! subscription status is inferred from a source document.
use crate::Store;
use evidence_engine::{consumer::{extract,VERSION},sha256_hex};
use refract_core::{RefractError,RefractResult,Subscription,SubscriptionStatus};
use rusqlite::{params,OptionalExtension};
use serde::{Deserialize,Serialize};
use std::collections::{BTreeMap,BTreeSet};
fn err(e:impl std::fmt::Display)->RefractError{RefractError::storage(e.to_string())}
fn now()->RefractResult<i64>{Ok(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_err(err)?.as_secs() as i64)}
#[derive(Debug,Clone,Serialize)]
pub struct ConsumerClaim {
    pub id:String,pub item_id:String,pub block_idx:u32,pub category:String,pub field:String,pub value:String,pub value_type:String,
    pub amount_minor:Option<i64>,pub currency:Option<String>,pub date_ts:Option<i64>,pub quote:String,pub start_byte:usize,pub end_byte:usize,
    pub confidence:f64,pub extracted_ts:i64,pub extractor_version:String,pub source_text_sha256:String,pub status:String,pub source_matches:bool,
}
#[derive(Debug,Serialize)]
pub struct ConsumerScan {pub item_id:String,pub inserted_claims:usize,pub examined_blocks:usize,pub total_blocks:usize,pub truncated:bool}
#[derive(Debug,Serialize)]
pub struct ConsumerDocument {pub item_id:String,pub title:String,pub source_url:Option<String>,pub captured_ts:i64,pub original_sha256:Option<String>,pub claims:Vec<ConsumerClaim>,pub scanned:bool,pub truncated:bool,pub limitations:Vec<String>}
#[derive(Debug,Serialize)]
pub struct ConsumerSummary {pub item_id:String,pub title:String,pub categories:Vec<String>,pub claim_count:usize,pub unconfirmed_count:usize,pub scanned_ts:i64,pub truncated:bool}
#[derive(Debug,Serialize)]
pub struct ConsumerReview {pub from_status:String,pub to_status:String,pub reviewed_ts:i64}
#[derive(Debug,Serialize)]
pub struct OriginalCheck {pub item_id:String,pub status:String,pub recorded_sha256:Option<String>,pub explanation:String}
#[derive(Debug,Serialize)]
pub struct ComparisonField {pub field:String,pub result:String,pub claims:Vec<ConsumerClaim>,pub missing_item_ids:Vec<String>}
#[derive(Debug,Serialize)]
pub struct ConsumerComparison {pub item_ids:Vec<String>,pub fields:Vec<ComparisonField>,pub explanation:String}
#[derive(Debug,Default,Deserialize)]
#[serde(default,deny_unknown_fields)]
pub struct ConsumerQuery {pub query:String,pub field:Option<String>,pub status:Option<String>}

impl Store {
    pub fn consumer_analyze(&self,id:&str)->RefractResult<ConsumerScan>{
        let item=self.get_item(id)?.ok_or_else(||RefractError::invalid("consumer source not found"))?;
        let ts=now()?;let tx=self.conn.unchecked_transaction().map_err(err)?;let mut inserted=0;let mut examined=0;let mut truncated=item.blocks.len()>500;
        for block in item.blocks.iter().take(500){
            examined+=1;
            if block.text.len()>1_000_000{truncated=true;continue;}
            let extracted=extract(&block.text);truncated|=extracted.truncated;let hash=sha256_hex(block.text.as_bytes());
            for c in extracted.claims{
                inserted+=tx.execute("INSERT OR IGNORE INTO consumer_claims (id,item_id,block_idx,category,field,value,value_type,amount_minor,currency,date_ts,quote,start_byte,end_byte,confidence,extracted_ts,extractor_version,source_text_sha256) VALUES (?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13,?14,?15,?16,?17)",params![uuid::Uuid::new_v4().to_string(),id,block.idx,c.category,c.field,c.value,c.value_type,c.amount_minor,c.currency,c.date_ts,c.quote,c.start_byte as i64,c.end_byte as i64,c.confidence,ts,VERSION,hash]).map_err(err)?;
            }
        }
        tx.execute("INSERT INTO consumer_scans (item_id,scanned_ts,extractor_version,examined_blocks,total_blocks,truncated) VALUES (?1,?2,?3,?4,?5,?6) ON CONFLICT(item_id) DO UPDATE SET scanned_ts=excluded.scanned_ts,extractor_version=excluded.extractor_version,examined_blocks=excluded.examined_blocks,total_blocks=excluded.total_blocks,truncated=excluded.truncated",params![id,ts,VERSION,examined as i64,item.blocks.len() as i64,truncated]).map_err(err)?;
        tx.commit().map_err(err)?;
        Ok(ConsumerScan{item_id:id.into(),inserted_claims:inserted,examined_blocks:examined,total_blocks:item.blocks.len(),truncated})
    }
    /// Explicit bounded backfill. New imports already receive best-effort analysis.
    pub fn consumer_analyze_library(&self)->RefractResult<Vec<ConsumerScan>>{
        let mut stmt=self.conn.prepare("SELECT id FROM items WHERE sense_decision!='ignore' ORDER BY import_ts DESC,id LIMIT 500").map_err(err)?;
        let ids=stmt.query_map([],|r|r.get::<_,String>(0)).map_err(err)?.collect::<Result<Vec<_>,_>>().map_err(err)?;drop(stmt);
        ids.iter().map(|id|self.consumer_analyze(id)).collect()
    }
    fn consumer_claim_rows(&self,item:Option<&str>,query:&ConsumerQuery)->RefractResult<Vec<ConsumerClaim>>{
        if query.query.chars().count()>500||query.status.as_ref().is_some_and(|s|!["unconfirmed","user_confirmed","rejected"].contains(&s.as_str())){return Err(RefractError::invalid("invalid claim filter"));}
        let mut stmt=self.conn.prepare("SELECT c.id,c.item_id,c.block_idx,c.category,c.field,c.value,c.value_type,c.amount_minor,c.currency,c.date_ts,c.quote,c.start_byte,c.end_byte,c.confidence,c.extracted_ts,c.extractor_version,c.source_text_sha256,c.status FROM consumer_claims c JOIN items i ON i.id=c.item_id WHERE (?1 IS NOT NULL OR i.sense_decision!='ignore') AND (?1 IS NULL OR c.item_id=?1) AND (?2 IS NULL OR c.field=?2) AND (?3 IS NULL OR c.status=?3) AND (?4='' OR instr(lower(c.value||' '||c.quote||' '||c.field),lower(?4))>0) ORDER BY c.item_id,c.block_idx,c.start_byte,c.field LIMIT 1000").map_err(err)?;
        let rows=stmt.query_map(params![item,query.field,query.status,query.query],|r|Ok(ConsumerClaim{id:r.get(0)?,item_id:r.get(1)?,block_idx:r.get(2)?,category:r.get(3)?,field:r.get(4)?,value:r.get(5)?,value_type:r.get(6)?,amount_minor:r.get(7)?,currency:r.get(8)?,date_ts:r.get(9)?,quote:r.get(10)?,start_byte:r.get::<_,i64>(11)? as usize,end_byte:r.get::<_,i64>(12)? as usize,confidence:r.get(13)?,extracted_ts:r.get(14)?,extractor_version:r.get(15)?,source_text_sha256:r.get(16)?,status:r.get(17)?,source_matches:false})).map_err(err)?;
        let mut claims=rows.collect::<Result<Vec<_>,_>>().map_err(err)?;drop(stmt);
        let ids=claims.iter().map(|c|c.item_id.clone()).collect::<BTreeSet<_>>();let mut sources=BTreeMap::new();
        for id in ids{if let Some(item)=self.get_item(&id)?{sources.insert(id,item);}}
        for c in &mut claims{c.source_matches=sources.get(&c.item_id).and_then(|i|i.blocks.iter().find(|b|b.idx==c.block_idx)).is_some_and(|b|sha256_hex(b.text.as_bytes())==c.source_text_sha256&&b.text.get(c.start_byte..c.end_byte)==Some(c.quote.as_str()));}
        Ok(claims)
    }
    pub fn consumer_search(&self,query:&ConsumerQuery)->RefractResult<Vec<ConsumerClaim>>{self.consumer_claim_rows(None,query)}
    pub fn consumer_document(&self,id:&str)->RefractResult<ConsumerDocument>{
        let item=self.get_item(id)?.ok_or_else(||RefractError::invalid("consumer source not found"))?;
        let scan:Option<bool>=self.conn.query_row("SELECT truncated FROM consumer_scans WHERE item_id=?1",params![id],|r|r.get(0)).optional().map_err(err)?;
        let original=self.conn.query_row("SELECT sha256 FROM blobs WHERE item_id=?1 AND kind='original' ORDER BY id LIMIT 1",params![id],|r|r.get(0)).optional().map_err(err)?;
        let claims=self.consumer_claim_rows(Some(id),&ConsumerQuery::default())?;
        let display_limited=claims.len()>=1000;
        Ok(ConsumerDocument{item_id:id.into(),title:item.title.unwrap_or_else(||"Untitled source".into()),source_url:item.source_url,captured_ts:item.import_ts,original_sha256:original,claims,scanned:scan.is_some(),truncated:scan.unwrap_or(false)||display_limited,limitations:vec!["Candidates describe source text, not verified transactions, active subscriptions or legally enforceable rights. User confirmation is not independent verification.".into(),"English clause/label rules and explicit ISO dates only. Missing fields are not proof of absence. Currency is not inferred from a bare dollar symbol; ambiguous numbers/dates stay clauses.".into(),"Evidence offsets and fingerprints refer to extracted source blocks, not byte positions in an original PDF/HTML. Original integrity is a separate, explicit check. This view returns at most 1000 stored claims.".into()]})
    }
    pub fn consumer_documents(&self)->RefractResult<Vec<ConsumerSummary>>{
        let mut stmt=self.conn.prepare("SELECT s.item_id,COALESCE(i.title,i.id),s.scanned_ts,s.truncated FROM consumer_scans s JOIN items i ON i.id=s.item_id WHERE i.sense_decision!='ignore' AND EXISTS(SELECT 1 FROM consumer_claims c WHERE c.item_id=i.id) ORDER BY s.scanned_ts DESC,s.item_id LIMIT 200").map_err(err)?;
        let rows=stmt.query_map([],|r|Ok((r.get::<_,String>(0)?,r.get::<_,String>(1)?,r.get::<_,i64>(2)?,r.get::<_,bool>(3)?))).map_err(err)?.collect::<Result<Vec<_>,_>>().map_err(err)?;drop(stmt);
        let mut out=Vec::new();for(id,title,scanned_ts,truncated)in rows{
            let (claim_count,unconfirmed_count):(i64,i64)=self.conn.query_row("SELECT COUNT(*),COALESCE(SUM(status='unconfirmed'),0) FROM consumer_claims WHERE item_id=?1",params![id],|r|Ok((r.get(0)?,r.get(1)?))).map_err(err)?;
            let mut stmt=self.conn.prepare("SELECT DISTINCT category FROM consumer_claims WHERE item_id=?1 ORDER BY category").map_err(err)?;
            let categories=stmt.query_map(params![id],|r|r.get(0)).map_err(err)?.collect::<Result<Vec<_>,_>>().map_err(err)?;
            out.push(ConsumerSummary{item_id:id,title,categories,claim_count:claim_count as usize,unconfirmed_count:unconfirmed_count as usize,scanned_ts,truncated:truncated||claim_count>=1000});
        }Ok(out)
    }
    pub fn consumer_review(&self,id:&str,status:&str)->RefractResult<()> {
        if !["unconfirmed","user_confirmed","rejected"].contains(&status){return Err(RefractError::invalid("invalid consumer review status"));}
        if status=="user_confirmed"{
            let source:String=self.conn.query_row("SELECT item_id FROM consumer_claims WHERE id=?1",params![id],|r|r.get(0)).optional().map_err(err)?.ok_or_else(||RefractError::invalid("claim not found"))?;
            if !self.consumer_claim_rows(Some(&source),&ConsumerQuery::default())?.iter().any(|c|c.id==id&&c.source_matches){return Err(RefractError::invalid("stale or unavailable source evidence cannot be confirmed"));}
        }
        let tx=self.conn.unchecked_transaction().map_err(err)?;
        let old:String=tx.query_row("SELECT status FROM consumer_claims WHERE id=?1",params![id],|r|r.get(0)).optional().map_err(err)?.ok_or_else(||RefractError::invalid("claim not found"))?;
        if old!=status{tx.execute("INSERT INTO consumer_reviews (id,claim_id,from_status,to_status,reviewed_ts) VALUES (?1,?2,?3,?4,?5)",params![uuid::Uuid::new_v4().to_string(),id,old,status,now()?]).map_err(err)?;tx.execute("UPDATE consumer_claims SET status=?1 WHERE id=?2",params![status,id]).map_err(err)?;}
        tx.commit().map_err(err)
    }
    pub fn consumer_review_history(&self,id:&str)->RefractResult<Vec<ConsumerReview>>{
        if self.conn.query_row("SELECT COUNT(*) FROM consumer_claims WHERE id=?1",params![id],|r|r.get::<_,i64>(0)).map_err(err)?==0{return Err(RefractError::invalid("claim not found"));}
        let mut stmt=self.conn.prepare("SELECT from_status,to_status,reviewed_ts FROM consumer_reviews WHERE claim_id=?1 ORDER BY reviewed_ts,rowid").map_err(err)?;
        let rows=stmt.query_map(params![id],|r|Ok(ConsumerReview{from_status:r.get(0)?,to_status:r.get(1)?,reviewed_ts:r.get(2)?})).map_err(err)?;rows.collect::<Result<Vec<_>,_>>().map_err(err)
    }
    pub fn consumer_check_original(&self,id:&str)->RefractResult<OriginalCheck>{
        if self.get_item(id)?.is_none(){return Err(RefractError::invalid("source not found"));}
        let blob:Option<(String,String)>=self.conn.query_row("SELECT path,sha256 FROM blobs WHERE item_id=?1 AND kind='original' ORDER BY id LIMIT 1",params![id],|r|Ok((r.get(0)?,r.get(1)?))).optional().map_err(err)?;
        let Some((path,hash))=blob else{return Ok(OriginalCheck{item_id:id.into(),status:"unavailable".into(),recorded_sha256:None,explanation:"No stored original blob is available.".into()});};
        let status=match evidence_engine::verify_blob(&path,&hash){Ok(true)=>"unchanged_relative_to_recorded_hash",Ok(false)=>"hash_mismatch",Err(_)=>"unavailable"};
        Ok(OriginalCheck{item_id:id.into(),status:status.into(),recorded_sha256:Some(hash),explanation:"This compares current original bytes with a recorded SHA-256 hash. It does not prove who created a document, its authenticity, transaction validity or legal enforceability.".into()})
    }
    pub fn consumer_compare(&self,ids:&[String])->RefractResult<ConsumerComparison>{
        let unique=ids.iter().cloned().collect::<BTreeSet<_>>();if unique.len()<2||unique.len()>5||unique.len()!=ids.len(){return Err(RefractError::invalid("select two to five distinct consumer sources"));}
        let mut grouped=BTreeMap::<String,Vec<ConsumerClaim>>::new();for id in ids{let doc=self.consumer_document(id)?;for c in doc.claims.into_iter().filter(|c|c.status!="rejected"&&c.source_matches){grouped.entry(c.field.clone()).or_default().push(c);}}
        let mut fields=Vec::new();for(field,claims)in grouped{let seen=claims.iter().map(|c|c.item_id.clone()).collect::<BTreeSet<_>>();let values=claims.iter().map(|c|match c.value_type.as_str(){"money"=>format!("{:?}:{:?}",c.currency,c.amount_minor),"date"=>format!("{:?}",c.date_ts),_=>c.value.to_lowercase()}).collect::<BTreeSet<_>>();let result=if seen.len()!=ids.len(){"not_found_in_some_sources"}else if claims.iter().any(|c|c.value_type=="money"&&c.currency.is_none()){"currency_unspecified_not_comparable"}else if values.len()==1{"same_extracted_value"}else{"different_extracted_values"};fields.push(ComparisonField{field,result:result.into(),missing_item_ids:unique.difference(&seen).cloned().collect(),claims});}
        Ok(ConsumerComparison{item_ids:ids.to_vec(),fields,explanation:"Side-by-side extracted values only. The selected sources may concern different products, purchases or dates. Differences are not proof of contradiction, applicability or changed rights; no source is silently preferred. Rejected or stale-source claims are excluded. At most 1000 stored claims per selected source are considered; no currency conversion or document-applicability inference is performed.".into()})
    }
    /// Explicit opt-in projection of unambiguous user-confirmed subscription
    /// fields. Never auto-activate a subscription based on an old receipt.
    pub fn consumer_track_subscription(&self,id:&str)->RefractResult<Subscription>{
        let doc=self.consumer_document(id)?;
        let old:Option<String>=self.conn.query_row("SELECT subscription_id FROM consumer_subscription_links WHERE item_id=?1",params![id],|r|r.get(0)).optional().map_err(err)?;
        if let Some(sid)=old{return self.list_subscriptions()?.into_iter().find(|s|s.id==sid).ok_or_else(||RefractError::storage("linked subscription missing"));}
        let accepted=doc.claims.iter().filter(|c|c.status=="user_confirmed"&&c.source_matches).collect::<Vec<_>>();
        let field=|name:&str|->RefractResult<Option<&ConsumerClaim>>{let found=accepted.iter().copied().filter(|c|c.field==name).collect::<Vec<_>>();if found.len()>1{return Err(RefractError::invalid(format!("multiple confirmed {name} claims; resolve before tracking")));}Ok(found.first().copied())};
        let service=field("service")?.ok_or_else(||RefractError::invalid("confirm one explicit Service: claim first"))?;
        let price=field("subscription_price")?;if price.is_some_and(|c|c.amount_minor.is_some_and(|v|v<0)){return Err(RefractError::invalid("negative amount may be a credit, not a subscription charge"));}if price.is_some_and(|c|c.currency.is_none()){return Err(RefractError::invalid("confirmed price needs an explicit currency code"));}
        let sub=Subscription{id:uuid::Uuid::new_v4().to_string(),service:service.value.clone(),plan:field("plan")?.map(|c|c.value.clone()),price:price.and_then(|c|c.amount_minor).map(|v|v as f64/100.0),currency:price.and_then(|c|c.currency.clone()),frequency:field("billing_frequency")?.map(|c|c.value.clone()),renewal_date:field("renewal_date")?.and_then(|c|c.date_ts),trial_end:field("trial_end")?.and_then(|c|c.date_ts),status:SubscriptionStatus::Imported,confidence:accepted.iter().filter(|c|["service","plan","subscription_price","billing_frequency","renewal_date","trial_end"].contains(&c.field.as_str())).map(|c|c.confidence as f32).fold(1.0_f32,f32::min),source_doc_id:Some(id.into()),created_ts:now()?};
        // add_subscription uses this same connection, so a single SQLite
        // transaction covers both the explicit projection and its provenance link.
        let tx=self.conn.unchecked_transaction().map_err(err)?;
        self.add_subscription(&sub)?;
        tx.execute("INSERT INTO consumer_subscription_links (item_id,subscription_id,created_ts) VALUES (?1,?2,?3)",params![id,sub.id,sub.created_ts]).map_err(err)?;
        for claim in &accepted {
            if ["service","plan","subscription_price","billing_frequency","renewal_date","trial_end"].contains(&claim.field.as_str()){
                tx.execute("INSERT INTO consumer_subscription_claims (subscription_id,claim_id) VALUES (?1,?2)",params![sub.id,claim.id]).map_err(err)?;
            }
        }
        tx.commit().map_err(err)?;
        Ok(sub)
    }
}

#[cfg(test)]mod tests{
    use super::*;use refract_core::{Item,Block,BlockKind,SourceType,ImportStatus};
    fn add(s:&mut Store,id:&str,text:&str){s.insert_item(&Item{id:id.into(),source_url:Some(format!("https://example.org/{id}")),source_type:SourceType::Text,import_ts:1700000000,content_hash:sha256_hex(text.as_bytes()),title:Some(format!("Document {id}")),author:None,language:None,extraction_confidence:0.9,status:ImportStatus::Ready,blocks:vec![Block{idx:0,kind:BlockKind::Paragraph,text:text.into()}]},text.as_bytes(),&sha256_hex(text.as_bytes())).unwrap();s.conn.execute("UPDATE items SET sense_decision='auto_save' WHERE id=?1",params![id]).unwrap();}
    #[test]fn exact_evidence_idempotence_and_review_audit(){
        let mut s=Store::open_in_memory().unwrap();let text="İ🙂\nMerchant: Prism Store\nTotal: EUR 29.99\nWarranty expires 2028-01-01.";add(&mut s,"a",text);
        let before=s.get_item("a").unwrap();let d=s.consumer_document("a").unwrap();assert!(!d.claims.is_empty());for c in &d.claims{assert_eq!(&text[c.start_byte..c.end_byte],c.quote);assert!(c.source_matches);assert_eq!(c.status,"unconfirmed");}
        let id=d.claims[0].id.clone();s.consumer_review(&id,"user_confirmed").unwrap();assert_eq!(s.consumer_analyze("a").unwrap().inserted_claims,0);assert_eq!(s.consumer_document("a").unwrap().claims.iter().find(|c|c.id==id).unwrap().status,"user_confirmed");s.consumer_review(&id,"rejected").unwrap();s.consumer_review(&id,"unconfirmed").unwrap();assert_eq!(s.consumer_review_history(&id).unwrap().len(),3);assert_eq!(before,s.get_item("a").unwrap());assert!(s.consumer_review(&id,"legally_verified").is_err());
    }
    #[test]fn original_integrity_is_separate_from_source_quote(){
        let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Total: USD 9.99");assert_eq!(s.consumer_check_original("a").unwrap().status,"unchanged_relative_to_recorded_hash");
        std::fs::write(s.blob_dir.join("a.original"),b"different").unwrap();assert_eq!(s.consumer_check_original("a").unwrap().status,"hash_mismatch");assert!(s.consumer_document("a").unwrap().claims[0].source_matches);std::fs::remove_file(s.blob_dir.join("a.original")).unwrap();assert_eq!(s.consumer_check_original("a").unwrap().status,"unavailable");
    }
    #[test]fn structured_search_and_source_comparison(){
        let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Total: EUR 9.99\nWarranty expires 2028-01-01.");add(&mut s,"b","Total: EUR 10.99\nWarranty expires 2028-01-01.");
        let q=ConsumerQuery{query:"9.99".into(),..Default::default()};assert_eq!(s.consumer_search(&q).unwrap().len(),1);
        let compared=s.consumer_compare(&["a".into(),"b".into()]).unwrap();assert_eq!(compared.fields.iter().find(|f|f.field=="receipt_total").unwrap().result,"different_extracted_values");assert_eq!(compared.fields.iter().find(|f|f.field=="warranty_expiry").unwrap().result,"same_extracted_value");
        assert!(s.consumer_compare(&["a".into(),"a".into()]).is_err());assert!(s.consumer_compare(&["a".into(),"missing".into()]).is_err());
    }
    #[test]fn stale_and_rejected_claims_are_not_compared(){
        let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Total: USD 9.99");add(&mut s,"b","Total: USD 9.99");let claim=s.consumer_document("a").unwrap().claims.remove(0);s.consumer_review(&claim.id,"rejected").unwrap();let r=s.consumer_compare(&["a".into(),"b".into()]).unwrap();assert_eq!(r.fields[0].missing_item_ids,vec!["a"]);
        s.conn.execute("UPDATE blocks SET text='Changed text' WHERE item_id='b'",[]).unwrap();assert!(!s.consumer_document("b").unwrap().claims[0].source_matches);assert!(s.consumer_review(&s.consumer_document("b").unwrap().claims[0].id,"user_confirmed").is_err());assert!(s.consumer_compare(&["a".into(),"b".into()]).unwrap().fields.is_empty());
    }
    #[test]fn tracking_is_explicit_confirmed_idempotent_and_not_activation(){
        let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Service: StreamCo\nPrice: USD 9.99 monthly subscription.\nRenews on 2027-01-01.");assert!(s.list_subscriptions().unwrap().is_empty());assert!(s.consumer_track_subscription("a").is_err());
        for claim in s.consumer_document("a").unwrap().claims{s.consumer_review(&claim.id,"user_confirmed").unwrap();}
        let sub=s.consumer_track_subscription("a").unwrap();assert_eq!(sub.status,SubscriptionStatus::Imported);assert_eq!(sub.price,Some(9.99));assert_eq!(sub.renewal_date,evidence_engine::consumer::iso_date("2027-01-01"));assert_eq!(s.consumer_track_subscription("a").unwrap().id,sub.id);assert_eq!(s.list_subscriptions().unwrap().len(),1);
        let links:i64=s.conn.query_row("SELECT COUNT(*) FROM consumer_subscription_claims WHERE subscription_id=?1",params![sub.id],|r|r.get(0)).unwrap();assert!(links>=3);
    }
    #[test]fn bare_dollar_currency_cannot_be_silently_promoted(){
        let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Service: StreamCo\nPrice: $9.99 monthly subscription.");for c in s.consumer_document("a").unwrap().claims{s.consumer_review(&c.id,"user_confirmed").unwrap();}assert!(s.consumer_track_subscription("a").is_err());
    }
    #[test]fn v7_migration_preserves_subscriptions_and_originals(){
        let conn=rusqlite::Connection::open_in_memory().unwrap();for sql in [crate::MIGRATION_0001,crate::MIGRATION_0002,crate::MIGRATION_0003,crate::MIGRATION_0004,crate::MIGRATION_0005,crate::MIGRATION_0006,crate::MIGRATION_0007]{conn.execute_batch(sql).unwrap();}conn.execute("INSERT INTO subscriptions (id,service,created_ts) VALUES ('legacy','Old service',100)",[]).unwrap();let s=Store{conn,blob_dir:std::env::temp_dir().join(uuid::Uuid::new_v4().to_string())};s.migrate().unwrap();s.migrate().unwrap();assert_eq!(s.list_subscriptions().unwrap().len(),1);assert!(s.consumer_documents().unwrap().is_empty());
    }
    #[test]fn ignored_sources_do_not_surface_in_global_claim_search(){
        let mut s=Store::open_in_memory().unwrap();add(&mut s,"a","Total: EUR 9.99");s.conn.execute("UPDATE items SET sense_decision='ignore' WHERE id='a'",[]).unwrap();assert!(s.consumer_documents().unwrap().is_empty());assert!(s.consumer_search(&ConsumerQuery::default()).unwrap().is_empty());assert!(!s.consumer_document("a").unwrap().claims.is_empty());
    }

}
