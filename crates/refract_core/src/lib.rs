//! REFRACT core: shared domain types, errors and the versioned ABI contract.
//!
//! This crate is the single source of truth for the data model that crosses
//! the Rust <-> Dart FFI boundary. Every type here is serializable so the
//! platform bridge can exchange JSON documents safely.

pub mod error;
pub mod model;

/// Version of the C ABI exposed by `platform_bridge`.
///
/// Bump on any breaking change to the FFI surface. The Flutter side checks
/// this at startup and refuses to run against a mismatched library.
pub const ABI_VERSION: u32 = 1;

pub use error::{RefractError, RefractResult};
pub use model::{Block, BlockKind, ImportStatus, Item, SourceType};
