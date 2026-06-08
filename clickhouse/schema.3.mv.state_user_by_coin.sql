-- User Leaderboard by (dex, coin, user) --
-- Pre-computed user trading stats per (interval_min, coin, user).
--
-- Two MVs write to this table:
--   * mv_refresh_state_user_by_coin         — hourly, intervals 60/1440/10080/43200
--   * mv_refresh_state_user_by_coin_alltime — every 6h, interval_min = 0
--
-- The sort key leads with `dex` so that both dex-scoped and coin-scoped
-- filters get a fast path:
--   * dex filter — granule prune on (interval_min, dex)
--   * coin filter — within an interval, granules cluster by dex and a
--     coin's dex is fixed, so per-granule minmax indexes on `coin` prune
--     to the relevant dex range without an explicit `dex` predicate
--   * user-only or unfiltered leaderboard — served by `state_user_leaderboard`
--     in schema.4 (this table cannot prune on `user` cheaply)
--
-- Engine: ReplacingMergeTree(refresh_time) — substreams sink rewrites to
-- ReplicatedReplacingMergeTree on a cluster. Consumers must read with FINAL.

CREATE TABLE IF NOT EXISTS state_user_by_coin (
    refresh_time             DateTime('UTC'),
    interval_min             UInt32 COMMENT '0=all-time, 60=1h, 1440=1d, 10080=1w, 43200=30d',
    coin                     LowCardinality(String),
    dex                      LowCardinality(String) COMMENT 'derived from dex_from_coin(coin), part of sort key for fast dex-filtered queries',
    user                     String,
    transactions             UInt64,
    buys                     UInt64 COMMENT 'BID-side fill count',
    sells                    UInt64 COMMENT 'ASK-side fill count',
    volume_bought            Float64 COMMENT 'BID-side notional, USDC',
    volume_sold              Float64 COMMENT 'ASK-side notional, USDC',
    total_volume             Float64,
    total_fees               Float64 COMMENT 'Negative when net maker rebates dominate',
    realized_pnl             Float64,
    total_funding            Float64 COMMENT 'Net funding — positive = received, negative = paid',
    liquidation_fills        UInt64 COMMENT 'Count of fills with LIQUIDATED_* direction',
    first_trade              DateTime('UTC'),
    last_trade               DateTime('UTC')
) ENGINE = ReplacingMergeTree(refresh_time)
ORDER BY (interval_min, dex, coin, user)
TTL refresh_time + INTERVAL 13 HOUR;

-- Source pruned to last 30d (the longest non-zero window).
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_refresh_state_user_by_coin
REFRESH EVERY 1 HOUR OFFSET 22 MINUTE APPEND
TO state_user_by_coin
AS
WITH
    time_periods AS (
        SELECT 43200 AS interval_min, now() - INTERVAL 30 DAY AS since
        UNION ALL SELECT 10080, now() - INTERVAL 7 DAY
        UNION ALL SELECT 1440,  now() - INTERVAL 1 DAY
        UNION ALL SELECT 60,    now() - INTERVAL 1 HOUR
    ),
    fills_agg AS (
        SELECT
            tp.interval_min                                  AS interval_min,
            f.coin                                           AS coin,
            f.dex                                            AS dex,
            f.user                                           AS user,
            count()                                          AS transactions,
            countIf(f.side = 'BID')                          AS buys,
            countIf(f.side = 'ASK')                          AS sells,
            sumIf(f.size * f.price, f.side = 'BID')          AS volume_bought,
            sumIf(f.size * f.price, f.side = 'ASK')          AS volume_sold,
            sum(f.size * f.price)                            AS total_volume,
            sum(f.fee)                                       AS total_fees,
            sum(f.closed_pnl_num)                            AS realized_pnl,
            countIf(f.direction LIKE 'LIQUIDATED_%' OR f.direction = 'AUTO_DELEVERAGING') AS liquidation_fills,
            min(f.fill_time)                                 AS first_trade,
            max(f.fill_time)                                 AS last_trade
        FROM fills f
        CROSS JOIN time_periods tp
        WHERE f.fill_time >= now() - INTERVAL 30 DAY
          AND f.fill_time >= tp.since
          AND f.direction NOT IN (
              'SETTLEMENT',
              'SPLIT_OUTCOME', 'MERGE_OUTCOME', 'MERGE_QUESTION', 'NEGATE_OUTCOME'
          )
        GROUP BY tp.interval_min, f.coin, f.dex, f.user
    ),
    funding_agg AS (
        SELECT
            tp.interval_min                                  AS interval_min,
            fd.coin                                          AS coin,
            fd.user                                          AS user,
            sum(fd.funding_amount)                           AS total_funding
        FROM funding_deltas fd
        CROSS JOIN time_periods tp
        WHERE fd.event_time >= now() - INTERVAL 30 DAY
          AND fd.event_time >= tp.since
        GROUP BY tp.interval_min, fd.coin, fd.user
    )
