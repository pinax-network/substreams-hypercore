mod events;
mod fills;
mod ledger_updates;
pub mod pb;

use crate::pb::pinax::hypercore::v1::Block;
use substreams::errors::Error;
use substreams::pb::substreams::Clock;
use substreams::Hex;
use substreams_database_change::pb::database::DatabaseChanges;

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

/// Fill-only source envelope. Preserve decimal strings, timestamps and all fill
/// provenance; consumers choose their own pricing and aggregation semantics.
#[substreams::handlers::map]
pub fn map_fills(block: Block) -> Result<Block, Error> {
    Ok(fills_only(block))
}

fn fills_only(mut block: Block) -> Block {
    block.events.clear();
    block
}

#[substreams::handlers::map]
pub fn db_out(clock: Clock, block: Block) -> Result<DatabaseChanges, Error> {
    let mut tables = substreams_database_change::tables::Tables::new();

    // Process fills
    fills::process_fills(&mut tables, &clock, &block);

    // Process events (delegations, deposits, withdrawals, funding, validator rewards)
    events::process_events(&mut tables, &clock, &block);

    // Process ledger updates (all delta types)
    ledger_updates::process_ledger_updates(&mut tables, &clock, &block);

    // ONLY include blocks if events are present
    if !tables.tables.is_empty() {
        set_clock(
            &clock,
            tables.create_row("blocks", [("block_num", clock.number.to_string())]),
        );
    }

    substreams::log::info!("Total rows {}", tables.all_row_count());
    Ok(tables.to_database_changes())
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
    let seconds = clock.timestamp.as_ref().map(|t| t.seconds).unwrap_or_default();
    [
        ("timestamp", seconds.to_string()),
        ("block_num", clock.number.to_string()),
        ("event_index", event_index.to_string()),
        ("event_hash", format!("0x{}", Hex::encode(hash))),
        ("block_hash", format!("0x{}", &clock.id)),
    ]
}

#[cfg(test)]
mod fill_stream_tests {
    use super::*;
    use crate::pb::pinax::hypercore::v1::{BlockHeader, Event, Fill, FillLiquidation};

    #[test]
    fn fill_output_preserves_precision_timestamps_and_liquidation_provenance() {
        let fill = Fill {
            coin: "xyz:TEST".into(),
            price: "9007199254740993.123456789012345678".into(),
            size: "0.000000000000000001".into(),
            fee: "0.000000000000000000123".into(),
            time: Some(prost_types::Timestamp {
                seconds: 1_700_000_000,
                nanos: 123_456_789,
            }),
            transaction_id: u64::MAX,
            user: vec![1; 20],
            hash: vec![2; 32],
            liquidation: Some(FillLiquidation {
                mark_px: "12.000000000000000001".into(),
                ..Default::default()
            }),
            ..Default::default()
        };
        let block = Block {
            block_header: Some(BlockHeader {
                block_number: 42,
                ..Default::default()
            }),
            fills: vec![fill.clone()],
            events: vec![Event::default()],
        };
        let result = fills_only(block.clone());
        assert_eq!(result.fills, vec![fill]);
        assert_eq!(result.block_header, block.block_header);
        assert!(result.events.is_empty());
    }

    #[test]
    fn a_block_without_fills_keeps_its_header() {
        let block = Block {
            block_header: Some(BlockHeader {
                block_number: 43,
                ..Default::default()
            }),
            events: vec![Event::default()],
            ..Default::default()
        };
        let result = fills_only(block.clone());
        assert!(result.fills.is_empty());
        assert!(result.events.is_empty());
        assert_eq!(result.block_header, block.block_header);
    }
}
