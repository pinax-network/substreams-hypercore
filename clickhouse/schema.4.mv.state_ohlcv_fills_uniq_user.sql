-- Per-bucket distinct user counts for OHLCV fills --
-- Replaces the AggregateFunction(uniq, String) state column on state_ohlcv_fills.
-- See `state_open_interest_uniq_user.sql` for the rationale and TTL caveat.
--
-- Source unions both regular `fills` and `fills_liquidation`, mirroring the two
-- MVs (mv_state_ohlcv_fills + mv_state_ohlcv_fills_liquidation) that populate
-- state_ohlcv_fills with the matching client_order_id != '' filter.

CREATE TABLE IF NOT EXISTS state_ohlcv_fills_uniq_user (
    refresh_time             DateTime('UTC'),
    interval_min             UInt16 COMMENT 'bar interval in minutes (1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w)',
    dex                      LowCardinality(String) COMMENT 'DEX/market namespace parsed from coin',
    coin                     LowCardinality(String) COMMENT 'Trading pair/coin symbol',
    timestamp                DateTime('UTC') COMMENT 'beginning of the bar',
    uniq_user                UInt64 COMMENT 'distinct users with fills (regular + liquidation) in the window'
) ENGINE = ReplacingMergeTree(refresh_time)
ORDER BY (interval_min, dex, coin, timestamp)
TTL refresh_time + INTERVAL 3 HOUR;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_refresh_state_ohlcv_fills_uniq_user
REFRESH EVERY 1 HOUR APPEND
TO state_ohlcv_fills_uniq_user
AS
SELECT
    now() AS refresh_time,
    arrayJoin([1, 5, 10, 30, 60, 240, 1440, 10080]) AS interval_min,
    dex, coin,
    toDateTime(intDiv(toUInt32(fill_time), interval_min * 60) * interval_min * 60, 'UTC') AS timestamp,
    uniqExact(user) AS uniq_user
FROM (
    SELECT fill_time, dex, coin, user FROM fills
    WHERE price > 0 AND size > 0 AND client_order_id != ''
    UNION ALL
    SELECT fill_time, dex, coin, user FROM fills_liquidation
    WHERE price > 0 AND size > 0 AND client_order_id != ''
)
GROUP BY interval_min, dex, coin, timestamp
SETTINGS max_execution_time = 600;
