mod events;
mod fills;
mod ledger_updates;

use proto::pb::pinax::hypercore::v1::Block;
use substreams::errors::Error;
use substreams::pb::substreams::Clock;
use substreams::Hex;
use substreams_database_change::pb::database::DatabaseChanges;

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
    row.set("minute", seconds / 60);
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

pub fn event_key(clock: &Clock, event_index: usize, hash: &[u8]) -> [(&'static str, String); 6] {
    let seconds = clock
        .timestamp
        .as_ref()
        .map(|t| t.seconds)
        .unwrap_or_default();
    [
        ("minute", (seconds / 60).to_string()),
        ("timestamp", seconds.to_string()),
        ("block_num", clock.number.to_string()),
        ("event_index", event_index.to_string()),
        ("event_hash", format!("0x{}", Hex::encode(hash))),
        ("block_hash", format!("0x{}", &clock.id)),
    ]
}
