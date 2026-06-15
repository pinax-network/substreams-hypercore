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

    -- DEX/coin identity --
    dex                     LowCardinality(String) COMMENT 'DEX/market namespace parsed from coin (: custom, # outcome, @ spot, fallback perps)',
    coin                    LowCardinality(String) COMMENT 'Trading pair/coin symbol',

    -- OHLC price aggregates --
    open                    AggregateFunction(argMin, Float64, UInt64) COMMENT 'opening price in the window',
    quantile                AggregateFunction(quantileDeterministic, Float64, UInt64) COMMENT 'quantile price in the window (use 0.95 for high, 0.05 for low)',
    close                   AggregateFunction(argMax, Float64, UInt64) COMMENT 'closing price in the window',

    -- volume by side (each side equals true total — every match emits one BID-side and one ASK-side row) --
    side_buy_volume         SimpleAggregateFunction(sum, Float64) COMMENT 'bid-side fill notional (equals total window volume)',
    side_ask_volume         SimpleAggregateFunction(sum, Float64) COMMENT 'ask-side fill notional (equals total window volume)',

    -- volume by aggressor (taker) — directional pressure signal --
    taker_buy_volume        SimpleAggregateFunction(sum, Float64) COMMENT 'aggressor BUY notional (crossed taker hit the ask)',
    taker_sell_volume       SimpleAggregateFunction(sum, Float64) COMMENT 'aggressor SELL notional (crossed taker hit the bid)',

    -- volume by perp direction --
    open_long_volume        SimpleAggregateFunction(sum, Float64) COMMENT 'total open long volume in the window',
    close_long_volume       SimpleAggregateFunction(sum, Float64) COMMENT 'total close long volume in the window',
    open_short_volume       SimpleAggregateFunction(sum, Float64) COMMENT 'total open short volume in the window',
    close_short_volume      SimpleAggregateFunction(sum, Float64) COMMENT 'total close short volume in the window',

    -- fees --
    total_fees              SimpleAggregateFunction(sum, Float64) COMMENT 'total fees collected in the window',

    -- trade counts --
    transactions            SimpleAggregateFunction(sum, UInt64) COMMENT 'true match count in the window (one row per taker)',

    -- distinct user counts live in state_ohlcv_fills_uniq_user (refresh MV)

    -- indexes --
    INDEX idx_timestamp         (timestamp)         TYPE minmax                 GRANULARITY 1,
    INDEX idx_dex               (dex)               TYPE set(12)                GRANULARITY 1,
    INDEX idx_coin              (coin)              TYPE set(256)               GRANULARITY 1,
    INDEX idx_transactions      (transactions)      TYPE minmax                 GRANULARITY 1
)
ENGINE = AggregatingMergeTree
ORDER BY (
    interval_min,
    dex,
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

    -- determine side --
    (side IN ('BUY', 'BID')) AS is_side_bid,

    -- perp position transitions --
    (direction = 'OPEN_LONG') AS is_open_long,
    (direction = 'CLOSE_LONG') AS is_close_long,
    (direction = 'OPEN_SHORT') AS is_open_short,
    (direction = 'CLOSE_SHORT') AS is_close_short

SELECT
    arrayJoin(intervals) AS interval_min,
    -- floor to the interval in seconds
    toDateTime(intDiv(toUInt32(f.fill_time), interval_min * 60) * interval_min * 60, 'UTC') AS timestamp,

    -- timestamp & block number --
    min(f.fill_time) AS min_timestamp,
    max(f.fill_time) AS max_timestamp,
    min(f.block_num) AS min_block_num,
    max(f.block_num) AS max_block_num,

    -- DEX/coin identity --
    f.dex AS dex,
    f.coin AS coin,

    -- OHLC --
    argMinState(f.price, f.block_num)                       AS open,
    quantileDeterministicState(f.price, f.block_num)        AS quantile,
    argMaxState(f.price, f.block_num)                       AS close,

    -- volume by side (each side = true total: every match emits one BID + one ASK row) --
    sum(if(is_side_bid, f.price * f.size, 0))               AS side_buy_volume,
    sum(if(NOT is_side_bid, f.price * f.size, 0))           AS side_ask_volume,

    -- aggressor flow (only the crossed taker contributes, no double-emission) --
    sum(if(f.crossed AND is_side_bid, f.price * f.size, 0))     AS taker_buy_volume,
    sum(if(f.crossed AND NOT is_side_bid, f.price * f.size, 0)) AS taker_sell_volume,

    -- volume by perp direction --
    sum(if(is_open_long, f.price * f.size, 0))              AS open_long_volume,
    sum(if(is_close_long, f.price * f.size, 0))             AS close_long_volume,
    sum(if(is_open_short, f.price * f.size, 0))             AS open_short_volume,
    sum(if(is_close_short, f.price * f.size, 0))            AS close_short_volume,

    -- fees --
    sum(f.fee)                                              AS total_fees,

    -- true match count: count only the crossed taker side --
    sum(if(f.crossed, 1, 0))                                AS transactions

FROM fills f
WHERE f.price > 0 AND f.size > 0
  AND f.direction NOT LIKE 'LIQUIDATED_%'
  AND f.direction NOT IN (
      'AUTO_DELEVERAGING', 'NET_CHILD_VAULTS', 'SPOT_DUST_CONVERSION',
      'SETTLEMENT',
      'SPLIT_OUTCOME', 'MERGE_OUTCOME', 'MERGE_QUESTION', 'NEGATE_OUTCOME'
  )
GROUP BY
    -- bar interval
    interval_min,
    -- DEX/coin identity
    dex,
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

    -- determine side --
    (side IN ('BUY', 'BID')) AS is_side_bid,

    -- perp position transitions --
    (direction = 'OPEN_LONG') AS is_open_long,
    (direction = 'CLOSE_LONG') AS is_close_long,
    (direction = 'OPEN_SHORT') AS is_open_short,
    (direction = 'CLOSE_SHORT') AS is_close_short

SELECT
    arrayJoin(intervals) AS interval_min,
    -- floor to the interval in seconds
    toDateTime(intDiv(toUInt32(f.fill_time), interval_min * 60) * interval_min * 60, 'UTC') AS timestamp,

    -- timestamp & block number --
    min(f.fill_time) AS min_timestamp,
    max(f.fill_time) AS max_timestamp,
    min(f.block_num) AS min_block_num,
    max(f.block_num) AS max_block_num,

    -- DEX/coin identity --
    f.dex AS dex,
    f.coin AS coin,

    -- OHLC --
    argMinState(f.price, f.block_num)                       AS open,
    quantileDeterministicState(f.price, f.block_num)        AS quantile,
    argMaxState(f.price, f.block_num)                       AS close,

    -- volume by side --
    sum(if(is_side_bid, f.price * f.size, 0))               AS side_buy_volume,
    sum(if(NOT is_side_bid, f.price * f.size, 0))           AS side_ask_volume,

    -- aggressor flow --
    sum(if(f.crossed AND is_side_bid, f.price * f.size, 0))     AS taker_buy_volume,
    sum(if(f.crossed AND NOT is_side_bid, f.price * f.size, 0)) AS taker_sell_volume,

    -- volume by perp direction --
    sum(if(is_open_long, f.price * f.size, 0))              AS open_long_volume,
    sum(if(is_close_long, f.price * f.size, 0))             AS close_long_volume,
    sum(if(is_open_short, f.price * f.size, 0))             AS open_short_volume,
    sum(if(is_close_short, f.price * f.size, 0))            AS close_short_volume,

    -- fees --
    sum(f.fee)                                              AS total_fees,

    -- true match count --
    sum(if(f.crossed, 1, 0))                                AS transactions

FROM fills_liquidation f
WHERE f.price > 0 AND f.size > 0
  AND f.direction NOT LIKE 'LIQUIDATED_%'
  AND f.direction NOT IN (
      'AUTO_DELEVERAGING', 'NET_CHILD_VAULTS', 'SPOT_DUST_CONVERSION',
      'SETTLEMENT',
      'SPLIT_OUTCOME', 'MERGE_OUTCOME', 'MERGE_QUESTION', 'NEGATE_OUTCOME'
  )
GROUP BY
    -- bar interval
    interval_min,
    -- DEX/coin identity
    dex,
    coin,
    -- bar beginning
    timestamp;
