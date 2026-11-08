//! Deterministic consumer-document candidates. Values are supported by exact
//! UTF-8 clause ranges in extracted source text, not by claims of authenticity.
pub const VERSION: &str = "consumer-rules-v1";

#[derive(Debug, Clone)]
pub struct Candidate {
    pub category: String, pub field: String, pub value: String, pub value_type: String,
    pub amount_minor: Option<i64>, pub currency: Option<String>, pub date_ts: Option<i64>,
    pub quote: String, pub start_byte: usize, pub end_byte: usize, pub confidence: f64,
}
pub struct Extraction { pub claims: Vec<Candidate>, pub truncated: bool }

/// Split at newlines/semicolons or sentence punctuation followed by whitespace.
/// Decimal points and internal URL dots remain intact. Offsets are always into
/// the original string, never into its Unicode-lowercased representation.
pub(crate) fn clauses(text: &str) -> Vec<(usize, &str)> {
    let mut out=Vec::new();let mut start=0;
    for (index,c) in text.char_indices() {
        let end=index+c.len_utf8();
        let boundary=c=='\n'||c==';'||(['.','!','?'].contains(&c)&&(end==text.len()||text[end..].starts_with(char::is_whitespace)));
        if boundary { push_clause(text,start,end,&mut out);start=end; }
    }
    if start<text.len(){push_clause(text,start,text.len(),&mut out);}out
}
fn push_clause<'a>(text:&'a str,start:usize,end:usize,out:&mut Vec<(usize,&'a str)>) {
    let raw=&text[start..end];let trimmed=raw.trim();if !trimmed.is_empty(){out.push((start+raw.len()-raw.trim_start().len(),trimmed));}
}
fn candidate(category:&str,field:&str,value:String,kind:&str,at:usize,quote:&str,confidence:f64)->Candidate {
    Candidate{category:category.into(),field:field.into(),value,value_type:kind.into(),amount_minor:None,currency:None,date_ts:None,quote:quote.into(),start_byte:at,end_byte:at+quote.len(),confidence}
}
/// Valid UTC ISO calendar date. No locale, relative-date or timezone inference.
pub fn iso_date(s:&str)->Option<i64>{
    if s.len()!=10{return None;}let b=s.as_bytes();if !b.iter().enumerate().all(|(i,c)|if i==4||i==7{*c==b'-'}else{c.is_ascii_digit()}){return None;}
    let y:i64=s[0..4].parse().ok()?;let m:i64=s[5..7].parse().ok()?;let d:i64=s[8..10].parse().ok()?;
    if !(1970..=2200).contains(&y)||!(1..=12).contains(&m){return None;}
    let leap=y%4==0&&(y%100!=0||y%400==0);let max=match m{2=>if leap{29}else{28},4|6|9|11=>30,_=>31};if d<1||d>max{return None;}
    let yy=y-if m<=2{1}else{0};let era=yy/400;let yoe=yy-era*400;let mp=(m+9)%12;let doy=(153*mp+2)/5+d-1;
    Some((era*146097+yoe*365+yoe/4-yoe/100+doy-719468)*86400)
}
fn dates(text:&str)->Vec<(&str,i64)>{
    text.as_bytes().windows(10).enumerate().filter_map(|(i,w)|{
        if !w.iter().enumerate().all(|(n,c)|if n==4||n==7{*c==b'-'}else{c.is_ascii_digit()}){return None;}
        if i>0&&text.as_bytes()[i-1].is_ascii_digit(){return None;}if i+10<text.len()&&text.as_bytes()[i+10].is_ascii_digit(){return None;}
        let value=&text[i..i+10];iso_date(value).map(|ts|(value,ts))
    }).collect()
}
// Explicit two-decimal amounts only. Ambiguous grouping is left as a clause.
fn money(quote:&str)->Option<(String,i64,Option<String>)>{
    let tokens=quote.split_whitespace().filter_map(|s|{
        let n=s.trim_matches(|c:char|!c.is_ascii_digit()&&c!='.'&&c!=','&&c!='-').trim_end_matches(['.',',']);
        let split=n.rfind(['.',','])?;let (whole,fraction)=n.split_at(split);let fraction=&fraction[1..];
        if fraction.len()!=2||!fraction.bytes().all(|b|b.is_ascii_digit()){return None;}
        let separator=n.as_bytes()[split] as char;let group=if separator=='.'{','}else{'.'};
        let sign=if whole.starts_with('-'){-1}else{1};let whole=whole.strip_prefix('-').unwrap_or(whole);
        let groups=whole.split(group).collect::<Vec<_>>();
        if groups.iter().any(|g|g.is_empty()||!g.bytes().all(|b|b.is_ascii_digit()))||groups.len()>1&&(groups[0].len()>3||groups.iter().skip(1).any(|g|g.len()!=3)){return None;}
        let major=groups.join("").parse::<i64>().ok()?;let minor=major.checked_mul(100)?.checked_add(fraction.parse::<i64>().ok()?)?.checked_mul(sign)?;
        Some((n.to_string(),minor))
    }).collect::<Vec<_>>();
    if tokens.len()!=1{return None;}
    let codes=quote.split(|c:char|!c.is_ascii_alphabetic()).map(str::to_uppercase).filter(|s|["USD","EUR","GBP","RON","CAD","AUD","CHF","JPY"].contains(&s.as_str())).collect::<std::collections::BTreeSet<_>>();
    let currency=if codes.len()==1{codes.into_iter().next()}else if codes.is_empty()&&quote.contains('€'){Some("EUR".into())}else{None};
    Some((tokens[0].0.clone(),tokens[0].1,currency))
}

