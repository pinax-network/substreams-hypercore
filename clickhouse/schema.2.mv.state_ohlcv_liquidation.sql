-- OHLCV state table for liquidation fills --
-- Aggregates the liquidated-user side of each liquidation trade into
-- OHLCV candlestick format for trading analytics. The upstream
-- `fills_liquidation` table also stores counterparty rows where
-- `user != liquidated_user`; those are excluded here to avoid
-- double-counting trade volume and to match the semantics of the
-- `/v1/hyperliquid/markets/liquidations` events endpoint.
CREATE TABLE IF NOT EXISTS state_ohlcv_liquidation (
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

    -- mark price aggregates --
    mark_px_open            AggregateFunction(argMin, Float64, UInt64) COMMENT 'opening mark price in the window',
    mark_px_quantile        AggregateFunction(quantileDeterministic, Float64, UInt64) COMMENT 'quantile mark price in the window',
    mark_px_close           AggregateFunction(argMax, Float64, UInt64) COMMENT 'closing mark price in the window',

    -- volume by side --
    side_buy_volume         SimpleAggregateFunction(sum, Float64) COMMENT 'total bid-side volume in the window',
    side_ask_volume         SimpleAggregateFunction(sum, Float64) COMMENT 'total ask side volume in the window',

    -- volume by direction --
    direction_buy_volume    SimpleAggregateFunction(sum, Float64) COMMENT 'total direction=BUY volume in the window',
    direction_sell_volume   SimpleAggregateFunction(sum, Float64) COMMENT 'total direction=SELL volume in the window',
    open_long_volume        SimpleAggregateFunction(sum, Float64) COMMENT 'total open long volume in the window',
    close_long_volume       SimpleAggregateFunction(sum, Float64) COMMENT 'total close long volume in the window',
    open_short_volume       SimpleAggregateFunction(sum, Float64) COMMENT 'total open short volume in the window',
    close_short_volume      SimpleAggregateFunction(sum, Float64) COMMENT 'total close short volume in the window',

    -- fees --
    total_fees              SimpleAggregateFunction(sum, Float64) COMMENT 'total fees collected in the window',

    -- trade counts --
    buy_count               SimpleAggregateFunction(sum, UInt64) COMMENT 'number of bid-side fills in the window',
    sell_count              SimpleAggregateFunction(sum, UInt64) COMMENT 'number of sell fills in the window',
    transactions            SimpleAggregateFunction(sum, UInt64) COMMENT 'total number of fills in the window',

    -- distinct user counts (uniq_user, uniq_liquidated_user) live in
    -- state_ohlcv_liquidation_uniq_user (refresh MV)

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
COMMENT 'OHLCV aggregated liquidation fill data for trading analytics';

-- Materialized view to populate state_ohlcv_liquidation from fills_liquidation table --
-- Filters to the liquidated user's side of each liquidation trade
-- (`user = liquidated_user`). Hyperliquid emits regular `Close Long` /
-- `Close Short` direction tags on most liquidated-user fills (the
-- liquidation signal lives in the separate `liquidation` sub-object on
-- the wire, which the substream uses to gate fills_liquidation membership).
-- The `LIQUIDATED_*` direction variants are real but represent rare edge
-- cases (backstop interventions, ADL, borrow liquidations) — they are
-- caught by the same predicate because their fills also have
-- `user = liquidated_user`. The `fills_liquidation` table also stores
-- counterparty rows where `user != liquidated_user`; those are excluded
-- here to avoid double-counting trade volume.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_ohlcv_liquidation
TO state_ohlcv_liquidation
AS
WITH
    -- predefined intervals --
    -- in minutes: 1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w
    [1, 5, 10, 30, 60, 240, 1440, 10080] AS intervals,

    -- determine side --
    (side IN ('BUY', 'BID')) AS is_side_bid,

    -- determine direction --
    (direction = 'BUY') AS is_direction_buy,
    (direction = 'SELL') AS is_direction_sell,
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

    -- mark price OHLC --
    argMinState(f.mark_px, f.block_num)                     AS mark_px_open,
    quantileDeterministicState(f.mark_px, f.block_num)      AS mark_px_quantile,
    argMaxState(f.mark_px, f.block_num)                     AS mark_px_close,

    -- volume by side --
    sum(if(is_side_bid, f.price * f.size, 0))               AS side_buy_volume,
    sum(if(NOT is_side_bid, f.price * f.size, 0))           AS side_ask_volume,

    -- volume by direction --
    sum(if(is_direction_buy, f.price * f.size, 0))          AS direction_buy_volume,
    sum(if(is_direction_sell, f.price * f.size, 0))         AS direction_sell_volume,
    sum(if(is_open_long, f.price * f.size, 0))              AS open_long_volume,
    sum(if(is_close_long, f.price * f.size, 0))             AS close_long_volume,
    sum(if(is_open_short, f.price * f.size, 0))             AS open_short_volume,
    sum(if(is_close_short, f.price * f.size, 0))            AS close_short_volume,

    -- fees --
    sum(f.fee)                                              AS total_fees,

    -- trade counts --
    sum(if(is_side_bid, 1, 0))                              AS buy_count,
    sum(if(NOT is_side_bid, 1, 0))                          AS sell_count,
    count()                                                 AS transactions

FROM fills_liquidation f
WHERE f.price > 0 AND f.size > 0
  AND f.user = f.liquidated_user
GROUP BY
    -- bar interval
    interval_min,
    -- DEX/coin identity
    dex,
    coin,
    -- bar beginning
    timestamp;
