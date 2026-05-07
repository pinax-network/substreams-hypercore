-- Platform-wide aggregation table --
-- Pre-aggregates fills + liquidation totals across all coins per (interval_min, timestamp).
-- Powers the Token API /platform endpoint. Replaces the per-query GROUP BY across
-- coins on state_ohlcv_fills / state_ohlcv_liquidation, dropping the platform 1m
-- query from ~1s to a few hundred ms when paired with a top-N timestamp pre-filter
-- on the API side.
CREATE TABLE IF NOT EXISTS state_platform (
    -- bar interval --
    timestamp               DateTime('UTC') COMMENT 'beginning of the bar',
    interval_min            UInt16 COMMENT 'bar interval in minutes (1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w)',

    -- fills volume --
    side_buy_volume         SimpleAggregateFunction(sum, Float64) COMMENT 'total bid-side fill volume across all coins',
    side_ask_volume         SimpleAggregateFunction(sum, Float64) COMMENT 'total ask-side fill volume across all coins',

    -- fills counts --
    buys                    SimpleAggregateFunction(sum, UInt64) COMMENT 'bid-side fills across all coins',
    sells                   SimpleAggregateFunction(sum, UInt64) COMMENT 'ask-side fills across all coins',
    transactions            SimpleAggregateFunction(sum, UInt64) COMMENT 'total fills across all coins',

    -- fills fees --
    total_fees              SimpleAggregateFunction(sum, Float64) COMMENT 'total fees across all coins',

    -- distinct coins active in the window --
    -- HLL state. Reading via uniqMerge is slower than a plain uniqExact(coin) over
    -- the small top-N timestamp slice in state_ohlcv_fills, so the API typically
    -- ignores this column and recomputes active_coins from the source. Kept here
    -- because it is essentially free at insert time and useful for ad-hoc queries.
    active_coins            AggregateFunction(uniq, String) COMMENT 'HLL of coins with at least one fill or liquidation in the window',

    -- liquidations slice --
    liq_side_buy_volume     SimpleAggregateFunction(sum, Float64) COMMENT 'total bid-side liquidation fill volume across all coins',
    liq_side_ask_volume     SimpleAggregateFunction(sum, Float64) COMMENT 'total ask-side liquidation fill volume across all coins',
    liq_transactions        SimpleAggregateFunction(sum, UInt64) COMMENT 'total liquidation fills across all coins'
)
ENGINE = AggregatingMergeTree
ORDER BY (interval_min, timestamp);

-- MV: state_ohlcv_fills -> state_platform --
-- Each insert into state_ohlcv_fills (one row per coin/interval/bucket) is collapsed
-- across coins to produce one platform row per (interval_min, timestamp).
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_platform_fills
TO state_platform
AS
SELECT
    timestamp,
    interval_min,
    sum(side_buy_volume)     AS side_buy_volume,
    sum(side_ask_volume)     AS side_ask_volume,
    sum(buy_count)           AS buys,
    sum(sell_count)          AS sells,
    sum(transactions)        AS transactions,
    sum(total_fees)          AS total_fees,
    uniqState(coin)          AS active_coins,
    toFloat64(0)             AS liq_side_buy_volume,
    toFloat64(0)             AS liq_side_ask_volume,
    toUInt64(0)              AS liq_transactions
FROM state_ohlcv_fills
GROUP BY interval_min, timestamp;

-- MV: state_ohlcv_liquidation -> state_platform --
-- Same pattern but populates the liquidation slice. Fills slice is zero-filled.
-- Liquidation events also count toward `active_coins` — the HLL state from this
-- MV merges with the fills MV's contribution.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_platform_liquidation
TO state_platform
AS
SELECT
    timestamp,
    interval_min,
    toFloat64(0)                                     AS side_buy_volume,
    toFloat64(0)                                     AS side_ask_volume,
    toUInt64(0)                                      AS buys,
    toUInt64(0)                                      AS sells,
    toUInt64(0)                                      AS transactions,
    toFloat64(0)                                     AS total_fees,
    uniqState(coin)                                  AS active_coins,
    -- Qualify source columns to avoid alias shadowing: the aliased
    -- `side_buy_volume = 0` / `side_ask_volume = 0` / `transactions = 0`
    -- above would otherwise resolve here, zeroing the sums.
    sum(state_ohlcv_liquidation.side_buy_volume)     AS liq_side_buy_volume,
    sum(state_ohlcv_liquidation.side_ask_volume)     AS liq_side_ask_volume,
    sum(state_ohlcv_liquidation.transactions)        AS liq_transactions
FROM state_ohlcv_liquidation
GROUP BY interval_min, timestamp;
