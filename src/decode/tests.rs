use super::*;
use crate::pb::pinax::hypercore::v1::{BlockHeader, Event, Fill, FillLiquidation};

fn block() -> Block {
    Block {
        block_header: Some(BlockHeader {
            block_number: 42,
            block_time: Some(prost_types::Timestamp {
                seconds: 1_700_000_000,
                nanos: 123_456_789,
            }),
        }),
        fills: vec![Fill {
            coin: "BTC".into(),
            price: "9007199254740993.123456789".into(),
            transaction_id: u64::MAX,
            side: 999,
            liquidation: Some(FillLiquidation {
                mark_px: "unknown".into(),
                ..Default::default()
            }),
            ..Default::default()
        }],
        events: vec![Event::default()],
    }
}

#[test]
fn same_header_and_fills_as_full_generated_decode_without_event_allocation() {
    let source = block();
    let bytes = source.encode_to_vec();
    let decoded = fills(&bytes, Limits::default()).unwrap();
    assert_eq!(decoded.block.block_header, source.block_header);
    assert_eq!(decoded.block.fills, source.fills);
    assert!(decoded.block.events.is_empty());
    assert_eq!(decoded.skipped_event_messages, 1);
    assert_eq!(decoded.skipped_unknown_fields, 0);
    let projected = crate::native::project(&decoded.block, 1).unwrap();
    assert_eq!(projected.fills().next().unwrap().fill, &source.fills[0]);
}

#[test]
fn empty_fill_messages_count_before_decode_and_byte_limits_are_exact() {
    let mut source = block();
    source.fills = vec![Fill::default(); 3];
    let bytes = source.encode_to_vec();
    let limits = Limits {
        max_block_bytes: bytes.len(),
        max_fills: 3,
    };
    assert_eq!(fills(&bytes, limits).unwrap().block.fills.len(), 3);
    assert_eq!(
        fills(
            &bytes,
            Limits {
                max_fills: 2,
                ..limits
            }
        )
        .unwrap_err(),
        Error::Capacity
    );
    assert_eq!(
        fills(
            &bytes,
            Limits {
                max_block_bytes: bytes.len() - 1,
                ..limits
            }
        )
        .unwrap_err(),
        Error::Capacity
    );
    assert_eq!(
        fills(
            &bytes,
            Limits {
                max_fills: 0,
                ..limits
            }
        )
        .unwrap_err(),
        Error::InvalidBounds
    );
    assert_eq!(fills(&[], limits).unwrap_err(), Error::MissingHeader);
}

#[test]
fn event_bodies_are_explicitly_opaque_but_outer_framing_must_be_valid() {
    let mut source = block();
    source.events.clear();
    let mut bytes = source.encode_to_vec();
    // Invalid event protobuf bytes are deliberately not parsed by a fill-only decoder.
    bytes.extend([0x1a, 1, 0xff]);
    assert!(Block::decode(bytes.as_slice()).is_err());
    let decoded = fills(&bytes, Limits::default()).unwrap();
    assert_eq!(decoded.skipped_event_messages, 1);
    assert_eq!(decoded.block.fills, source.fills);
    for suffix in [&[0x1a, 2, 0xff][..], &[0x18, 1][..], &[0x12, 1, 0xff][..]] {
        let mut bad = source.encode_to_vec();
        bad.extend(suffix);
        assert_eq!(fills(&bad, Limits::default()).unwrap_err(), Error::Encoding);
    }
}

#[test]
fn duplicate_header_merging_unknown_fields_and_recursion_keep_prost_semantics() {
    let mut source = block();
    source.events.clear();
    let mut bytes = source.encode_to_vec();
    // A second header updates number while retaining omitted time, as in Prost.
    bytes.extend([0x0a, 2, 0x08, 43, 0x78, 1]);
    let decoded = fills(&bytes, Limits::default()).unwrap();
    let expected = Block::decode(bytes.as_slice()).unwrap();
    assert_eq!(decoded.block, expected);
    assert_eq!(decoded.skipped_unknown_fields, 1);
    let mut bad = source.encode_to_vec();
    bad.extend(std::iter::repeat_n(0x7b, 101));
    bad.extend(std::iter::repeat_n(0x7c, 101));
    assert_eq!(fills(&bad, Limits::default()).unwrap_err(), Error::Encoding);
}
