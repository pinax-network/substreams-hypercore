-- Per-bucket distinct user counts for OHLCV fills --
-- Replaces the AggregateFunction(uniq, String) state column on state_ohlcv_fills.
-- See `state_open_interest_uniq_user.sql` for the rationale and TTL caveat.
--
-- Source unions both regular `fills` and `fills_liquidation`, mirroring the two
-- MVs (mv_state_ohlcv_fills + mv_state_ohlcv_fills_liquidation) that populate
-- state_ohlcv_fills with the matching direction-exclusion filter (regular
-- trades only — liquidations and vault internals are tracked separately).
--
-- Two MVs write to this table:
--   * mv_refresh_state_ohlcv_fills_uniq_user         — hourly, last 14 days
--   * mv_refresh_state_ohlcv_fills_uniq_user_alltime — every 6h, full scan
--
-- The hourly recent MV scans only the last 14 days of fills (about 10x less
-- than the full table) so it finishes within budget under cluster contention.
-- The alltime MV refreshes every bar regardless of age, keeping older bars'
-- counts current. TTL = 7h covers the 6h cadence plus retry slack — a single
-- missed alltime cycle still leaves valid rows for older bars on disk.

CREATE TABLE IF NOT EXISTS state_ohlcv_fills_uniq_user (
    refresh_time             DateTime('UTC'),
    interval_min             UInt16 COMMENT 'bar interval in minutes (1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w)',
    dex                      LowCardinality(String) COMMENT 'DEX/market namespace parsed from coin (: custom, # outcome, @ spot, fallback perps)',
    coin                     LowCardinality(String) COMMENT 'Trading pair/coin symbol',
    timestamp                DateTime('UTC') COMMENT 'beginning of the bar',
    uniq_user                UInt64 COMMENT 'distinct users with fills (regular + liquidation) in the window'
) ENGINE = ReplacingMergeTree(refresh_time)
ORDER BY (interval_min, dex, coin, timestamp)
TTL refresh_time + INTERVAL 7 HOUR;

-- Recent MV — scans only the last 14 days so a single tick fits under
-- max_execution_time even with 4 threads. Older bars are kept fresh by the
-- alltime MV below.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_refresh_state_ohlcv_fills_uniq_user
REFRESH EVERY 1 HOUR OFFSET 6 MINUTE APPEND
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
    WHERE fill_time >= now() - INTERVAL 14 DAY
      AND price > 0 AND size > 0
      AND direction NOT LIKE 'LIQUIDATED_%'
      AND direction NOT IN (
          'AUTO_DELEVERAGING', 'NET_CHILD_VAULTS', 'SPOT_DUST_CONVERSION',
          'SETTLEMENT',
          'SPLIT_OUTCOME', 'MERGE_OUTCOME', 'MERGE_QUESTION', 'NEGATE_OUTCOME'
      )
    UNION ALL
    SELECT fill_time, dex, coin, user FROM fills_liquidation
    WHERE fill_time >= now() - INTERVAL 14 DAY
      AND price > 0 AND size > 0
      AND direction NOT LIKE 'LIQUIDATED_%'
      AND direction NOT IN (
          'AUTO_DELEVERAGING', 'NET_CHILD_VAULTS', 'SPOT_DUST_CONVERSION',
          'SETTLEMENT',
          'SPLIT_OUTCOME', 'MERGE_OUTCOME', 'MERGE_QUESTION', 'NEGATE_OUTCOME'
      )
)
GROUP BY interval_min, dex, coin, timestamp
SETTINGS max_threads = 4, max_insert_threads = 4, max_execution_time = 300;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_refresh_state_ohlcv_fills_uniq_user_alltime
REFRESH EVERY 6 HOUR OFFSET 2 HOUR 42 MINUTE APPEND
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
    WHERE price > 0 AND size > 0
      AND direction NOT LIKE 'LIQUIDATED_%'
      AND direction NOT IN (
          'AUTO_DELEVERAGING', 'NET_CHILD_VAULTS', 'SPOT_DUST_CONVERSION',
          'SETTLEMENT',
          'SPLIT_OUTCOME', 'MERGE_OUTCOME', 'MERGE_QUESTION', 'NEGATE_OUTCOME'
      )
    UNION ALL
    SELECT fill_time, dex, coin, user FROM fills_liquidation
    WHERE price > 0 AND size > 0
      AND direction NOT LIKE 'LIQUIDATED_%'
      AND direction NOT IN (
          'AUTO_DELEVERAGING', 'NET_CHILD_VAULTS', 'SPOT_DUST_CONVERSION',
          'SETTLEMENT',
          'SPLIT_OUTCOME', 'MERGE_OUTCOME', 'MERGE_QUESTION', 'NEGATE_OUTCOME'
      )
)
GROUP BY interval_min, dex, coin, timestamp
SETTINGS max_threads = 4, max_insert_threads = 4, max_execution_time = 1500;
