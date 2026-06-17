-- User Leaderboard pre-aggregated across coins / dexes --
-- Pre-computed user trading stats per (interval_min, user), summed across
-- all coins and dexes the user has traded.
--
-- Serves the unscoped leaderboard and single-user profile modes of the
-- `/v1/hyperliquid/users` endpoint, which previously read
-- `state_user_by_coin FINAL` with `GROUP BY user` and timed out at the
-- ClickHouse `max_execution_time` once the source MV accumulated partial
-- states between merges.
--
-- The sort key is `(interval_min, user)` — leaderboard mode hits the
-- prefix for the sort, single-user profile mode is a point lookup. Filters
-- on `coin` or `dex` are not supported here. The API falls back to
-- `state_user_by_coin` (schema.3) for those cases.
--
-- Refreshed hourly by chaining off `state_user_by_coin FINAL`. Adds up to
-- one hour of additional staleness on top of the source MV's hour, so up
-- to two hours of total lag in the worst case — acceptable for leaderboards.
--
-- The same APPEND + ReplacingMergeTree pattern as the rest of the
-- refresh-MV layer. Consumers must read with FINAL.

CREATE TABLE IF NOT EXISTS state_user_leaderboard (
    refresh_time      DateTime('UTC'),
    interval_min      UInt32 COMMENT '0=all-time, 60=1h, 1440=1d, 10080=1w, 43200=30d',
    user              String,
    transactions      UInt64,
    buys              UInt64,
    sells             UInt64,
    volume_bought     Float64,
    volume_sold       Float64,
    total_volume      Float64,
    total_fees        Float64,
    realized_pnl      Float64,
    total_funding     Float64,
    liquidation_fills UInt64,
    coins_traded      UInt32 COMMENT 'distinct coins the user traded (real BUY/SELL/etc.) in this interval — excludes coins whose only retained activity is SETTLEMENT',
    first_trade       DateTime('UTC') COMMENT 'Earliest captured activity (any direction) across all the user''s coins',
    last_trade        DateTime('UTC') COMMENT 'Most recent captured activity (any direction) across all the user''s coins'
) ENGINE = ReplacingMergeTree(refresh_time)
ORDER BY (interval_min, user)
TTL refresh_time + INTERVAL 3 HOUR;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_refresh_state_user_leaderboard
REFRESH EVERY 1 HOUR OFFSET 57 MINUTE APPEND
TO state_user_leaderboard
AS
SELECT
    now()                                                    AS refresh_time,
    s.interval_min                                           AS interval_min,
    s.user                                                   AS user,
    sum(s.transactions)                                      AS transactions,
    sum(s.buys)                                              AS buys,
    sum(s.sells)                                             AS sells,
    sum(s.volume_bought)                                     AS volume_bought,
    sum(s.volume_sold)                                       AS volume_sold,
    sum(s.total_volume)                                      AS total_volume,
    sum(s.total_fees)                                        AS total_fees,
    sum(s.realized_pnl)                                      AS realized_pnl,
    sum(s.total_funding)                                     AS total_funding,
    sum(s.liquidation_fills)                                 AS liquidation_fills,
    countIf(s.transactions > 0)                              AS coins_traded,
    min(s.first_trade)                                       AS first_trade,
    max(s.last_trade)                                        AS last_trade
FROM state_user_by_coin AS s FINAL
GROUP BY s.interval_min, s.user
SETTINGS max_threads = 4, max_insert_threads = 4, max_execution_time = 600;
