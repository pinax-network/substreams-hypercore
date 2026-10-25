//! Bounded fill-only protobuf admission using the existing generated model.
//! Non-fill event bodies are skipped without allocating or decoding them.
use crate::pb::pinax::hypercore::v1::Block;
use prost::{
    bytes::{Buf, BufMut},
    encoding::{check_wire_type, skip_field, DecodeContext, WireType},
    DecodeError, Message,
};
use std::fmt;

#[derive(Clone, Copy, Debug)]
pub struct Limits {
    pub max_block_bytes: usize,
    /// Checked before decoding or allocating the next fill, including empty
    /// messages. Together with encoded bytes, this bounds retained field data
    /// and repeated Fill structures; it is not a process RSS limit.
    pub max_fills: usize,
}
impl Default for Limits {
    fn default() -> Self {
        Self {
            max_block_bytes: 32 * 1024 * 1024,
            max_fills: 65_536,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Error {
    InvalidBounds,
    Capacity,
    Encoding,
    MissingHeader,
}
impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::InvalidBounds => "invalid Hypercore decode bounds",
            Self::Capacity => "Hypercore decode capacity exceeded",
            Self::Encoding => "invalid Hypercore fill payload encoding",
            Self::MissingHeader => "missing Hypercore block header",
        })
    }
}
impl std::error::Error for Error {}

#[derive(Debug)]
pub struct DecodedFills {
    /// Header and fills only: events is always empty. This is deliberately not
    /// a full-event block decoder and must never feed non-fill projections.
    pub block: Block,
    pub skipped_event_messages: usize,
    pub skipped_unknown_fields: usize,
}

/// Decode header/fills once through generated Prost code, preserving all fields
/// represented by the current public schema. Skip unrelated event bodies and
/// unknown top-level fields with Prost's bounded wire framing. Those bodies are
/// not validated. Unknown fields inside fills follow the generated schema's
/// usual Prost behavior; schema completeness remains a separate qualification.
/// Semantic clock, identity, parent and timestamp checks belong to admission.
pub fn fills(payload: &[u8], limits: Limits) -> Result<DecodedFills, Error> {
    if !(1..=64 * 1024 * 1024).contains(&limits.max_block_bytes)
        || !(1..=100_000).contains(&limits.max_fills)
    {
        return Err(Error::InvalidBounds);
    }
    if payload.len() > limits.max_block_bytes {
        return Err(Error::Capacity);
    }
    let mut decoder = FillDecoder {
        block: Block::default(),
        max_fills: limits.max_fills,
        capacity: false,
        events: 0,
        unknown: 0,
    };
    if decoder.merge(payload).is_err() {
        return Err(if decoder.capacity {
            Error::Capacity
        } else {
            Error::Encoding
        });
    }
    if decoder.block.block_header.is_none() {
        return Err(Error::MissingHeader);
    }
    Ok(DecodedFills {
        block: decoder.block,
        skipped_event_messages: decoder.events,
        skipped_unknown_fields: decoder.unknown,
    })
}

#[derive(Debug)]
struct FillDecoder {
    block: Block,
    max_fills: usize,
    capacity: bool,
    events: usize,
    unknown: usize,
}
impl Message for FillDecoder {
    fn encode_raw(&self, buf: &mut impl BufMut) {
        self.block.encode_raw(buf);
    }
    fn encoded_len(&self) -> usize {
        self.block.encoded_len()
    }
    fn clear(&mut self) {
        self.block.clear();
        self.capacity = false;
        self.events = 0;
        self.unknown = 0;
    }
    fn merge_field(
        &mut self,
        tag: u32,
        wire: WireType,
        buf: &mut impl Buf,
        ctx: DecodeContext,
    ) -> Result<(), DecodeError> {
        match tag {
            1 => self.block.merge_field(tag, wire, buf, ctx),
            2 => {
                // Enforce the count before generated merge_repeated decodes
                // its temporary Fill or grows the vector. Never return a prefix.
                if self.block.fills.len() >= self.max_fills {
                    self.capacity = true;
                    return Err(DecodeError::new("fill count limit"));
                }
                self.block.merge_field(tag, wire, buf, ctx)
            }
            3 => {
                check_wire_type(WireType::LengthDelimited, wire)?;
                skip_field(wire, tag, buf, ctx)?;
                self.events += 1;
                Ok(())
            }
            _ => {
                skip_field(wire, tag, buf, ctx)?;
                self.unknown += 1;
                Ok(())
            }
        }
    }
}

#[cfg(test)]
mod tests;
