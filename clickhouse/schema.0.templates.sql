-- Template for Hypercore events --
-- Hypercore is not EVM, so we don't have traditional transaction/log fields
-- Instead we have block-level and event-level metadata
CREATE TABLE IF NOT EXISTS TEMPLATE_EVENT (
    -- block --
    block_num                   UInt64,
    block_hash                  String,
    timestamp                   DateTime('UTC'),
    minute                      UInt32 MATERIALIZED toRelativeMinuteNum(timestamp),

    -- event --
    event_index                 UInt32, -- derived from Substreams
    event_hash                  String, -- transaction/event hash from Hypercore
    event_time                  DateTime('UTC') -- event-specific timestamp
)
ENGINE = MergeTree
ORDER BY (
    timestamp, block_num
);