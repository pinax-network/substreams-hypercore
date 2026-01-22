-- OHLCV state table for fills --
-- Aggregates fill data into OHLCV candlestick format for trading analytics
CREATE TABLE IF NOT EXISTS state_ohlcv_fills (
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

    -- OHLC price aggregates --
    open                    AggregateFunction(argMin, Float64, UInt64) COMMENT 'opening price in the window',
    quantile                AggregateFunction(quantileDeterministic, Float64, UInt64) COMMENT 'quantile price in the window (use 0.95 for high, 0.05 for low)',
    close                   AggregateFunction(argMax, Float64, UInt64) COMMENT 'closing price in the window',

    -- volume by side --
    buy_volume              SimpleAggregateFunction(sum, Float64) COMMENT 'total buy side volume in the window',
    ask_volume              SimpleAggregateFunction(sum, Float64) COMMENT 'total ask side volume in the window',

    -- volume by direction --
    open_long_volume        SimpleAggregateFunction(sum, Float64) COMMENT 'total open long volume in the window',
    close_long_volume       SimpleAggregateFunction(sum, Float64) COMMENT 'total close long volume in the window',
    open_short_volume       SimpleAggregateFunction(sum, Float64) COMMENT 'total open short volume in the window',
    close_short_volume      SimpleAggregateFunction(sum, Float64) COMMENT 'total close short volume in the window',

    -- fees --
    total_fees              SimpleAggregateFunction(sum, Float64) COMMENT 'total fees collected in the window',

    -- trade counts --
    buy_count               SimpleAggregateFunction(sum, UInt64) COMMENT 'number of buy fills in the window',
    sell_count              SimpleAggregateFunction(sum, UInt64) COMMENT 'number of sell fills in the window',
    transactions            SimpleAggregateFunction(sum, UInt64) COMMENT 'total number of fills in the window',

    -- unique counts --
    uniq_user               AggregateFunction(uniq, String) COMMENT 'unique user addresses in the window',

    -- indexes --
    INDEX idx_timestamp         (timestamp)         TYPE minmax                 GRANULARITY 1,
    INDEX idx_coin              (coin)              TYPE set(256)               GRANULARITY 1,
    INDEX idx_transactions      (transactions)      TYPE minmax                 GRANULARITY 1
)
ENGINE = AggregatingMergeTree
ORDER BY (
    interval_min,
    coin,
    timestamp
)
COMMENT 'OHLCV aggregated fill data for trading analytics';

-- Materialized view to populate state_ohlcv_fills from fills table --
-- Filter by client_order_id != '' to only count initiating orders (not counterparties)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_ohlcv_fills
TO state_ohlcv_fills
AS
WITH
    -- predefined intervals --
    -- in minutes: 1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w
    [1, 5, 10, 30, 60, 240, 1440, 10080] AS intervals,

    -- determine side and direction
    (side = 'BUY') AS is_buy,
    (direction = 'OPEN_LONG') AS is_open_long,
    (direction = 'CLOSE_LONG') AS is_close_long,
    (direction = 'OPEN_SHORT') AS is_open_short,
    (direction = 'CLOSE_SHORT') AS is_close_short

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

    -- OHLC --
    argMinState(f.price, f.block_num)                       AS open,
    quantileDeterministicState(f.price, f.block_num)        AS quantile,
    argMaxState(f.price, f.block_num)                       AS close,

    -- volume by side --
    sum(if(is_buy, f.price * f.size, 0))                    AS buy_volume,
    sum(if(NOT is_buy, f.price * f.size, 0))                AS ask_volume,

    -- volume by direction --
    sum(if(is_open_long, f.price * f.size, 0))              AS open_long_volume,
    sum(if(is_close_long, f.price * f.size, 0))             AS close_long_volume,
    sum(if(is_open_short, f.price * f.size, 0))             AS open_short_volume,
    sum(if(is_close_short, f.price * f.size, 0))            AS close_short_volume,

    -- fees --
    sum(f.fee)                                              AS total_fees,

    -- trade counts --
    sum(if(is_buy, 1, 0))                                   AS buy_count,
    sum(if(NOT is_buy, 1, 0))                               AS sell_count,
    count()                                                 AS transactions,

    -- unique counts --
    uniqState(f.user)                                       AS uniq_user

FROM fills f
WHERE f.price > 0 AND f.size > 0 AND f.client_order_id != ''
GROUP BY
    -- bar interval
    interval_min,
    -- trading identity
    coin,
    -- bar beginning
    timestamp;

-- Materialized view to populate state_ohlcv_fills from fills_liquidation table --
-- This ensures liquidation fills are also included in the OHLCV price aggregation
-- Filter by client_order_id != '' to only count initiating orders (not counterparties)
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_ohlcv_fills_liquidation
TO state_ohlcv_fills
AS
WITH
    -- predefined intervals --
    -- in minutes: 1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w
    [1, 5, 10, 30, 60, 240, 1440, 10080] AS intervals,

    -- determine side and direction
    (side = 'BUY') AS is_buy,
    (direction = 'OPEN_LONG') AS is_open_long,
    (direction = 'CLOSE_LONG') AS is_close_long,
    (direction = 'OPEN_SHORT') AS is_open_short,
    (direction = 'CLOSE_SHORT') AS is_close_short

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

    -- OHLC --
    argMinState(f.price, f.block_num)                       AS open,
    quantileDeterministicState(f.price, f.block_num)        AS quantile,
    argMaxState(f.price, f.block_num)                       AS close,

    -- volume by side --
    sum(if(is_buy, f.price * f.size, 0))                    AS buy_volume,
    sum(if(NOT is_buy, f.price * f.size, 0))                AS ask_volume,

    -- volume by direction --
    sum(if(is_open_long, f.price * f.size, 0))              AS open_long_volume,
    sum(if(is_close_long, f.price * f.size, 0))             AS close_long_volume,
    sum(if(is_open_short, f.price * f.size, 0))             AS open_short_volume,
    sum(if(is_close_short, f.price * f.size, 0))            AS close_short_volume,

    -- fees --
    sum(f.fee)                                              AS total_fees,

    -- trade counts --
    sum(if(is_buy, 1, 0))                                   AS buy_count,
    sum(if(NOT is_buy, 1, 0))                               AS sell_count,
    count()                                                 AS transactions,

    -- unique counts --
    uniqState(f.user)                                       AS uniq_user

FROM fills_liquidation f
WHERE f.price > 0 AND f.size > 0 AND f.client_order_id != ''
GROUP BY
    -- bar interval
    interval_min,
    -- trading identity
    coin,
    -- bar beginning
    timestamp;