pub fn extract(text:&str)->Extraction {
    let mut result=Extraction{claims:Vec::new(),truncated:false};
    // Work is bounded without losing or rewriting any original text.
    let units=clauses(text);if units.len()>2000{result.truncated=true;}
    for (at,quote) in units.into_iter().take(2000){
        if quote.chars().count()>2000{result.truncated=true;continue;}
        let lower=quote.to_lowercase();
        for (label,field,category) in [("merchant:","merchant","receipt"),("vendor:","merchant","receipt"),("order id:","order_id","order"),("order number:","order_id","order"),("receipt id:","receipt_id","receipt"),("service:","service","subscription"),("plan:","plan","subscription")]{
            // ASCII labels at the beginning: the slice offset is not derived
            // from a Unicode-lowercased search position.
            if quote.get(..label.len()).is_some_and(|s|s.eq_ignore_ascii_case(label)){
                let value=quote[label.len()..].trim().trim_end_matches('.');if !value.is_empty(){result.claims.push(candidate(category,field,value.into(),"text",at,quote,0.8));}
            }
        }
        for (prefix,field,category) in [("total", "receipt_total","receipt"),("amount paid", "receipt_total","receipt"),("tax:","tax","receipt"),("price:","subscription_price","subscription"),("subscription price:","subscription_price","subscription")]{
            let matched=lower.strip_prefix(prefix).is_some_and(|rest|prefix.ends_with(':')||rest.starts_with(':')||rest.starts_with(char::is_whitespace));
            if matched{
                if let Some((value,minor,currency))=money(quote){let mut c=candidate(category,field,value,"money",at,quote,0.75);c.amount_minor=Some(minor);c.currency=currency;result.claims.push(c);}
                else{result.claims.push(candidate(category,&format!("{field}_clause"),quote.into(),"clause",at,quote,0.45));}
            }
        }
        for (needles,field,category) in [
            (&["renew"][..],"renewal_terms","subscription"),(&["trial"][..],"trial_terms","subscription"),
            (&["refund","return policy"][..],"refund_policy","refund"),(&["warranty"][..],"warranty_terms","warranty"),
            (&["cancel"][..],"cancellation_instructions","cancellation"),(&["deliver","shipping"][..],"delivery_terms","delivery"),
            (&["order confirmed","order confirmation"][..],"order_status","order"),
        ]{
            if needles.iter().any(|n|lower.contains(n)){result.claims.push(candidate(category,field,quote.into(),"clause",at,quote,0.65));}
        }
        let found=dates(quote);if found.len()==1{
            let date_fields=[
                (lower.contains("renew"),"renewal_date","subscription"),
                (lower.contains("trial")&&(lower.contains("end")||lower.contains("expir")),"trial_end","subscription"),
                (lower.contains("warranty")&&(lower.contains("expir")||lower.contains("end")||lower.contains("until")),"warranty_expiry","warranty"),
                (lower.contains("deliver")&&(lower.contains(" on ")||lower.contains(" by ")||lower.contains("expected")||lower.contains("date")),"delivery_date","delivery"),
                (lower.starts_with("purchase date:")||lower.starts_with("purchased on"),"purchase_date","receipt"),
            ];
            // More than one semantic date role in the same clause is ambiguous.
            if date_fields.iter().filter(|r|r.0).count()==1 {
                let (_,field,category)=date_fields.into_iter().find(|r|r.0).unwrap();let mut c=candidate(category,field,found[0].0.into(),"date",at,quote,0.7);c.date_ts=Some(found[0].1);result.claims.push(c);
            }
        }
        let freqs=[("monthly",["monthly","per month"]),("yearly",["yearly","per year"]),("weekly",["weekly","per week"])];
        let hits=freqs.iter().filter(|(_,cues)|cues.iter().any(|s|lower.contains(s))).collect::<Vec<_>>();
        if hits.len()==1 && ["subscription","bill","renew","price","charged"].iter().any(|s|lower.contains(s)) {
            result.claims.push(candidate("subscription","billing_frequency",hits[0].0.into(),"frequency",at,quote,0.7));
        }
        if result.claims.len()>=100{result.claims.truncate(100);result.truncated=true;break;}
    }
    result
}

