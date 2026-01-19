-- OHLCV state table for liquidation fills --
-- Aggregates liquidation fill data into OHLCV candlestick format for trading analytics
CREATE TABLE IF NOT EXISTS state_ohlcv_liquidation (
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

    -- mark price aggregates --
    mark_px_open            AggregateFunction(argMin, Float64, UInt64) COMMENT 'opening mark price in the window',
    mark_px_quantile        AggregateFunction(quantileDeterministic, Float64, UInt64) COMMENT 'quantile mark price in the window',
    mark_px_close           AggregateFunction(argMax, Float64, UInt64) COMMENT 'closing mark price in the window',

    -- volume --
    buy_volume              SimpleAggregateFunction(sum, Float64) COMMENT 'total buy volume in the window',
    sell_volume             SimpleAggregateFunction(sum, Float64) COMMENT 'total sell volume in the window',
    gross_volume            SimpleAggregateFunction(sum, Float64) COMMENT 'total volume (buy + sell) in the window',
    net_volume              SimpleAggregateFunction(sum, Float64) COMMENT 'net volume (buy - sell) in the window',

    -- fees --
    total_fees              SimpleAggregateFunction(sum, Float64) COMMENT 'total fees collected in the window',

    -- trade counts --
    buy_count               SimpleAggregateFunction(sum, UInt64) COMMENT 'number of buy fills in the window',
    sell_count              SimpleAggregateFunction(sum, UInt64) COMMENT 'number of sell fills in the window',
    transactions            SimpleAggregateFunction(sum, UInt64) COMMENT 'total number of fills in the window',

    -- unique counts --
    uniq_user               AggregateFunction(uniq, String) COMMENT 'unique user addresses in the window',
    uniq_liquidated_user    AggregateFunction(uniq, String) COMMENT 'unique liquidated user addresses in the window',

    -- indexes --
    INDEX idx_timestamp         (timestamp)         TYPE minmax                 GRANULARITY 1,
    INDEX idx_coin              (coin)              TYPE set(256)               GRANULARITY 1,
    INDEX idx_gross_volume      (gross_volume)      TYPE minmax                 GRANULARITY 1,
    INDEX idx_transactions      (transactions)      TYPE minmax                 GRANULARITY 1
)
ENGINE = AggregatingMergeTree
ORDER BY (
    interval_min,
    coin,
    timestamp
)
COMMENT 'OHLCV aggregated liquidation fill data for trading analytics';

-- Materialized view to populate state_ohlcv_liquidation from fills_liquidation table --
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_ohlcv_liquidation
TO state_ohlcv_liquidation
AS
WITH
    -- predefined intervals --
    -- in minutes: 1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w
    [1, 5, 10, 30, 60, 240, 1440, 10080] AS intervals,

    -- parse price and size as Float64 for calculations
    toFloat64OrZero(price) AS price_f64,
    toFloat64OrZero(size) AS size_f64,
    toFloat64OrZero(fee) AS fee_f64,

    -- determine if buy or sell
    (side = 'BUY') AS is_buy

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
    argMinState(price_f64, f.block_num)                     AS open,
    quantileDeterministicState(price_f64, f.block_num)      AS quantile,
    argMaxState(price_f64, f.block_num)                     AS close,

    -- mark price OHLC --
    argMinState(f.mark_px, f.block_num)                     AS mark_px_open,
    quantileDeterministicState(f.mark_px, f.block_num)      AS mark_px_quantile,
    argMaxState(f.mark_px, f.block_num)                     AS mark_px_close,

    -- volume --
    sum(if(is_buy, price_f64 * size_f64, 0))                AS buy_volume,
    sum(if(NOT is_buy, price_f64 * size_f64, 0))            AS sell_volume,
    sum(price_f64 * size_f64)                               AS gross_volume,
    sum(if(is_buy, price_f64 * size_f64, -(price_f64 * size_f64))) AS net_volume,

    -- fees --
    sum(fee_f64)                                            AS total_fees,

    -- trade counts --
    sum(if(is_buy, 1, 0))                                   AS buy_count,
    sum(if(NOT is_buy, 1, 0))                               AS sell_count,
    count()                                                 AS transactions,

    -- unique counts --
    uniqState(f.user)                                       AS uniq_user,
    uniqState(f.liquidated_user)                            AS uniq_liquidated_user

FROM fills_liquidation f
WHERE price_f64 > 0 AND size_f64 > 0
GROUP BY
    -- bar interval
    interval_min,
    -- trading identity
    coin,
    -- bar beginning
    timestamp;
