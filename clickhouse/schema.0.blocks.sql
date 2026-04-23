CREATE TABLE IF NOT EXISTS blocks (
    block_num                   UInt64,
    block_hash                  String,
    timestamp                   DateTime('UTC'),
    minute                      UInt32 COMMENT 'toRelativeMinuteNum(timestamp)',

    -- PROJECTIONS --
    PROJECTION prj_timestamp ( SELECT * ORDER BY timestamp )
)
ENGINE = MergeTree
ORDER BY ( block_num )
COMMENT 'Blocks';
