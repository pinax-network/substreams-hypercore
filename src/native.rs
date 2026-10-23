//! Borrowed, lossless fill projection. No Substreams execution or host calls.
use crate::pb::pinax::hypercore::v1::{Block, BlockHeader, Fill};
use std::fmt;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FillKind {
    Regular,
    Liquidation,
    /// Kept separate from ordinary fills even when liquidation metadata exists,
    /// matching the current legacy formatter's classification order.
    Outcome {
        outcome_id: u64,
        side_index: u8,
    },
}

pub fn classify(fill: &Fill) -> FillKind {
    if let Some((outcome_id, side_index)) = parse_outcome_coin(&fill.coin) {
        FillKind::Outcome {
            outcome_id,
            side_index,
        }
    } else if fill.liquidation.is_some() {
        FillKind::Liquidation
    } else {
        FillKind::Regular
    }
}

/// Parse `#<outcome_id * 10 + side>`, where side is 0 or 1. Preserve the
/// existing legacy classification for malformed/unrecognized coin names.
pub fn parse_outcome_coin(coin: &str) -> Option<(u64, u8)> {
    let rest = coin.strip_prefix('#')?;
    if rest.is_empty() || !rest.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    let value: u64 = rest.parse().ok()?;
    let side = (value % 10) as u8;
    (side <= 1).then_some((value / 10, side))
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct ProjectedFill<'a> {
    /// Original index within Block.fills, including every fill category.
    pub index: u32,
    pub kind: FillKind,
    /// All decimal strings, timestamps, raw enum values and optional provenance
    /// are borrowed verbatim. Unknown numeric enum values are not coerced.
    pub fill: &'a Fill,
}

#[derive(Debug)]
pub struct Projection<'a> {
    pub header: &'a BlockHeader,
    fills: &'a [Fill],
}

impl<'a> Projection<'a> {
    pub fn fills(&self) -> impl ExactSizeIterator<Item = ProjectedFill<'a>> + '_ {
        self.fills
            .iter()
            .enumerate()
            .map(|(index, fill)| ProjectedFill {
                index: index as u32,
                kind: classify(fill),
                fill,
            })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ProjectError {
    MissingHeader,
    Capacity,
}

impl fmt::Display for ProjectError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::MissingHeader => "missing Hypercore block header",
            Self::Capacity => "Hypercore fill capacity exceeded",
        })
    }
}
impl std::error::Error for ProjectError {}

/// Project all fills from one already decoded Firehose block. `max_fills` is a
/// hard admission bound; no prefix is returned on failure. Input bytes and
/// protobuf allocations must be bounded by the caller before decoding.
///
/// This is extraction, not price qualification: decimal strings and timestamps
/// are not normalized or validated here. The current schema's scalar `twap_id`
/// cannot distinguish absent from zero (upstream schema sync is separate).
/// Header identity/parent proof and reorg handling belong to the Firehose
/// envelope: the payload does not supply a block hash or parent hash.
pub fn project(block: &Block, max_fills: usize) -> Result<Projection<'_>, ProjectError> {
    if block.fills.len() > max_fills || block.fills.len() > u32::MAX as usize {
        return Err(ProjectError::Capacity);
    }
    let header = block
        .block_header
        .as_ref()
        .ok_or(ProjectError::MissingHeader)?;
    Ok(Projection {
        header,
        fills: &block.fills,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pb::pinax::hypercore::v1::{Event, FillLiquidation};

    #[test]
    fn preserves_every_field_and_source_index_without_copying() {
        let fill = Fill {
            price: "9007199254740993.123456789012345678".into(),
            size: "0.000000000000000001".into(),
            fee: "not-a-number".into(),
            side: 999,
            direction: 998,
            transaction_id: u64::MAX,
            time: Some(prost_types::Timestamp {
                seconds: 1700000000,
                nanos: 123456789,
            }),
            ..Default::default()
        };
        let block = Block {
            block_header: Some(BlockHeader::default()),
            fills: vec![
                fill.clone(),
                Fill {
                    liquidation: Some(FillLiquidation::default()),
                    ..fill.clone()
                },
                Fill {
                    coin: "#71".into(),
                    liquidation: Some(FillLiquidation::default()),
                    ..fill
                },
            ],
            events: vec![Event::default()],
        };
        let projection = project(&block, 3).unwrap();
        let rows: Vec<_> = projection.fills().collect();
        assert_eq!(
            rows.iter().map(|row| row.kind).collect::<Vec<_>>(),
            vec![
                FillKind::Regular,
                FillKind::Liquidation,
                FillKind::Outcome {
                    outcome_id: 7,
                    side_index: 1
                }
            ]
        );
        for (index, row) in rows.iter().enumerate() {
            assert_eq!(row.index, index as u32);
            assert!(std::ptr::eq(row.fill, &block.fills[index]));
        }
        assert_eq!(block.events.len(), 1);
        assert_eq!(project(&block, 2).unwrap_err(), ProjectError::Capacity);
    }

    #[test]
    fn requires_header_even_for_empty_blocks() {
        assert_eq!(
            project(&Block::default(), 0).unwrap_err(),
            ProjectError::MissingHeader
        );
        let block = Block {
            block_header: Some(BlockHeader::default()),
            ..Default::default()
        };
        assert_eq!(project(&block, 0).unwrap().fills().len(), 0);
    }

    #[test]
    fn malformed_outcome_names_do_not_change_legacy_classification() {
        for coin in [
            "#",
            "#12",
            "#-10",
            "#+10",
            "#1a",
            "#18446744073709551616",
            "BTC",
            "xyz:ABC",
        ] {
            assert_eq!(parse_outcome_coin(coin), None);
            assert_eq!(
                classify(&Fill {
                    coin: coin.into(),
                    ..Default::default()
                }),
                FillKind::Regular
            );
        }
        assert_eq!(parse_outcome_coin("#0"), Some((0, 0)));
        assert_eq!(
            parse_outcome_coin("#18446744073709551610"),
            Some((1844674407370955161, 0))
        );
    }
}
