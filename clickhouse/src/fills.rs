use proto::pb::pinax::hypercore::v1::{Block, Fill, FillSide, TradingDirection};
use substreams::pb::substreams::Clock;
use substreams::Hex;
use substreams_database_change::tables::Tables;

use crate::{event_key, set_clock};

pub fn process_fills(tables: &mut Tables, clock: &Clock, block: &Block) {
    for (index, fill) in block.fills.iter().enumerate() {
        process_fill(tables, clock, index, fill);
    }
}

fn process_fill(tables: &mut Tables, clock: &Clock, index: usize, fill: &Fill) {
    let key = event_key(clock, index, &fill.hash);
    let row = tables.create_row("fills", key);

    set_clock(clock, row);

    // Event metadata
    row.set("event_index", index as u32);
    row.set("event_hash", format!("0x{}", Hex::encode(&fill.hash)));
    row.set("event_time", fill.time.as_ref().map(|t| t.seconds).unwrap_or(0));

    // Fill-specific fields
    row.set("user", format!("0x{}", Hex::encode(&fill.user)));
    row.set("coin", &fill.coin);
    row.set("price", &fill.price);
    row.set("size", &fill.size);
    row.set("side", fill_side_to_string(fill.side));
    row.set("fill_time", fill.time.as_ref().map(|t| t.seconds).unwrap_or(0));
    row.set("start_position", &fill.start_position);
    row.set("direction", trading_direction_to_string(fill.direction));
    row.set("closed_pnl", &fill.closed_pnl);
    row.set("order_id", fill.order_id);
    row.set("crossed", fill.crossed);
    row.set("fee", &fill.fee);
    row.set("transaction_id", fill.transaction_id);
    row.set("fee_token", &fill.fee_token);
    row.set("twap_id", fill.twap_id);
    row.set("client_order_id", format!("0x{}", Hex::encode(&fill.client_order_id)));

    // Liquidation fields (always set, empty when not present)
    if let Some(liq) = &fill.liquidation {
        row.set("liquidated_user", format!("0x{}", Hex::encode(&liq.liquidated_user)));
        row.set("mark_px", &liq.mark_px);
        row.set("liquidation_method", &liq.method);
    } else {
        row.set("liquidated_user", "");
        row.set("mark_px", "");
        row.set("liquidation_method", "");
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
