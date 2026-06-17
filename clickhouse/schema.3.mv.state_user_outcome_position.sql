-- User outcome share positions --
-- Current open share balance per (user, outcome leg) derived from the full
-- history of `outcome_fills`. Each HIP-4 direction writes per-leg rows with
-- `side` encoding the share-flow direction (BID = receive, ASK = release),
-- so summing `if(side='BID', +size, -size)` across the entire fills history
-- yields the user's current share count.
--
-- Share-flow encoding per direction (verified empirically against HL
-- `userFills` / `spotClearinghouseState`):
--   * BUY                                  — BID, +size on the traded leg
--   * SELL                                 — ASK, -size on the traded leg
--   * SPLIT_OUTCOME                        — BID on both Yes and No legs
--   * MERGE_OUTCOME                        — ASK on both Yes and No legs
--   * NEGATE_OUTCOME                       — ASK on the negated No leg
--                                            + BID on the Yes leg of every
--                                            other outcome in the question
--   * MERGE_QUESTION                       — ASK on every Yes leg of the
--                                            question
--   * SETTLEMENT                           — ASK on every held leg of the
--                                            settled outcome (drives the
--                                            share balance to zero by the
--                                            time the resolution is processed)
--
-- Settled outcomes do not need a separate filter: SETTLEMENT fills emit
-- ASK on every previously-held leg, which zero out the running sum, and
-- HAVING share_balance > 0 prunes them. Verified empirically against
-- dev1 (2026-06-17): of 3,117 (user, settled-outcome) combos, 3,031
-- reach zero exactly. The 86 remainders are `0x320...` system addresses
-- (deployer / fallback) which legitimately retain non-zero balances
-- post-settlement.
--
-- HAVING share_balance > 0 keeps only currently-open long positions.
-- HIP-4 does not permit short share holdings, so a negative running sum
-- is necessarily a data artifact: the user acquired shares in events
-- that precede the sink's START_BLOCK and later sold or burned them
-- under our coverage window. Surfacing those rows would mislead
-- consumers reading the table as a holdings list.
--
-- Authoritative reconciliation: HL `spotClearinghouseState.balances[]`
-- (coin = `+<outcome_id*10 + side_index>`) is the source of truth.
-- This MV equals that endpoint exactly when the sink has been backfilled
-- from a block predating every still-live outcome's first fill, and
-- under-reports by exactly the shares acquired in events before the
-- backfill horizon otherwise. Verified empirically 2026-06-17 on a
-- dev1 sink with no backfill: 100% of the gap vs HL on a 25-leg user
-- reconciles to fills earlier than the sink's earliest captured block,
-- with zero in-window misses.
--
-- Engine: ReplacingMergeTree(refresh_time) — substreams sink rewrites to
-- ReplicatedReplacingMergeTree on a cluster. Consumers must read with FINAL.
--
-- Sort key `(user, outcome_id, side_index)` makes single-user position
-- queries a point lookup, with `outcome_id` and `side_index` available as
-- range filters.

CREATE TABLE IF NOT EXISTS state_user_outcome_position (
    refresh_time     DateTime('UTC'),
    user             String,
    coin             LowCardinality(String) COMMENT '#<outcome_id*10 + side_index> per HL HIP-4 encoding',
    outcome_id       UInt64,
    side_index       UInt8 COMMENT '0 = first sideSpec, 1 = second sideSpec',
    share_balance    Float64 COMMENT 'Net shares held on this leg. Negative is a data artifact (truncated history) — filtered out by HAVING > 0 at write time',
    last_fill_time   DateTime('UTC') COMMENT 'Most recent fill timestamp that touched this leg',
    last_block_num   UInt64 COMMENT 'Block number of the most recent touching fill'
) ENGINE = ReplacingMergeTree(refresh_time)
ORDER BY (user, outcome_id, side_index)
TTL refresh_time + INTERVAL 3 HOUR;

-- Staggered between the source-tier source MVs (state_user_by_coin at :22)
-- and the leaderboard-tier MVs (:47 / :57) so refreshes spread across the
-- hour. Reads raw outcome_fills, no upstream-MV dependency.
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_refresh_state_user_outcome_position
REFRESH EVERY 1 HOUR OFFSET 32 MINUTE APPEND
TO state_user_outcome_position
AS
SELECT
    now()                                                AS refresh_time,
    user                                                 AS user,
    coin                                                 AS coin,
    outcome_id                                           AS outcome_id,
    side_index                                           AS side_index,
    sum(if(side = 'BID', size, -size))                   AS share_balance,
    max(fill_time)                                       AS last_fill_time,
    max(block_num)                                       AS last_block_num
FROM outcome_fills
GROUP BY user, coin, outcome_id, side_index
HAVING share_balance > 0
SETTINGS max_threads = 4, max_insert_threads = 4, max_execution_time = 600;
