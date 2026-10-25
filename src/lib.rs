//! Shared Hypercore fill projection with optional Substreams wrappers.
pub mod decode;
#[cfg(feature = "substreams")]
mod events;
#[cfg(feature = "legacy-rows")]
mod fills;
#[cfg(feature = "substreams")]
mod ledger_updates;
#[cfg(feature = "substreams")]
mod legacy;
pub mod native;
#[cfg(feature = "legacy-rows")]
pub mod rows;
#[cfg(feature = "legacy-rows")]
pub use rows::{event_key, parse_f64, set_clock, set_event_metadata, set_numeric_field};
pub mod pb;
#[cfg(feature = "substreams")]
pub use legacy::*;
