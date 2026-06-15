-- OHLCV bars for outcome markets. Excludes composition and settlement
-- directions so price candles reflect only real market trades. Composition
-- rows (SPLIT_OUTCOME, MERGE_OUTCOME, MERGE_QUESTION, NEGATE_OUTCOME) and
-- payouts (SETTLEMENT) remain queryable on the raw `outcome_fills` table.
CREATE TABLE IF NOT EXISTS state_ohlcv_outcomes (
    timestamp               DateTime('UTC') COMMENT 'beginning of the bar',
    interval_min            UInt16 DEFAULT 1 COMMENT 'bar interval in minutes (1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w)',

    min_timestamp           SimpleAggregateFunction(min, DateTime('UTC')),
    max_timestamp           SimpleAggregateFunction(max, DateTime('UTC')),
    min_block_num           SimpleAggregateFunction(min, UInt64),
    max_block_num           SimpleAggregateFunction(max, UInt64),

    coin                    LowCardinality(String) COMMENT 'Outcome coin (#<outcome_id*10+side>)',

    open                    AggregateFunction(argMin, Float64, UInt64),
    quantile                AggregateFunction(quantileDeterministic, Float64, UInt64) COMMENT 'use 0.95 for high, 0.05 for low',
    close                   AggregateFunction(argMax, Float64, UInt64),

    side_buy_volume         SimpleAggregateFunction(sum, Float64) COMMENT 'total bid-side volume in the window',
    side_ask_volume         SimpleAggregateFunction(sum, Float64) COMMENT 'total ask-side volume in the window',

    taker_buy_volume        SimpleAggregateFunction(sum, Float64) COMMENT 'aggressor BUY notional (crossed taker hit the ask)',
    taker_sell_volume       SimpleAggregateFunction(sum, Float64) COMMENT 'aggressor SELL notional (crossed taker hit the bid)',

    total_fees              SimpleAggregateFunction(sum, Float64),

    transactions            SimpleAggregateFunction(sum, UInt64) COMMENT 'true match count in the window (one row per taker)',

    INDEX idx_timestamp         (timestamp)         TYPE minmax    GRANULARITY 1,
    INDEX idx_coin              (coin)              TYPE set(256)  GRANULARITY 1,
    INDEX idx_transactions      (transactions)      TYPE minmax    GRANULARITY 1
)
ENGINE = AggregatingMergeTree
ORDER BY (
    interval_min,
    coin,
    timestamp
)
COMMENT 'OHLCV bars per outcome coin';

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_ohlcv_outcomes
TO state_ohlcv_outcomes
AS
WITH
    [1, 5, 10, 30, 60, 240, 1440, 10080] AS intervals,
    (side = 'BID') AS is_side_bid

SELECT
    arrayJoin(intervals) AS interval_min,
    toDateTime(intDiv(toUInt32(f.fill_time), interval_min * 60) * interval_min * 60, 'UTC') AS timestamp,

    min(f.fill_time) AS min_timestamp,
    max(f.fill_time) AS max_timestamp,
    min(f.block_num) AS min_block_num,
    max(f.block_num) AS max_block_num,

    f.coin AS coin,

    argMinState(f.price, f.block_num)                       AS open,
    quantileDeterministicState(f.price, f.block_num)        AS quantile,
    argMaxState(f.price, f.block_num)                       AS close,

    sum(if(is_side_bid, f.price * f.size, 0))               AS side_buy_volume,
    sum(if(NOT is_side_bid, f.price * f.size, 0))           AS side_ask_volume,

    sum(if(f.crossed AND is_side_bid, f.price * f.size, 0))     AS taker_buy_volume,
    sum(if(f.crossed AND NOT is_side_bid, f.price * f.size, 0)) AS taker_sell_volume,

    sum(f.fee)                                              AS total_fees,

    sum(if(f.crossed, 1, 0))                                AS transactions

FROM outcome_fills f
WHERE f.price > 0 AND f.size > 0
  AND f.direction IN ('BUY', 'SELL')
GROUP BY
    interval_min,
    coin,
    timestamp;
