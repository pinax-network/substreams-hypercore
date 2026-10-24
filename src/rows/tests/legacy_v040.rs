use super::*;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

#[path = "../../../tests/support/legacy_wasm.rs"]
mod legacy_wasm;

fn cases() -> Vec<(&'static str, Block)> {
    let (_, template) = source();
    let mut cases = Vec::new();
    let single = |fill: Fill| Block {
        fills: vec![fill],
        events: vec![],
        ..template.clone()
    };
    cases.push((
        "empty",
        Block {
            fills: vec![],
            events: vec![],
            ..template.clone()
        },
    ));
    cases.push(("mixed_categories", template.clone()));
    cases.push(("regular", single(template.fills[0].clone())));
    cases.push(("liquidation", single(template.fills[1].clone())));
    cases.push(("outcome_liquidation", single(template.fills[2].clone())));
    cases.push(("unknown_values", single(template.fills[3].clone())));
    for (name, coin) in [
        ("outcome_yes", "#70"),
        ("outcome_no", "#71"),
        ("outcome_invalid_side", "#72"),
        ("outcome_overflow", "#184467440737095516160"),
        ("outcome_leading_zero", "#0071"),
        ("outcome_negative", "#-71"),
        ("empty_coin", ""),
    ] {
        cases.push((
            name,
            single(Fill {
                coin: coin.into(),
                ..template.fills[0].clone()
            }),
        ));
    }
    for (name, value) in [
        ("zero", "0"),
        ("negative", "-0.123"),
        ("negative_zero", "-0"),
        ("nan", "NaN"),
        ("infinity", "inf"),
        ("exponent", "1e-300"),
        ("decimal_precision", "9007199254740993.123456789012345678"),
        ("malformed_numeric", "invalid"),
    ] {
        let fill = Fill {
            price: value.into(),
            size: value.into(),
            fee: value.into(),
            start_position: value.into(),
            closed_pnl: value.into(),
            builder_fee: value.into(),
            deployer_fee: value.into(),
            priority_gas: value.into(),
            liquidation: Some(FillLiquidation {
                mark_px: value.into(),
                ..Default::default()
            }),
            ..template.fills[0].clone()
        };
        cases.push((name, single(fill)));
    }
    cases.push((
        "all_directions",
        Block {
            fills: (0..=23)
                .map(|direction| Fill {
                    direction,
                    ..template.fills[0].clone()
                })
                .collect(),
            events: vec![],
            ..template.clone()
        },
    ));
    cases.push((
        "all_sides",
        Block {
            fills: (0..=3)
                .map(|side| Fill {
                    side,
                    ..template.fills[0].clone()
                })
                .collect(),
            events: vec![],
            ..template.clone()
        },
    ));
    cases.push(("missing_values", single(Fill::default())));
    cases.push((
        "invalid_fill_timestamp",
        single(Fill {
            time: Some(prost_types::Timestamp {
                seconds: -1,
                nanos: -1,
            }),
            ..template.fills[0].clone()
        }),
    ));
    cases
}

fn retained(mut changes: DatabaseChanges) -> DatabaseChanges {
    changes
        .table_changes
        .retain(|row| matches!(row.table.as_str(), "fills" | "fills_liquidation"));
    for row in &mut changes.table_changes {
        row.primary_key = None;
        row.fields.sort_by(|a, b| a.name.cmp(&b.name));
    }
    changes
}
fn rows(changes: &DatabaseChanges) -> Vec<BTreeMap<String, String>> {
    changes
        .table_changes
        .iter()
        .map(|row| {
            let mut values: BTreeMap<_, _> = row
                .fields
                .iter()
                .map(|f| (f.name.clone(), f.new_value.clone()))
                .collect();
            values.insert("@table".into(), row.table.clone());
            values
        })
        .collect()
}
fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[test]
fn published_v040_fill_corpus() {
    let oracle = legacy_wasm::Oracle::new();
    let (clock, _) = source();
    let mut corpus = Vec::new();
    for (name, block) in cases() {
        let bytes = block.encode_to_vec();
        let legacy_bytes = oracle
            .database(&clock.encode_to_vec(), &bytes)
            .expect("historical package must produce output");
        let legacy = retained(DatabaseChanges::decode(legacy_bytes.as_slice()).unwrap());
        let admitted = crate::decode::fills(&bytes, crate::decode::Limits::default()).unwrap();
        assert_eq!(admitted.block.fills, block.fills);
        assert_eq!(admitted.block.block_header, block.block_header);
        let projection = native::project(&admitted.block, 100_000).unwrap();
        let current = retained(fill_changes(&clock, &projection, Limits::default()).unwrap());
        assert_eq!(
            rows(&current),
            rows(&legacy),
            "{name}: unclassified historical row difference"
        );
        corpus.push(json!({"name":name,"block_hex":hex(&bytes),"block_sha256":format!("{:x}",Sha256::digest(&bytes)),
            "oracle_database_changes_hex":hex(&legacy_bytes),"rows":rows(&legacy)}));
    }
    assert_eq!(corpus.len(), 25);
    let value = json!({"schema_version":1,"package_sha256":"0754d1ed93a49f8252864e6c8428ca584cfc61d9f9e50555a09636fa08a700d3",
        "clock_hex":hex(&clock.encode_to_vec()),"cases":corpus});
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/legacy-v0.4.0/corpus.json");
    if std::env::var_os("UPDATE_HYPERCORE_LEGACY_CORPUS").as_deref()
        == Some(std::ffi::OsStr::new("1"))
    {
        std::fs::write(&path, serde_json::to_string_pretty(&value).unwrap() + "\n").unwrap();
    }
    let expected: Value = serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
    assert_eq!(value, expected);
}
