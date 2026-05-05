-- Funding snapshot observation state table --
-- Aggregates funding delta snapshot observations by dex/coin and is not a current-position state table
CREATE TABLE IF NOT EXISTS state_open_interest (
    -- bar interval --
    timestamp               DateTime('UTC') COMMENT 'beginning of the bar',
    interval_min            UInt16 DEFAULT 1 COMMENT 'bar interval in minutes (1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w)',

    -- timestamp & block number --
    min_timestamp           SimpleAggregateFunction(min, DateTime('UTC')) COMMENT 'first timestamp seen',
    max_timestamp           SimpleAggregateFunction(max, DateTime('UTC')) COMMENT 'last timestamp seen',
    min_block_num           SimpleAggregateFunction(min, UInt64) COMMENT 'first block number seen',
    max_block_num           SimpleAggregateFunction(max, UInt64) COMMENT 'last block number seen',

    -- DEX/coin identity --
    dex                     LowCardinality(String) COMMENT 'DEX/market namespace parsed from coin (: custom, # outcome, @ spot, fallback perps)',
    coin                    LowCardinality(String) COMMENT 'Trading pair/coin symbol',

    -- funding snapshot observation aggregates --
    sum_szi_observations            SimpleAggregateFunction(sum, Float64) COMMENT 'sum of signed szi observations seen in the window',
    sum_abs_szi_observations        SimpleAggregateFunction(sum, Float64) COMMENT 'sum of absolute szi observations seen in the window',
    sum_long_szi_observations       SimpleAggregateFunction(sum, Float64) COMMENT 'sum of positive szi observations seen in the window',
    sum_short_szi_observations      SimpleAggregateFunction(sum, Float64) COMMENT 'sum of negative szi observations seen in the window',

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

    -- distinct user counts live in state_open_interest_uniq_user (refresh MV)

    -- indexes --
    INDEX idx_timestamp         (timestamp)         TYPE minmax                 GRANULARITY 1,
    INDEX idx_dex               (dex)               TYPE set(12)                GRANULARITY 1,
    INDEX idx_coin              (coin)              TYPE set(256)               GRANULARITY 1,
    INDEX idx_sum_abs_szi_observations (sum_abs_szi_observations) TYPE minmax GRANULARITY 1,
    INDEX idx_funding_events    (funding_events)    TYPE minmax                 GRANULARITY 1
)
ENGINE = AggregatingMergeTree
ORDER BY (
    interval_min,
    dex,
    coin,
    timestamp
)
COMMENT 'Funding delta snapshot observations aggregated by dex and coin';

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

    -- DEX/coin identity --
    f.dex AS dex,
    f.coin AS coin,

    -- funding snapshot observation aggregates --
    sum(f.szi)                                              AS sum_szi_observations,
    sum(abs(f.szi))                                         AS sum_abs_szi_observations,
    sum(if(is_long, f.szi, 0))                              AS sum_long_szi_observations,
    sum(if(is_short, f.szi, 0))                             AS sum_short_szi_observations,

    -- funding aggregates --
    sum(f.funding_amount)                                   AS total_funding,
    sum(if(f.funding_amount > 0, f.funding_amount, 0))      AS positive_funding,
    sum(if(f.funding_amount < 0, f.funding_amount, 0))      AS negative_funding,

    -- funding rate --
    avgState(f.funding_rate)                                AS avg_funding_rate,

    -- counts --
    count()                                                 AS funding_events,
    sum(if(is_long, 1, 0))                                  AS long_positions,
    sum(if(is_short, 1, 0))                                 AS short_positions

FROM funding_deltas f
WHERE f.szi != 0
GROUP BY
    -- bar interval
    interval_min,
    -- DEX/coin identity
    dex,
    coin,
    -- bar beginning
    timestamp;
