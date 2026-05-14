-- Per-bucket distinct user counts for OHLCV liquidations --
-- Replaces both AggregateFunction(uniq, String) state columns
-- (uniq_user + uniq_liquidated_user) on state_ohlcv_liquidation.
-- See `state_open_interest_uniq_user.sql` for the rationale and TTL caveat.

CREATE TABLE IF NOT EXISTS state_ohlcv_liquidation_uniq_user (
    refresh_time             DateTime('UTC'),
    interval_min             UInt16 COMMENT 'bar interval in minutes (1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w)',
    dex                      LowCardinality(String) COMMENT 'DEX/market namespace parsed from coin (: custom, # outcome, @ spot, fallback perps)',
    coin                     LowCardinality(String) COMMENT 'Trading pair/coin symbol',
    timestamp                DateTime('UTC') COMMENT 'beginning of the bar',
    uniq_user                UInt64 COMMENT 'distinct liquidator addresses in the window',
    uniq_liquidated_user     UInt64 COMMENT 'distinct liquidated addresses in the window'
) ENGINE = ReplacingMergeTree(refresh_time)
ORDER BY (interval_min, dex, coin, timestamp)
TTL refresh_time + INTERVAL 3 HOUR;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_refresh_state_ohlcv_liquidation_uniq_user
REFRESH EVERY 1 HOUR OFFSET 55 MINUTE APPEND
TO state_ohlcv_liquidation_uniq_user
AS
SELECT
    now() AS refresh_time,
    arrayJoin([1, 5, 10, 30, 60, 240, 1440, 10080]) AS interval_min,
    dex, coin,
    toDateTime(intDiv(toUInt32(fill_time), interval_min * 60) * interval_min * 60, 'UTC') AS timestamp,
    uniqExact(user) AS uniq_user,
    uniqExact(liquidated_user) AS uniq_liquidated_user
FROM fills_liquidation
WHERE price > 0 AND size > 0
  AND user = liquidated_user
GROUP BY interval_min, dex, coin, timestamp
SETTINGS max_threads = 4, max_insert_threads = 4, max_execution_time = 600;
