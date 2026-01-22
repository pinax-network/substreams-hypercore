-- Open Interest state table --
-- Aggregates funding delta data into open interest metrics by coin
CREATE TABLE IF NOT EXISTS state_open_interest (
    -- bar interval --
    timestamp               DateTime('UTC') COMMENT 'beginning of the bar',
    interval_min            UInt16 DEFAULT 1 COMMENT 'bar interval in minutes (1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w)',

    -- timestamp & block number --
    min_timestamp           SimpleAggregateFunction(min, DateTime('UTC')) COMMENT 'first timestamp seen',
    max_timestamp           SimpleAggregateFunction(max, DateTime('UTC')) COMMENT 'last timestamp seen',
    min_block_num           SimpleAggregateFunction(min, UInt64) COMMENT 'first block number seen',
    max_block_num           SimpleAggregateFunction(max, UInt64) COMMENT 'last block number seen',

    -- trading identity --
    coin                    LowCardinality(String) COMMENT 'Trading pair/coin symbol',

    -- open interest aggregates --
    total_szi               SimpleAggregateFunction(sum, Float64) COMMENT 'total signed position size (sum of szi)',
    abs_szi                 SimpleAggregateFunction(sum, Float64) COMMENT 'absolute position size (sum of abs(szi))',
    long_szi                SimpleAggregateFunction(sum, Float64) COMMENT 'total long positions (sum of szi where szi > 0)',
    short_szi               SimpleAggregateFunction(sum, Float64) COMMENT 'total short positions (sum of szi where szi < 0, negative values preserved)',

    -- funding aggregates --
    total_funding           SimpleAggregateFunction(sum, Float64) COMMENT 'total funding amount in the window',
    positive_funding        SimpleAggregateFunction(sum, Float64) COMMENT 'sum of positive funding amounts',
    negative_funding        SimpleAggregateFunction(sum, Float64) COMMENT 'sum of negative funding amounts',

    -- funding rate --
    avg_funding_rate        AggregateFunction(avg, Float64) COMMENT 'average funding rate in the window',

    -- counts --
    funding_events          SimpleAggregateFunction(sum, UInt64) COMMENT 'number of funding events in the window',
    long_positions          SimpleAggregateFunction(sum, UInt64) COMMENT 'number of long positions',
    short_positions         SimpleAggregateFunction(sum, UInt64) COMMENT 'number of short positions',

    -- unique counts --
    uniq_user               AggregateFunction(uniq, String) COMMENT 'unique user addresses in the window',

    -- indexes --
    INDEX idx_timestamp         (timestamp)         TYPE minmax                 GRANULARITY 1,
    INDEX idx_coin              (coin)              TYPE set(256)               GRANULARITY 1,
    INDEX idx_abs_szi           (abs_szi)           TYPE minmax                 GRANULARITY 1,
    INDEX idx_funding_events    (funding_events)    TYPE minmax                 GRANULARITY 1
)
ENGINE = AggregatingMergeTree
ORDER BY (
    interval_min,
    coin,
    timestamp
)
COMMENT 'Open interest aggregated data from funding deltas';

-- Materialized view to populate state_open_interest from funding_deltas table --
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_open_interest
TO state_open_interest
AS
WITH
    -- predefined intervals --
    -- in minutes: 1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w
    [1, 5, 10, 30, 60, 240, 1440, 10080] AS intervals,

    -- determine if long or short position
    (f.szi > 0) AS is_long,
    (f.szi < 0) AS is_short

SELECT
    arrayJoin(intervals) AS interval_min,
    -- floor to the interval in seconds
    toDateTime(intDiv(toUInt32(f.timestamp), interval_min * 60) * interval_min * 60, 'UTC') AS timestamp,

    -- timestamp & block number --
    min(f.timestamp) AS min_timestamp,
    max(f.timestamp) AS max_timestamp,
    min(f.block_num) AS min_block_num,
    max(f.block_num) AS max_block_num,

    -- trading identity --
    f.coin AS coin,

    -- open interest aggregates --
    sum(f.szi)                                              AS total_szi,
    sum(abs(f.szi))                                         AS abs_szi,
    sum(if(is_long, f.szi, 0))                              AS long_szi,
    sum(if(is_short, f.szi, 0))                             AS short_szi,

    -- funding aggregates --
    sum(f.funding_amount)                                   AS total_funding,
    sum(if(f.funding_amount > 0, f.funding_amount, 0))      AS positive_funding,
    sum(if(f.funding_amount < 0, f.funding_amount, 0))      AS negative_funding,

    -- funding rate --
    avgState(f.funding_rate)                                AS avg_funding_rate,

    -- counts --
    count()                                                 AS funding_events,
    sum(if(is_long, 1, 0))                                  AS long_positions,
    sum(if(is_short, 1, 0))                                 AS short_positions,

    -- unique counts --
    uniqState(f.user)                                       AS uniq_user

FROM funding_deltas f
WHERE f.szi != 0
GROUP BY
    -- bar interval
    interval_min,
    -- trading identity
    coin,
    -- bar beginning
    timestamp;
