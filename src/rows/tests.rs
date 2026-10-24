use super::*;
use crate::pb::pinax::hypercore::v1::{Block, BlockHeader, Event, Fill, FillLiquidation};
use std::collections::BTreeMap;

mod legacy_v040;

fn source() -> (Clock, Block) {
    let time = prost_types::Timestamp {
        seconds: 1_700_000_000,
        nanos: 123_456_789,
    };
    let mut clock = Clock {
        id: "42".into(),
        number: 42,
        ..Default::default()
    };
    clock.timestamp.get_or_insert_default().seconds = time.seconds;
    clock.timestamp.get_or_insert_default().nanos = time.nanos;
    let regular = Fill {
        user: vec![1; 20],
        coin: "BTC".into(),
        price: "9007199254740993.123456789".into(),
        size: "0.000000000000000001".into(),
        side: 2,
        time: Some(time.clone()),
        start_position: "-3.000000000000001".into(),
        direction: 3,
        closed_pnl: "invalid".into(),
        hash: vec![2; 32],
        order_id: u64::MAX,
        transaction_id: u64::MAX,
        crossed: true,
        fee: "invalid".into(),
        fee_token: "USDC".into(),
        client_order_id: vec![3; 16],
        twap_id: u64::MAX,
        deployer_fee: "1e-9".into(),
        builder: "builder".into(),
        builder_fee: "0.01".into(),
        priority_gas: "0.02".into(),
        liquidation: None,
    };
    let liquidation = Fill {
        liquidation: Some(FillLiquidation {
            liquidated_user: vec![4; 20],
            mark_px: "invalid".into(),
            method: "backstop".into(),
        }),
        ..regular.clone()
    };
    let outcome = Fill {
        coin: "#71".into(),
        ..liquidation.clone()
    };
    let unknown = Fill {
        side: 999,
        direction: 998,
        time: None,
        client_order_id: vec![],
        coin: "#72".into(),
        ..regular.clone()
    };
    (
        clock,
        Block {
            block_header: Some(BlockHeader {
                block_number: 42,
                block_time: Some(time),
            }),
            fills: vec![regular, liquidation, outcome, unknown],
            events: vec![Event::default()],
        },
    )
}

fn fields(changes: &DatabaseChanges, index: usize) -> BTreeMap<String, String> {
    changes.table_changes[index]
        .fields
        .iter()
        .map(|field| (field.name.clone(), field.value.clone()))
        .collect()
}

#[test]
fn keeps_source_order_selection_values_and_defaults_without_traversing_events() {
    let (clock, block) = source();
    let projection = native::project(&block, 4).unwrap();
    let changes = fill_changes(&clock, &projection, Limits::default()).unwrap();
    assert_eq!(
        changes
            .table_changes
            .iter()
            .map(|row| row.table.as_str())
            .collect::<Vec<_>>(),
        ["fills", "fills_liquidation", "outcome_fills", "fills"]
    );
    for index in 0..4 {
        assert_eq!(fields(&changes, index)["event_index"], index.to_string());
        assert_eq!(fields(&changes, index)["block_hash"], "0x42");
        assert_eq!(
            fields(&changes, index)["transaction_id"],
            u64::MAX.to_string()
        );
    }
    let row = fields(&changes, 0);
    assert_eq!(
        row["price"],
        block.fills[0].price.parse::<f64>().unwrap().to_string()
    );
    assert_eq!(row["start_position"], block.fills[0].start_position);
    assert_eq!(row["closed_pnl"], "invalid");
    assert_eq!(row["closed_pnl_num"], "0");
    assert_eq!(row["fee"], "0");
    assert_eq!(row["side"], "BID");
    assert_eq!(fields(&changes, 1)["mark_px"], "0");
    assert!(!fields(&changes, 2).contains_key("liquidation_method"));
    let unknown = fields(&changes, 3);
    assert_eq!(unknown["side"], "UNSPECIFIED");
    assert_eq!(unknown["direction"], "UNSPECIFIED");
    assert_eq!(unknown["fill_time"], "0");
    assert_eq!(unknown["client_order_id"], "");
    assert_eq!(block.events.len(), 1);
    assert_eq!(
        projection.fills().next().unwrap().fill.price,
        "9007199254740993.123456789"
    );
}

#[test]
fn checks_identity_and_exact_complete_output_capacity() {
    let (clock, block) = source();
    let projection = native::project(&block, 4).unwrap();
    let size =
        encoded_size(&fill_changes(&clock, &projection, Limits::default()).unwrap()).unwrap();
    let exact = Limits {
        max_fills: 4,
        max_bytes: size,
    };
    assert!(fill_changes(&clock, &projection, exact).is_ok());
    assert_eq!(
        fill_changes(
            &clock,
            &projection,
            Limits {
                max_bytes: size - 1,
                ..exact
            }
        )
        .unwrap_err(),
        FormatError::Capacity
    );
    assert_eq!(
        fill_changes(
            &clock,
            &projection,
            Limits {
                max_fills: 3,
                ..exact
            }
        )
        .unwrap_err(),
        FormatError::Capacity
    );
    assert_eq!(
        fill_changes(
            &clock,
            &projection,
            Limits {
                max_fills: 0,
                ..exact
            }
        )
        .unwrap_err(),
        FormatError::InvalidBounds
    );
    let mut wrong_time = clock.clone();
    wrong_time.timestamp.get_or_insert_default().nanos = 0;
    for wrong in [
        Clock {
            number: 43,
            ..clock.clone()
        },
        Clock {
            id: "".into(),
            ..clock.clone()
        },
        Clock {
            timestamp: Default::default(),
            ..clock.clone()
        },
        wrong_time,
    ] {
        assert_eq!(
            fill_changes(&wrong, &projection, exact).unwrap_err(),
            FormatError::Identity
        );
    }
}

#[test]
fn empty_projection_has_no_block_row() {
    let (clock, mut block) = source();
    block.fills.clear();
    let projection = native::project(&block, 0).unwrap();
    assert!(fill_changes(&clock, &projection, Limits::default())
        .unwrap()
        .table_changes
        .is_empty());
}

#[cfg(feature = "substreams")]
#[test]
fn equals_all_current_wrapper_fill_rows_including_keys_and_ordinals() {
    let (clock, block) = source();
    let mut wrapper = crate::database_changes(&clock, &block);
    wrapper.table_changes.retain(|row| row.table != "blocks");
    let projection = native::project(&block, 4).unwrap();
    let mut actual = fill_changes(&clock, &projection, Limits::default()).unwrap();
    for changes in [&mut wrapper, &mut actual] {
        for row in &mut changes.table_changes {
            row.fields.sort_by(|a, b| a.name.cmp(&b.name));
        }
    }
    assert_eq!(actual, wrapper);
}
