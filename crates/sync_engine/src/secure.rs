//! Authenticated, recipient-encrypted foreground exchange. No network transport.
use base64::{engine::general_purpose::STANDARD as B64,Engine};
use chacha20poly1305::{aead::{Aead,Payload},KeyInit,XChaCha20Poly1305,XNonce};
use ed25519_dalek::{Signer,SigningKey,VerifyingKey,Signature};
use hkdf::Hkdf;
use rand_core::{OsRng,RngCore};
use refract_core::{RefractError,RefractResult};
use serde::{Deserialize,Serialize};
use sha2::Sha256;
use x25519_dalek::{StaticSecret,PublicKey};
pub const MAX_PACKET:usize=1_600_000;
fn bad()->RefractError{RefractError::invalid("Invalid, oversized, unauthenticated or incorrectly addressed exchange")}
pub fn hex(bytes:&[u8])->String{bytes.iter().map(|b|format!("{b:02x}")).collect()}
pub fn unhex<const N:usize>(s:&str)->RefractResult<[u8;N]>{if s.len()!=2*N||!s.bytes().all(|b|b.is_ascii_digit()||(b'a'..=b'f').contains(&b)){return Err(bad());}let mut out=[0;N];for(i,b)in out.iter_mut().enumerate(){*b=u8::from_str_radix(&s[i*2..i*2+2],16).map_err(|_|bad())?;}Ok(out)}
pub fn json<T:Serialize>(value:&T)->RefractResult<String>{serde_json::to_string(value).map_err(|_|bad())}
pub fn sign(secret:&str,value:&str)->RefractResult<String>{Ok(hex(&SigningKey::from_bytes(&unhex(secret)?).sign(value.as_bytes()).to_bytes()))}
pub fn verify(public:&str,value:&str,signature:&str)->RefractResult<()>{VerifyingKey::from_bytes(&unhex(public)?).map_err(|_|bad())?.verify_strict(value.as_bytes(),&Signature::from_bytes(&unhex(signature)?)).map_err(|_|bad())}
#[derive(Debug,Clone,Serialize,Deserialize,PartialEq,Eq)]#[serde(deny_unknown_fields)]
pub struct ContactData{pub version:u32,pub name:String,pub signing_key:String,pub encryption_key:String}
#[derive(Debug,Clone,Serialize,Deserialize,PartialEq,Eq)]#[serde(deny_unknown_fields)]
pub struct Contact{pub data:ContactData,pub signature:String}
impl Contact{pub fn validate(&self)->RefractResult<()>{if self.data.version!=1||self.data.name.trim().is_empty()||self.data.name.chars().count()>80{return Err(bad());}unhex::<32>(&self.data.encryption_key)?;verify(&self.data.signing_key,&format!("refract-contact-v1:{}",json(&self.data)?),&self.signature)}}
#[derive(Serialize,Deserialize)]
pub struct LocalIdentity{pub signing_secret:String,pub encryption_secret:String,pub contact:Contact}
impl LocalIdentity{
 pub fn new(name:&str)->RefractResult<Self>{let mut signing=[0;32];let mut encryption=[0;32];OsRng.fill_bytes(&mut signing);OsRng.fill_bytes(&mut encryption);let data=ContactData{version:1,name:name.trim().into(),signing_key:hex(&SigningKey::from_bytes(&signing).verifying_key().to_bytes()),encryption_key:hex(PublicKey::from(&StaticSecret::from(encryption)).as_bytes())};let signature=sign(&hex(&signing),&format!("refract-contact-v1:{}",json(&data)?))?;let contact=Contact{data,signature};contact.validate()?;Ok(Self{signing_secret:hex(&signing),encryption_secret:hex(&encryption),contact})}
}
#[derive(Debug,Clone,Serialize,Deserialize)]#[serde(deny_unknown_fields)]
pub struct Header{pub version:u32,pub workspace_id:String,pub epoch:u64,pub kind:String,pub sender:String,pub recipient:String,pub ephemeral_key:String}
#[derive(Debug,Clone,Serialize,Deserialize)]#[serde(deny_unknown_fields)]
pub struct Packet{pub header:Header,pub nonce:String,pub body:String,pub signature:String}
fn key(shared:&[u8;32],header:&Header)->RefractResult<[u8;32]>{if shared.iter().all(|b|*b==0){return Err(bad());}let mut key=[0;32];Hkdf::<Sha256>::new(Some(b"refract-margins-v1"),shared).expand(json(header)?.as_bytes(),&mut key).map_err(|_|bad())?;Ok(key)}
pub fn seal(me:&LocalIdentity,to:&Contact,workspace:&str,epoch:u64,kind:&str,plain:&str)->RefractResult<String>{
 to.validate()?;if plain.len()>1_000_000{return Err(bad());}let mut ephemeral=[0;32];OsRng.fill_bytes(&mut ephemeral);let secret=StaticSecret::from(ephemeral);let header=Header{version:1,workspace_id:workspace.into(),epoch,kind:kind.into(),sender:me.contact.data.signing_key.clone(),recipient:to.data.signing_key.clone(),ephemeral_key:hex(PublicKey::from(&secret).as_bytes())};let shared=secret.diffie_hellman(&PublicKey::from(unhex::<32>(&to.data.encryption_key)?));let key=key(shared.as_bytes(),&header)?;let mut nonce=[0;24];OsRng.fill_bytes(&mut nonce);let body=XChaCha20Poly1305::new_from_slice(&key).map_err(|_|bad())?.encrypt(XNonce::from_slice(&nonce),Payload{msg:plain.as_bytes(),aad:json(&header)?.as_bytes()}).map_err(|_|bad())?;let nonce=B64.encode(nonce);let body=B64.encode(body);let signature=sign(&me.signing_secret,&json(&("refract-packet-v1",&header,&nonce,&body))?)?;json(&Packet{header,nonce,body,signature})
}
pub fn open(me:&LocalIdentity,text:&str)->RefractResult<(Header,String)>{
 if text.len()>MAX_PACKET{return Err(bad());}let p:Packet=serde_json::from_str(text).map_err(|_|bad())?;if p.header.version!=1||p.header.recipient!=me.contact.data.signing_key||p.header.workspace_id.len()>80||!["invite","sync","policy","receipt"].contains(&p.header.kind.as_str()){return Err(bad());}
 verify(&p.header.sender,&json(&("refract-packet-v1",&p.header,&p.nonce,&p.body))?,&p.signature)?;let shared=StaticSecret::from(unhex::<32>(&me.encryption_secret)?).diffie_hellman(&PublicKey::from(unhex::<32>(&p.header.ephemeral_key)?));let key=key(shared.as_bytes(),&p.header)?;let nonce=B64.decode(&p.nonce).map_err(|_|bad())?;if nonce.len()!=24{return Err(bad());}let body=B64.decode(&p.body).map_err(|_|bad())?;let bytes=XChaCha20Poly1305::new_from_slice(&key).map_err(|_|bad())?.decrypt(XNonce::from_slice(&nonce),Payload{msg:&body,aad:json(&p.header)?.as_bytes()}).map_err(|_|bad())?;if bytes.len()>1_000_000{return Err(bad());}Ok((p.header,String::from_utf8(bytes).map_err(|_|bad())?))
}
#[cfg(test)]mod tests{use super::*;#[test]fn recipient_encryption_and_signatures(){let a=LocalIdentity::new("A").unwrap();let b=LocalIdentity::new("B").unwrap();let c=LocalIdentity::new("C").unwrap();let packet=seal(&a,&b.contact,"w",1,"sync","private quote").unwrap();assert!(!packet.contains("private quote"));assert_eq!(open(&b,&packet).unwrap().1,"private quote");assert!(open(&c,&packet).is_err());let mut p:Packet=serde_json::from_str(&packet).unwrap();p.header.epoch=2;assert!(open(&b,&json(&p).unwrap()).is_err());assert!(unhex::<32>("é").is_err());assert!(unhex::<1>("AB").is_err());let mut upper:Packet=serde_json::from_str(&packet).unwrap();upper.signature=upper.signature.to_uppercase();assert!(open(&b,&json(&upper).unwrap()).is_err());}}
