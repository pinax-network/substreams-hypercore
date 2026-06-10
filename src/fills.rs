use crate::pb::pinax::hypercore::v1::{Block, Fill, FillSide, TradingDirection};
use substreams::pb::substreams::Clock;
use substreams::Hex;
use substreams_database_change::tables::Tables;

use crate::{event_key, parse_f64, set_event_metadata, set_numeric_field};

pub fn process_fills(tables: &mut Tables, clock: &Clock, block: &Block) {
    for (index, fill) in block.fills.iter().enumerate() {
        // HIP-4 outcomes use `coin = '#' + (outcome_id * 10 + side)`. Route them
        // to outcome_fills so perp/spot OHLCV MVs and leaderboards don't scan
        // the (typically smaller, structurally distinct) outcome rows, and so
        // outcome consumers don't pay the perp scan tax.
        if let Some((outcome_id, side_index)) = parse_outcome_coin(&fill.coin) {
            process_outcome_fill(tables, clock, index, fill, outcome_id, side_index);
        } else if fill.liquidation.is_some() {
            process_fill(tables, clock, index, fill, "fills_liquidation");
        } else {
            process_fill(tables, clock, index, fill, "fills");
        }
    }
}

/// Parse the HIP-4 outcome coin encoding. HL emits outcomes on coins of the
/// form `#<outcome_id * 10 + side>` where `side ∈ {0, 1}` indexes into the
/// outcome's `sideSpecs` array. Returns `None` for non-outcome coins, empty
/// suffix, non-numeric suffix, or out-of-range side.
fn parse_outcome_coin(coin: &str) -> Option<(u64, u8)> {
    let rest = coin.strip_prefix('#')?;
    if rest.is_empty() || !rest.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let n: u64 = rest.parse().ok()?;
    let side = (n % 10) as u8;
    if side > 1 {
        return None;
    }
    Some((n / 10, side))
}

fn process_outcome_fill(
    tables: &mut Tables,
    clock: &Clock,
    index: usize,
    fill: &Fill,
    outcome_id: u64,
    side_index: u8,
) {
    let key = event_key(clock, index, &fill.hash);
    let row = tables.create_row("outcome_fills", key);

    set_event_metadata(clock, index, &fill.hash, fill.time.as_ref(), row);

    let price = parse_f64(&fill.price);
    let size = parse_f64(&fill.size);
    let fee = parse_f64(&fill.fee);

    let client_order_id = if fill.client_order_id.is_empty() {
        String::new()
    } else {
        format!("0x{}", Hex::encode(&fill.client_order_id))
    };

    row.set("user", format!("0x{}", Hex::encode(&fill.user)));
    row.set("coin", &fill.coin);
    row.set("outcome_id", outcome_id);
    row.set("side_index", side_index as u32);
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

    if let Some(liq) = &fill.liquidation {
        row.set(
            "liquidated_user",
            format!("0x{}", Hex::encode(&liq.liquidated_user)),
        );
        let mark_px = parse_f64(&liq.mark_px);
        row.set("mark_px", mark_px.to_string());
        row.set("liquidation_method", &liq.method);
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
    fn outcome_coin_parse_valid() {
        assert_eq!(parse_outcome_coin("#0"), Some((0, 0)));
        assert_eq!(parse_outcome_coin("#1"), Some((0, 1)));
        assert_eq!(parse_outcome_coin("#100"), Some((10, 0)));
        assert_eq!(parse_outcome_coin("#101"), Some((10, 1)));
        assert_eq!(parse_outcome_coin("#1420"), Some((142, 0)));
        assert_eq!(parse_outcome_coin("#1421"), Some((142, 1)));
    }

    #[test]
    fn outcome_coin_parse_rejects() {
        assert_eq!(parse_outcome_coin("BTC"), None);
        assert_eq!(parse_outcome_coin("@107"), None);
        assert_eq!(parse_outcome_coin("xyz:WHEAT"), None);
        assert_eq!(parse_outcome_coin("#"), None);
        assert_eq!(parse_outcome_coin("#abc"), None);
        assert_eq!(parse_outcome_coin("#1a"), None);
        // side > 1 means the coin doesn't follow HIP-4's binary encoding
        assert_eq!(parse_outcome_coin("#102"), None);
        assert_eq!(parse_outcome_coin("#109"), None);
    }
}
