//! Explicit, bounded access to an existing library original. No export, external
//! app launch or destination write happens in this module.
use super::{invalid, storage};
use crate::Store;
use base64::{engine::general_purpose::STANDARD, Engine};
use content_compiler::sha256_hex;
use refract_core::{ImportStatus, Item, RefractResult};
use rusqlite::{params, OptionalExtension};
use serde::Serialize;
use std::io::Read;

const LIMIT: usize = 10 * 1024 * 1024;

#[derive(Serialize)]
pub struct ReadOriginal {
    pub source_type: String,
    pub byte_len: usize,
    pub sha256: String,
    pub bytes_base64: String,
}

impl Store {
    /// Caller must have obtained explicit user approval to read a source for a
    /// specific action. Hash checks detect inconsistency, not authenticity.
    pub fn capture_read_original(&self, id: &str, approved: bool) -> RefractResult<ReadOriginal> {
        if !approved { return Err(invalid("Explicit approval is required to access the stored original")); }
        let (item, bytes) = self.capture_original_bytes(id)?;
        Ok(ReadOriginal { source_type: item.source_type.as_str().to_owned(), byte_len: bytes.len(), sha256: item.content_hash, bytes_base64: STANDARD.encode(bytes) })
    }

    // Internal verification is also used when a user explicitly chooses an
    // existing duplicate. It never trusts a stored filesystem path.
    pub(super) fn capture_original_bytes(&self, id: &str) -> RefractResult<(Item, Vec<u8>)> {
        if id.is_empty() || id.len() > 128 || !id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_') {
            return Err(invalid("Invalid original identifier"));
        }
        let item = self.get_item(id)?.ok_or_else(|| invalid("Original source not found"))?;
        if item.status != ImportStatus::Ready { return Err(invalid("Original source is not ready")); }
        // Never use an arbitrary path from database metadata as a filesystem path.
        let recorded: Option<String> = self.conn.query_row(
            "SELECT sha256 FROM blobs WHERE item_id=?1 AND kind='original' ORDER BY id LIMIT 1",
            params![id], |row| row.get(0),
        ).optional().map_err(storage)?;
        let recorded = recorded.ok_or_else(|| invalid("Original source is unavailable"))?;
        if recorded != item.content_hash { return Err(invalid("Original metadata is inconsistent")); }
        let path = self.blob_dir.join(format!("{id}.original"));
        let mut options = std::fs::OpenOptions::new();
        options.read(true);
        // Reject final-component symlinks and avoid blocking on a FIFO/device.
        #[cfg(unix)] { use std::os::unix::fs::OpenOptionsExt; options.custom_flags(libc::O_NOFOLLOW | libc::O_NONBLOCK); }
        let file = options.open(path).map_err(|_| invalid("Original source is unavailable"))?;
        if !file.metadata().map_err(storage)?.is_file() { return Err(invalid("Original source is not a regular file")); }
        let mut bytes = Vec::new();
        file.take(LIMIT as u64 + 1).read_to_end(&mut bytes).map_err(storage)?;
        if bytes.is_empty() || bytes.len() > LIMIT { return Err(invalid("Original source size is unsupported")); }
        if sha256_hex(&bytes) != recorded { return Err(invalid("Original source differs from its recorded hash")); }
        Ok((item, bytes))
    }
}
