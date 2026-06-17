-- User Leaderboard pre-aggregated by (dex, user) --
-- Sibling of `state_user_leaderboard` (which is keyed on (interval_min, user)
-- and sums across all dexes). This table keeps the `dex` dimension so the
-- `/users?dex=...` and `/outcomes/users` endpoints can read a fast dex-scoped
-- leaderboard without scanning `state_user_by_coin` per request.
--
-- Sort key: `(interval_min, dex, user)`. Leaderboard mode (no `user`) reads
-- the prefix `(interval_min, dex)`. Single-user profile within a dex is a
-- point lookup.
--
-- Refreshed hourly by chaining off `state_user_by_coin FINAL`. Same
-- staleness budget as `state_user_leaderboard` — up to two hours of lag
-- in the worst case.
--
-- Engine: ReplacingMergeTree(refresh_time) — substreams sink rewrites to
-- ReplicatedReplacingMergeTree on a cluster. Consumers must read with FINAL.

CREATE TABLE IF NOT EXISTS state_user_leaderboard_by_dex (
    refresh_time      DateTime('UTC'),
    interval_min      UInt32 COMMENT '0=all-time, 60=1h, 1440=1d, 10080=1w, 43200=30d',
    dex               LowCardinality(String),
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
    coins_traded      UInt32 COMMENT 'distinct coins the user traded (real BUY/SELL/etc.) on this dex in this interval — excludes coins whose only retained activity is SETTLEMENT',
    first_trade       DateTime('UTC') COMMENT 'Earliest captured activity (any direction) across the user''s coins on this dex',
    last_trade        DateTime('UTC') COMMENT 'Most recent captured activity (any direction) across the user''s coins on this dex'
) ENGINE = ReplacingMergeTree(refresh_time)
ORDER BY (interval_min, dex, user)
TTL refresh_time + INTERVAL 3 HOUR;

-- Staggered between the source refresh (`state_user_by_coin` at :22) and the
-- unscoped leaderboard (`state_user_leaderboard` at :57) so the three MVs
-- don't stack on a single minute.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_refresh_state_user_leaderboard_by_dex
REFRESH EVERY 1 HOUR OFFSET 47 MINUTE APPEND
TO state_user_leaderboard_by_dex
AS
SELECT
    now()                                                    AS refresh_time,
    s.interval_min                                           AS interval_min,
    s.dex                                                    AS dex,
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
GROUP BY s.interval_min, s.dex, s.user
SETTINGS max_threads = 4, max_insert_threads = 4, max_execution_time = 600;
