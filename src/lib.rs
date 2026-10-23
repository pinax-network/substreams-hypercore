//! Shared Hypercore fill projection with optional Substreams wrappers.
#[cfg(feature = "substreams")]
mod events;
#[cfg(feature = "substreams")]
mod fills;
#[cfg(feature = "substreams")]
mod ledger_updates;
#[cfg(feature = "substreams")]
mod legacy;
pub mod native;
pub mod pb;
#[cfg(feature = "substreams")]
pub use legacy::*;
