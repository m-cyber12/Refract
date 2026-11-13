use thiserror::Error;

/// Every fallible operation in the Rust core returns this.
///
/// The FFI boundary never panics: errors are converted to this type and then
/// to JSON for the Dart side.
#[derive(Debug, Error, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum RefractError {
    #[error("invalid input: {0}")]
    InvalidInput(String),
    #[error("storage error: {0}")]
    Storage(String),
    #[error("parse error: {0}")]
    Parse(String),
    #[error("internal error: {0}")]
    Internal(String),
}

pub type RefractResult<T> = Result<T, RefractError>;

impl RefractError {
    pub fn invalid(msg: impl Into<String>) -> Self {
        RefractError::InvalidInput(msg.into())
    }
    pub fn storage(msg: impl Into<String>) -> Self {
        RefractError::Storage(msg.into())
    }
    pub fn parse(msg: impl Into<String>) -> Self {
        RefractError::Parse(msg.into())
    }
    pub fn internal(msg: impl Into<String>) -> Self {
        RefractError::Internal(msg.into())
    }
}