#[cfg(test)]mod tests{
    use super::*;
    #[test]fn receipt_money_and_exact_unicode_ranges(){
        let text="İ中文🙂\nMerchant: Prism Shop\nTotal: EUR 1.299,00\nTax: EUR 19,00";let r=extract(text);
        let total=r.claims.iter().find(|c|c.field=="receipt_total").unwrap();assert_eq!(total.amount_minor,Some(129900));assert_eq!(total.currency.as_deref(),Some("EUR"));
        for c in r.claims{assert_eq!(&text[c.start_byte..c.end_byte],c.quote);}
    }
    #[test]fn subscription_dates_policies_and_frequency(){
        let r=extract("Service: StreamCo\nPrice: USD 9.99 monthly subscription. Renews on 2027-02-28. Trial ends 2027-01-10. Cancel at https://example.org/cancel. Refund within 14 days. Warranty expires 2028-01-01. Delivery expected 2027-01-12.");
        for field in ["service","subscription_price","billing_frequency","renewal_date","trial_end","cancellation_instructions","refund_policy","warranty_expiry","delivery_date"]{assert!(r.claims.iter().any(|c|c.field==field),"missing {field}");}
        assert!(r.claims.iter().any(|c|c.quote.contains("https://example.org/cancel")));
    }
    #[test]fn ambiguities_remain_clauses_not_inferred_dates(){
        let r=extract("Trial ends 2027-01-01 and renews 2027-02-01. Warranty is two years. Total: $1,234. Renewal on 2027-02-30.");
        assert!(!r.claims.iter().any(|c|c.value_type=="date"));assert!(!r.claims.iter().any(|c|c.amount_minor.is_some()));assert!(r.claims.iter().any(|c|c.field=="warranty_terms"));
        let r=extract("Total: $9.99");assert_eq!(r.claims[0].currency,None);
    }
    #[test]fn iso_dates_and_bounds(){assert_eq!(iso_date("1970-01-01"),Some(0));assert_eq!(iso_date("2026-03-01"),Some(1772323200));assert!(iso_date("2027-02-29").is_none());assert!(extract(&"Refund policy.\n".repeat(3000)).truncated);}
}
