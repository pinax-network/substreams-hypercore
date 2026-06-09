use crate::pb::pinax::hypercore::v1::{Block, Fill, FillSide, TradingDirection};
use substreams::pb::substreams::Clock;
use substreams::Hex;
use substreams_database_change::tables::Tables;

use crate::{event_key, parse_f64, set_event_metadata, set_numeric_field};

/// HIP-4 outcome markets (`#<outcome_id*10+side>`) are owned by
/// substreams-hyperliquid-outcomes. The new package consumes the same firehose
/// stream and writes outcome fills to a dedicated database, so we skip them
/// here to avoid double-writes during and after the carve-out cutover.
fn is_outcome_coin(coin: &str) -> bool {
    coin.starts_with('#')
}

pub fn process_fills(tables: &mut Tables, clock: &Clock, block: &Block) {
    for (index, fill) in block.fills.iter().enumerate() {
        // Filter runs before the liquidation branch so an outcome fill carrying
        // a `liquidation` sub-message is also skipped — outcomes don't have
        // liquidations under HIP-4 today, but the order keeps the carve-out
        // total even if HL changes that.
        if is_outcome_coin(&fill.coin) {
            continue;
        }
        if fill.liquidation.is_some() {
            // If there's liquidation data, write to fills_liquidation table
            process_fill(tables, clock, index, fill, "fills_liquidation");
        } else {
            // If there's no liquidation data, write to fills table
            process_fill(tables, clock, index, fill, "fills");
        }
    }
}

fn process_fill(tables: &mut Tables, clock: &Clock, index: usize, fill: &Fill, table_name: &str) {
    let key = event_key(clock, index, &fill.hash);
    let row = tables.create_row(table_name, key);

    set_event_metadata(clock, index, &fill.hash, fill.time.as_ref(), row);

    // Parse price, size, and fee as f64 (default to 0.0 if parsing fails)
    // Then convert back to string for database insertion (ClickHouse will parse as Float64)
    let price = parse_f64(&fill.price);
    let size = parse_f64(&fill.size);
    let fee = parse_f64(&fill.fee);

    // Format client_order_id - empty string if empty, otherwise hex encoded
    let client_order_id = if fill.client_order_id.is_empty() {
        String::new()
    } else {
        format!("0x{}", Hex::encode(&fill.client_order_id))
    };

    // Fill-specific fields
    row.set("user", format!("0x{}", Hex::encode(&fill.user)));
    row.set("coin", &fill.coin);
    row.set("price", price.to_string());
    row.set("size", size.to_string());
    row.set("side", fill_side_to_string(fill.side));
    row.set(
        "fill_time",
        fill.time.as_ref().map(|t| t.seconds).unwrap_or(0),
    );
    row.set("start_position", &fill.start_position);
    row.set("direction", trading_direction_to_string(fill.direction));
    row.set("closed_pnl", &fill.closed_pnl);
    set_numeric_field(row, "closed_pnl_num", &fill.closed_pnl);
    row.set("order_id", fill.order_id);
    row.set("crossed", fill.crossed);
    row.set("fee", fee.to_string());
    row.set("transaction_id", fill.transaction_id);
    row.set("fee_token", &fill.fee_token);
    row.set("twap_id", fill.twap_id);
    row.set("client_order_id", client_order_id);
    set_numeric_field(row, "deployer_fee", &fill.deployer_fee);
    row.set("builder", &fill.builder);
    set_numeric_field(row, "builder_fee", &fill.builder_fee);
    set_numeric_field(row, "priority_gas", &fill.priority_gas);

    // Liquidation fields
    if let Some(liq) = &fill.liquidation {
        row.set(
            "liquidated_user",
            format!("0x{}", Hex::encode(&liq.liquidated_user)),
        );
        let mark_px = parse_f64(&liq.mark_px);
        row.set("mark_px", mark_px.to_string());
        row.set("liquidation_method", &liq.method);
    } else {
        // // Only set empty values for the fills table (optional fields)
        // if table_name == "fills" {
        //     row.set("liquidated_user", "");
        //     row.set("mark_px", "");
        //     row.set("liquidation_method", "");
        // }
    }
}

fn fill_side_to_string(side: i32) -> &'static str {
    match FillSide::try_from(side) {
        Ok(FillSide::Ask) => "ASK",
        Ok(FillSide::Buy) => "BID",
        _ => "UNSPECIFIED",
    }
}

