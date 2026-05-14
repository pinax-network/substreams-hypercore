-- Per-bucket distinct user counts for open interest --
-- Replaces the AggregateFunction(uniq, String) state column on state_open_interest.
-- Storing the final count as UInt64 turns query-time uniqMerge (~3 s on hot coins,
-- ~1 GB peak memory) into a primary-key lookup (~3 ms). The HLL state for
-- AggregateFunction(uniq, String) was the dominant cost in OI/OHLC API queries.
--
-- Pattern mirrors `state_user_by_coin`: REFRESH EVERY 1 HOUR APPEND into a
-- ReplacingMergeTree(refresh_time) target with a TTL window covering several
-- refresh ticks. Consumers read with FINAL.
--
-- TTL = refresh_time + 3 HOUR. Refresh runs hourly so the window holds the last
-- ~3 snapshots. If the refresh MV stops succeeding for >3 hours the table goes
-- empty until the next successful refresh — alert on stale max(refresh_time).

CREATE TABLE IF NOT EXISTS state_open_interest_uniq_user (
    refresh_time             DateTime('UTC'),
    interval_min             UInt16 COMMENT 'bar interval in minutes (1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w)',
    dex                      LowCardinality(String) COMMENT 'DEX/market namespace parsed from coin (: custom, # outcome, @ spot, fallback perps)',
    coin                     LowCardinality(String) COMMENT 'Trading pair/coin symbol',
    timestamp                DateTime('UTC') COMMENT 'beginning of the bar',
    uniq_user                UInt64 COMMENT 'distinct users with funding observations in the window'
) ENGINE = ReplacingMergeTree(refresh_time)
ORDER BY (interval_min, dex, coin, timestamp)
TTL refresh_time + INTERVAL 3 HOUR;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_refresh_state_open_interest_uniq_user
REFRESH EVERY 1 HOUR OFFSET 20 MINUTE APPEND
TO state_open_interest_uniq_user
AS
SELECT
    now() AS refresh_time,
    arrayJoin([1, 5, 10, 30, 60, 240, 1440, 10080]) AS interval_min,
    f.dex AS dex,
    f.coin AS coin,
    toDateTime(intDiv(toUInt32(f.timestamp), interval_min * 60) * interval_min * 60, 'UTC') AS timestamp,
    uniqExact(f.user) AS uniq_user
FROM funding_deltas AS f
WHERE f.szi != 0
GROUP BY interval_min, dex, coin, timestamp
SETTINGS max_threads = 4, max_insert_threads = 4, max_execution_time = 600;