SELECT
    now()                                                    AS refresh_time,
    f.interval_min                                           AS interval_min,
    f.coin                                                   AS coin,
    f.dex                                                    AS dex,
    f.user                                                   AS user,
    f.transactions                                           AS transactions,
    f.buys                                                   AS buys,
    f.sells                                                  AS sells,
    f.volume_bought                                          AS volume_bought,
    f.volume_sold                                            AS volume_sold,
    f.total_volume                                           AS total_volume,
    f.total_fees                                             AS total_fees,
    f.realized_pnl                                           AS realized_pnl,
    coalesce(g.total_funding, 0)                             AS total_funding,
    f.liquidation_fills                                      AS liquidation_fills,
    f.first_trade                                            AS first_trade,
    f.last_trade                                             AS last_trade
FROM fills_agg f
LEFT JOIN funding_agg g USING (interval_min, coin, user)
SETTINGS max_threads = 4, max_insert_threads = 4, max_execution_time = 720;

CREATE MATERIALIZED VIEW IF NOT EXISTS mv_refresh_state_user_by_coin_alltime
REFRESH EVERY 6 HOUR OFFSET 1 HOUR 42 MINUTE APPEND
TO state_user_by_coin
AS
WITH
    fills_agg AS (
        SELECT
            f.coin                                           AS coin,
            f.dex                                            AS dex,
            f.user                                           AS user,
            count()                                          AS transactions,
            countIf(f.side = 'BID')                          AS buys,
            countIf(f.side = 'ASK')                          AS sells,
            sumIf(f.size * f.price, f.side = 'BID')          AS volume_bought,
            sumIf(f.size * f.price, f.side = 'ASK')          AS volume_sold,
            sum(f.size * f.price)                            AS total_volume,
            sum(f.fee)                                       AS total_fees,
            sum(f.closed_pnl_num)                            AS realized_pnl,
            countIf(f.direction LIKE 'LIQUIDATED_%' OR f.direction = 'AUTO_DELEVERAGING') AS liquidation_fills,
            min(f.fill_time)                                 AS first_trade,
            max(f.fill_time)                                 AS last_trade
        FROM fills f
        WHERE f.direction NOT IN (
            'SETTLEMENT',
            'SPLIT_OUTCOME', 'MERGE_OUTCOME', 'MERGE_QUESTION', 'NEGATE_OUTCOME'
        )
        GROUP BY f.coin, f.dex, f.user
    ),
    funding_agg AS (
        SELECT
            fd.coin                                          AS coin,
            fd.user                                          AS user,
            sum(fd.funding_amount)                           AS total_funding
        FROM funding_deltas fd
        GROUP BY fd.coin, fd.user
    )
SELECT
    now()                                                    AS refresh_time,
    toUInt32(0)                                              AS interval_min,
    f.coin                                                   AS coin,
    f.dex                                                    AS dex,
    f.user                                                   AS user,
    f.transactions                                           AS transactions,
    f.buys                                                   AS buys,
    f.sells                                                  AS sells,
    f.volume_bought                                          AS volume_bought,
    f.volume_sold                                            AS volume_sold,
    f.total_volume                                           AS total_volume,
    f.total_fees                                             AS total_fees,
    f.realized_pnl                                           AS realized_pnl,
    coalesce(g.total_funding, 0)                             AS total_funding,
    f.liquidation_fills                                      AS liquidation_fills,
    f.first_trade                                            AS first_trade,
    f.last_trade                                             AS last_trade
FROM fills_agg f
LEFT JOIN funding_agg g USING (coin, user)
SETTINGS max_threads = 4, max_insert_threads = 4, max_execution_time = 1200;