fn trading_direction_to_string(direction: i32) -> &'static str {
    match TradingDirection::try_from(direction) {
        Ok(TradingDirection::Buy) => "BUY",
        Ok(TradingDirection::Sell) => "SELL",
        Ok(TradingDirection::OpenLong) => "OPEN_LONG",
        Ok(TradingDirection::CloseLong) => "CLOSE_LONG",
        Ok(TradingDirection::OpenShort) => "OPEN_SHORT",
        Ok(TradingDirection::CloseShort) => "CLOSE_SHORT",
        Ok(TradingDirection::LongToShort) => "LONG_TO_SHORT",
        Ok(TradingDirection::ShortToLong) => "SHORT_TO_LONG",
        Ok(TradingDirection::SpotDustConversion) => "SPOT_DUST_CONVERSION",
        Ok(TradingDirection::LiquidatedCrossLong) => "LIQUIDATED_CROSS_LONG",
        Ok(TradingDirection::LiquidatedCrossShort) => "LIQUIDATED_CROSS_SHORT",
        Ok(TradingDirection::LiquidatedIsolatedLong) => "LIQUIDATED_ISOLATED_LONG",
        Ok(TradingDirection::LiquidatedIsolatedShort) => "LIQUIDATED_ISOLATED_SHORT",
        Ok(TradingDirection::AutoDeleveraging) => "AUTO_DELEVERAGING",
        Ok(TradingDirection::Settlement) => "SETTLEMENT",
        Ok(TradingDirection::NetChildVaults) => "NET_CHILD_VAULTS",
        Ok(TradingDirection::BackstopBorrowLiquidation) => "BACKSTOP_BORROW_LIQUIDATION",
        Ok(TradingDirection::PartialBorrowLiquidation) => "PARTIAL_BORROW_LIQUIDATION",
        Ok(TradingDirection::SplitOutcome) => "SPLIT_OUTCOME",
        Ok(TradingDirection::MergeOutcome) => "MERGE_OUTCOME",
        Ok(TradingDirection::MergeQuestion) => "MERGE_QUESTION",
        Ok(TradingDirection::NegateOutcome) => "NEGATE_OUTCOME",
        _ => "UNSPECIFIED",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_known_direction_maps_to_a_named_string() {
        // The substreams enum must round-trip every value firehose-hypercore can
        // emit. A new variant added to the proto without a match arm here would
        // silently land in CH as `UNSPECIFIED` — exactly the regression that
        // produced ~286K mis-classified outcome fills before v0.3.0.
        let cases: &[(i32, &str)] = &[
            (TradingDirection::Buy as i32, "BUY"),
            (TradingDirection::Sell as i32, "SELL"),
            (TradingDirection::OpenLong as i32, "OPEN_LONG"),
            (TradingDirection::CloseLong as i32, "CLOSE_LONG"),
            (TradingDirection::OpenShort as i32, "OPEN_SHORT"),
            (TradingDirection::CloseShort as i32, "CLOSE_SHORT"),
            (TradingDirection::LongToShort as i32, "LONG_TO_SHORT"),
            (TradingDirection::ShortToLong as i32, "SHORT_TO_LONG"),
            (TradingDirection::SpotDustConversion as i32, "SPOT_DUST_CONVERSION"),
            (TradingDirection::LiquidatedCrossLong as i32, "LIQUIDATED_CROSS_LONG"),
            (TradingDirection::LiquidatedCrossShort as i32, "LIQUIDATED_CROSS_SHORT"),
            (TradingDirection::LiquidatedIsolatedLong as i32, "LIQUIDATED_ISOLATED_LONG"),
            (TradingDirection::LiquidatedIsolatedShort as i32, "LIQUIDATED_ISOLATED_SHORT"),
            (TradingDirection::AutoDeleveraging as i32, "AUTO_DELEVERAGING"),
            (TradingDirection::Settlement as i32, "SETTLEMENT"),
            (TradingDirection::NetChildVaults as i32, "NET_CHILD_VAULTS"),
            (TradingDirection::BackstopBorrowLiquidation as i32, "BACKSTOP_BORROW_LIQUIDATION"),
            (TradingDirection::PartialBorrowLiquidation as i32, "PARTIAL_BORROW_LIQUIDATION"),
            (TradingDirection::SplitOutcome as i32, "SPLIT_OUTCOME"),
            (TradingDirection::MergeOutcome as i32, "MERGE_OUTCOME"),
            (TradingDirection::MergeQuestion as i32, "MERGE_QUESTION"),
            (TradingDirection::NegateOutcome as i32, "NEGATE_OUTCOME"),
        ];
        for (value, expected) in cases {
            assert_eq!(
                trading_direction_to_string(*value),
                *expected,
                "TradingDirection={} mapped to wrong string",
                value
            );
        }
    }

    #[test]
    fn unspecified_and_unknown_directions_fall_back() {
        assert_eq!(trading_direction_to_string(0), "UNSPECIFIED");
        assert_eq!(trading_direction_to_string(9999), "UNSPECIFIED");
        assert_eq!(trading_direction_to_string(-1), "UNSPECIFIED");
    }

    #[test]
    fn fill_side_mapping() {
        assert_eq!(fill_side_to_string(FillSide::Ask as i32), "ASK");
        assert_eq!(fill_side_to_string(FillSide::Buy as i32), "BID");
        assert_eq!(fill_side_to_string(FillSide::Unspecified as i32), "UNSPECIFIED");
        assert_eq!(fill_side_to_string(9999), "UNSPECIFIED");
    }

    #[test]
    fn outcome_coin_filter_matches_hash_prefix() {
        // Every `#`-prefixed coin belongs to substreams-hyperliquid-outcomes.
        // We don't validate the digit shape here — the outcomes package enforces
        // strict `#<digits>` + `side ∈ {0, 1}`. Malformed `#`-prefixed coins are
        // dropped by both sinks rather than landing as a phantom outcome 0.
        assert!(is_outcome_coin("#0"));
        assert!(is_outcome_coin("#1"));
        assert!(is_outcome_coin("#1420"));
        assert!(is_outcome_coin("#")); // bare `#` — still skipped here
        assert!(is_outcome_coin("#abc")); // non-digit tail — still skipped here

        // The other three HL coin namespaces pass through to normal processing:
        // perp (plain symbol), spot (`@N`), and custom dex (`prefix:COIN`).
        assert!(!is_outcome_coin("BTC"));
        assert!(!is_outcome_coin("XMR"));
        assert!(!is_outcome_coin("@107"));
        assert!(!is_outcome_coin("xyz:WHEAT"));
        assert!(!is_outcome_coin("xyz:SKHX"));
        assert!(!is_outcome_coin("cash:TSLA"));
        assert!(!is_outcome_coin(""));

        // `#` matters only at the very start — embedded `#` does not signal an
        // outcome, so a hypothetical custom-dex coin like `xyz:#foo` passes
        // through.
        assert!(!is_outcome_coin("xyz:#foo"));
        assert!(!is_outcome_coin("BTC#1"));
    }
}
