use substreams::Hex;

pub fn bytes_to_hex(bytes: &[u8]) -> String {
    format! {"0x{}", Hex::encode(bytes)}.to_string()
}
