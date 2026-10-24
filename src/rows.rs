//! Bounded fill-only legacy formatting; no Substreams execution or host calls.
use crate::{fills, native};
use prost::Message;
use std::fmt;
pub use substreams::pb::substreams::Clock;
use substreams::Hex;
use substreams_database_change::{pb::database::DatabaseChanges, tables::Tables};

#[derive(Clone, Copy, Debug)]
pub struct Limits {
    pub max_fills: usize,
    /// Combined encoded input fill size and final DatabaseChanges size.
    /// Not a peak allocation or process-memory guarantee.
    pub max_bytes: usize,
}
impl Default for Limits {
    fn default() -> Self {
        Self {
            max_fills: 65_536,
            max_bytes: 64 * 1024 * 1024,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FormatError {
    InvalidBounds,
    Identity,
    Capacity,
}
impl fmt::Display for FormatError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::InvalidBounds => "invalid Hypercore row bounds",
            Self::Identity => "Hypercore projection and clock disagree",
            Self::Capacity => "Hypercore row capacity exceeded",
        })
    }
}
impl std::error::Error for FormatError {}

/// Reuse an already projected complete fill list without cloning the block,
/// decoding again or traversing unrelated events. Retains the existing three
/// fill tables, source indexes, numeric defaults and outcome-first selection.
/// The caller chooses which tables to serve after formatting. No blocks row is
/// added, and no field is promoted to an exact canonical numeric observation.
pub fn fill_changes(
    clock: &Clock,
    projection: &native::Projection<'_>,
    limits: Limits,
) -> Result<DatabaseChanges, FormatError> {
    if !(1..=100_000).contains(&limits.max_fills)
        || !(1..=64 * 1024 * 1024).contains(&limits.max_bytes)
    {
        return Err(FormatError::InvalidBounds);
    }
    let time = projection
        .header
        .block_time
        .as_ref()
        .ok_or(FormatError::Identity)?;
    let clock_time = clock.timestamp.as_ref().ok_or(FormatError::Identity)?;
    if clock.number != projection.header.block_number
        || clock.id.is_empty()
        || clock.id.len() > 256
        || clock.id.chars().any(char::is_control)
        || !(0..=253_402_300_799).contains(&time.seconds)
        || !(0..1_000_000_000).contains(&time.nanos)
        || clock_time.seconds != time.seconds
        || clock_time.nanos != time.nanos
    {
        return Err(FormatError::Identity);
    }
    if projection.fills().len() > limits.max_fills {
        return Err(FormatError::Capacity);
    }
    let mut input_bytes = 0usize;
    for row in projection.fills() {
        input_bytes = input_bytes.saturating_add(row.fill.encoded_len());
        if input_bytes > limits.max_bytes {
            return Err(FormatError::Capacity);
        }
    }
    let mut tables = Tables::new();
    for row in projection.fills() {
        fills::process_projected_fill(&mut tables, clock, row.index as usize, row.fill, row.kind);
    }
    let changes = tables.to_database_changes();
    if changes.encoded_len() > limits.max_bytes {
        return Err(FormatError::Capacity);
    }
    Ok(changes)
}

/// Parse a string value to f64, returning 0.0 if parsing fails
pub fn parse_f64(value: &str) -> f64 {
    value.parse().unwrap_or(0.0)
}

pub fn set_numeric_field(
    row: &mut substreams_database_change::tables::Row,
    field: &str,
    value: &str,
) {
    row.set(field, parse_f64(value).to_string());
}

pub fn set_clock(clock: &Clock, row: &mut substreams_database_change::tables::Row) {
    row.set("block_num", clock.number);
    row.set("block_hash", format!("0x{}", clock.id));
    let seconds = clock.timestamp.as_ref().map(|t| t.seconds).unwrap_or(0);
    row.set("timestamp", seconds);
}

pub fn set_event_metadata(
    clock: &Clock,
    event_index: usize,
    hash: &[u8],
    time: Option<&prost_types::Timestamp>,
    row: &mut substreams_database_change::tables::Row,
) {
    set_clock(clock, row);
    row.set("event_index", event_index as u32);
    row.set("event_hash", format!("0x{}", Hex::encode(hash)));
    row.set("event_time", time.map(|t| t.seconds).unwrap_or(0));
}

pub fn event_key(clock: &Clock, event_index: usize, hash: &[u8]) -> [(&'static str, String); 5] {
    let seconds = clock
        .timestamp
        .as_ref()
        .map(|t| t.seconds)
        .unwrap_or_default();
    [
        ("timestamp", seconds.to_string()),
        ("block_num", clock.number.to_string()),
        ("event_index", event_index.to_string()),
        ("event_hash", format!("0x{}", Hex::encode(hash))),
        ("block_hash", format!("0x{}", &clock.id)),
    ]
}

#[cfg(test)]
mod tests;
