use proto::pb::pinax::hypercore::v1::{Block, Fill, FillSide, TradingDirection};
use substreams::pb::substreams::Clock;
use substreams::Hex;
use substreams_database_change::tables::Tables;

use crate::{event_key, set_event_metadata};

pub fn process_fills(tables: &mut Tables, clock: &Clock, block: &Block) {
    for (index, fill) in block.fills.iter().enumerate() {
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
    let price: f64 = fill.price.parse().unwrap_or(0.0);
    let size: f64 = fill.size.parse().unwrap_or(0.0);
    let fee: f64 = fill.fee.parse().unwrap_or(0.0);

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
    row.set("order_id", fill.order_id);
    row.set("crossed", fill.crossed);
    row.set("fee", fee.to_string());
    row.set("transaction_id", fill.transaction_id);
    row.set("fee_token", &fill.fee_token);
    row.set("twap_id", fill.twap_id);
    row.set("client_order_id", client_order_id);

    // Liquidation fields
    if let Some(liq) = &fill.liquidation {
        row.set(
            "liquidated_user",
            format!("0x{}", Hex::encode(&liq.liquidated_user)),
        );
        // Parse mark_px as f64 and convert back to string
        let mark_px: f64 = liq.mark_px.parse().unwrap_or(0.0);
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
        Ok(FillSide::Buy) => "BUY",
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
        _ => "UNSPECIFIED",
    }
}
