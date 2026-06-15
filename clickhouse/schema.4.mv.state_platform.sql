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
    total_volume            SimpleAggregateFunction(sum, Float64) COMMENT 'total fill volume across all coins',
    taker_buy_volume        SimpleAggregateFunction(sum, Float64) COMMENT 'aggressor BUY notional across all coins',
    taker_sell_volume       SimpleAggregateFunction(sum, Float64) COMMENT 'aggressor SELL notional across all coins',

    -- fills count --
    transactions            SimpleAggregateFunction(sum, UInt64) COMMENT 'true match count across all coins',

    -- fills fees --
    total_fees              SimpleAggregateFunction(sum, Float64) COMMENT 'total fees across all coins',

    -- distinct coins active in the window --
    -- HLL state. Reading via uniqMerge is slower than a plain uniqExact(coin) over
    -- the small top-N timestamp slice in state_ohlcv_fills, so the API typically
    -- ignores this column and recomputes active_coins from the source. Kept here
    -- because it is essentially free at insert time and useful for ad-hoc queries.
    active_coins            AggregateFunction(uniq, String) COMMENT 'HLL of coins with at least one fill or liquidation in the window',

    -- liquidations slice --
    liq_total_volume        SimpleAggregateFunction(sum, Float64) COMMENT 'total liquidation fill volume across all coins',
    liq_taker_buy_volume    SimpleAggregateFunction(sum, Float64) COMMENT 'aggressor BUY liquidation notional (forced buys, closing shorts)',
    liq_taker_sell_volume   SimpleAggregateFunction(sum, Float64) COMMENT 'aggressor SELL liquidation notional (forced sells, closing longs)',
    liq_transactions        SimpleAggregateFunction(sum, UInt64) COMMENT 'total liquidation events across all coins'
)
ENGINE = AggregatingMergeTree
ORDER BY (interval_min, timestamp);

-- MV: state_ohlcv_fills -> state_platform --
-- Each insert into state_ohlcv_fills (one row per coin/interval/bucket) is collapsed
-- across coins to produce one platform row per (interval_min, timestamp).
-- `side_buy_volume` from the source already equals true total volume (each match's
-- buyer + seller perspectives both record the full match), so it's the cleanest
-- one-sided source for `total_volume`.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_platform_fills
TO state_platform
AS
SELECT
    timestamp,
    interval_min,
    sum(side_buy_volume)                             AS total_volume,
    sum(taker_buy_volume)                            AS taker_buy_volume,
    sum(taker_sell_volume)                           AS taker_sell_volume,
    sum(transactions)                                AS transactions,
    sum(total_fees)                                  AS total_fees,
    uniqState(coin)                                  AS active_coins,
    toFloat64(0)                                     AS liq_total_volume,
    toFloat64(0)                                     AS liq_taker_buy_volume,
    toFloat64(0)                                     AS liq_taker_sell_volume,
    toUInt64(0)                                      AS liq_transactions
FROM state_ohlcv_fills
GROUP BY interval_min, timestamp;

-- MV: state_ohlcv_liquidation -> state_platform --
-- Same pattern but populates the liquidation slice. Fills slice is zero-filled.
-- Liquidation events also count toward `active_coins` — the HLL state from this
-- MV merges with the fills MV's contribution.
-- Liquidation MV is already single-perspective (user = liquidated_user), so
-- side_buy_volume + side_ask_volume is the true total liquidation volume.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_platform_liquidation
TO state_platform
AS
SELECT
    timestamp,
    interval_min,
    toFloat64(0)                                                 AS total_volume,
    toFloat64(0)                                                 AS taker_buy_volume,
    toFloat64(0)                                                 AS taker_sell_volume,
    toUInt64(0)                                                  AS transactions,
    toFloat64(0)                                                 AS total_fees,
    uniqState(coin)                                              AS active_coins,
    sum(state_ohlcv_liquidation.side_buy_volume
      + state_ohlcv_liquidation.side_ask_volume)                 AS liq_total_volume,
    sum(state_ohlcv_liquidation.taker_buy_volume)                AS liq_taker_buy_volume,
    sum(state_ohlcv_liquidation.taker_sell_volume)               AS liq_taker_sell_volume,
    sum(state_ohlcv_liquidation.transactions)                    AS liq_transactions
FROM state_ohlcv_liquidation
GROUP BY interval_min, timestamp;

-- MV: state_ohlcv_outcomes -> state_platform --
-- Outcome volume is probability-denominated `size × price` against USDC
-- collateral, so it adds cleanly into the platform-wide USD-equivalent total.
-- Liquidation slice stays zero (outcomes are fully collateralized — no
-- liquidations). Outcomes' side_buy + side_ask are NOT equal because some
-- matches are single-perspective (e.g. against system accounts), so sum both
-- sides for the total.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_platform_outcomes
TO state_platform
AS
SELECT
    timestamp,
    interval_min,
    sum(side_buy_volume + side_ask_volume)           AS total_volume,
    sum(taker_buy_volume)                            AS taker_buy_volume,
    sum(taker_sell_volume)                           AS taker_sell_volume,
    sum(transactions)                                AS transactions,
    sum(total_fees)                                  AS total_fees,
    uniqState(coin)                                  AS active_coins,
    toFloat64(0)                                     AS liq_total_volume,
    toFloat64(0)                                     AS liq_taker_buy_volume,
    toFloat64(0)                                     AS liq_taker_sell_volume,
    toUInt64(0)                                      AS liq_transactions
FROM state_ohlcv_outcomes
GROUP BY interval_min, timestamp;
