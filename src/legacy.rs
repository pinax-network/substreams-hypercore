use crate::pb::pinax::hypercore::v1::Block;
use crate::rows::DatabaseChanges;
use crate::set_clock;
use crate::{events, fills, ledger_updates};
use substreams::errors::Error;
use substreams::pb::substreams::Clock;

/// Fill-only source envelope. Preserve decimal strings, timestamps and all fill
/// provenance; consumers choose their own pricing and aggregation semantics.
#[cfg_attr(target_arch = "wasm32", substreams::handlers::map)]
pub fn map_fills(block: Block) -> Result<Block, Error> {
    Ok(fills_only(block))
}

fn fills_only(mut block: Block) -> Block {
    block.events.clear();
    block
}

#[cfg_attr(target_arch = "wasm32", substreams::handlers::map)]
pub fn db_out(clock: Clock, block: Block) -> Result<DatabaseChanges, Error> {
    let changes = database_changes(&clock, &block);
    substreams::log::info!("Total rows {}", changes.table_changes.len());
    Ok(changes)
}

/// Format existing legacy rows without calling Substreams host functions.
/// Native canonical consumers should use `native::project` to retain raw values.
pub fn database_changes(clock: &Clock, block: &Block) -> DatabaseChanges {
    let mut tables = substreams_database_change::tables::Tables::new();

    // Process fills
    fills::process_fills(&mut tables, clock, block);

    // Process events (delegations, deposits, withdrawals, funding, validator rewards)
    events::process_events(&mut tables, clock, block);

    // Process ledger updates (all delta types)
    ledger_updates::process_ledger_updates(&mut tables, clock, block);

    // ONLY include blocks if events are present
    if tables.all_row_count() > 0 {
        set_clock(
            clock,
            tables.create_row("blocks", [("block_num", clock.number.to_string())]),
        );
    }

    tables.to_database_changes()
}

#[cfg(test)]
mod fill_stream_tests {
    use super::*;
    use crate::pb::pinax::hypercore::v1::{BlockHeader, Event, Fill, FillLiquidation};

    #[test]
    fn host_formatter_retains_legacy_tables_and_numeric_defaults() {
        let block = Block {
            block_header: Some(BlockHeader::default()),
            fills: vec![
                Fill {
                    coin: "BTC".into(),
                    price: "invalid".into(),
                    ..Default::default()
                },
                Fill {
                    coin: "ETH".into(),
                    liquidation: Some(FillLiquidation::default()),
                    ..Default::default()
                },
                Fill {
                    coin: "#71".into(),
                    liquidation: Some(FillLiquidation::default()),
                    ..Default::default()
                },
            ],
            ..Default::default()
        };
        let changes = database_changes(
            &Clock {
                number: 42,
                id: "abc".into(),
                ..Default::default()
            },
            &block,
        );
        let mut tables: Vec<_> = changes
            .table_changes
            .iter()
            .map(|row| row.table.as_str())
            .collect();
        tables.sort();
        assert_eq!(
            tables,
            vec!["blocks", "fills", "fills_liquidation", "outcome_fills"]
        );
        let regular = changes
            .table_changes
            .iter()
            .find(|row| row.table == "fills")
            .unwrap();
        assert_eq!(
            regular
                .fields
                .iter()
                .find(|field| field.name == "price")
                .unwrap()
                .value,
            "0"
        );
        let native = crate::native::project(&block, 3).unwrap();
        assert_eq!(native.fills().next().unwrap().fill.price, "invalid");
    }

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
