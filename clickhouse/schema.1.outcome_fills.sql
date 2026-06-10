-- HIP-4 outcome fills --
-- `coin = '#' + (outcome_id * 10 + side)` where `side ∈ {0, 1}` indexes
-- into the outcome's `sideSpecs` array (typically Yes/No, but can be team
-- names or any deployer-chosen labels). The substream parses the encoding
-- once at write time so `outcome_id` and `side_index` are real columns —
-- they can participate in projections / ORDER BY without re-parsing the
-- `coin` string on every query.
--
-- Kept as a sibling table to `fills` (not a discriminated subset) so perp
-- and spot OHLCV / leaderboard MVs don't pay an outcome scan tax, and so
-- outcome consumers don't pay the perp scan tax.
CREATE TABLE IF NOT EXISTS outcome_fills AS TEMPLATE_EVENT;
ALTER TABLE outcome_fills
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS coin                        LowCardinality(String),
    ADD COLUMN IF NOT EXISTS dex                         LowCardinality(String) MATERIALIZED dex_from_coin(coin),
    ADD COLUMN IF NOT EXISTS outcome_id                  UInt64,
    ADD COLUMN IF NOT EXISTS side_index                  UInt8 COMMENT '0 = first sideSpec, 1 = second sideSpec',
    ADD COLUMN IF NOT EXISTS price                       Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS size                        Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS side                        LowCardinality(String) COMMENT 'BID or ASK',
    ADD COLUMN IF NOT EXISTS fill_time                   DateTime('UTC'),
    ADD COLUMN IF NOT EXISTS start_position              String,
    ADD COLUMN IF NOT EXISTS direction                   LowCardinality(String) COMMENT 'Trading direction (BUY, SELL, SETTLEMENT, SPLIT_OUTCOME, MERGE_OUTCOME, MERGE_QUESTION, NEGATE_OUTCOME)',
    ADD COLUMN IF NOT EXISTS closed_pnl                  String,
    ADD COLUMN IF NOT EXISTS closed_pnl_num              Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS order_id                    UInt64,
    ADD COLUMN IF NOT EXISTS crossed                     Bool,
    ADD COLUMN IF NOT EXISTS fee                         Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS transaction_id              UInt64,
    ADD COLUMN IF NOT EXISTS fee_token                   LowCardinality(String),
    ADD COLUMN IF NOT EXISTS twap_id                     UInt64,
    ADD COLUMN IF NOT EXISTS client_order_id             String,
    ADD COLUMN IF NOT EXISTS deployer_fee                Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS builder                     LowCardinality(String),
    ADD COLUMN IF NOT EXISTS builder_fee                 Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS priority_gas                Float64 DEFAULT 0,

    ADD PROJECTION IF NOT EXISTS prj_outcome_count ( SELECT outcome_id, count(), min(block_num), max(block_num), min(timestamp), max(timestamp) GROUP BY outcome_id ),
    ADD PROJECTION IF NOT EXISTS prj_user_count ( SELECT user, count(), min(block_num), max(block_num), min(timestamp), max(timestamp) GROUP BY user ),
    ADD PROJECTION IF NOT EXISTS prj_direction_count ( SELECT direction, count(), min(block_num), max(block_num), min(timestamp), max(timestamp) GROUP BY direction ),

    ADD PROJECTION IF NOT EXISTS prj_outcome_by_minute ( SELECT outcome_id, minute, count() GROUP BY outcome_id, minute ),
    ADD PROJECTION IF NOT EXISTS prj_user_by_minute ( SELECT user, minute, count() GROUP BY user, minute );

ALTER TABLE outcome_fills
    MODIFY COLUMN IF EXISTS dex                         LowCardinality(String) MATERIALIZED dex_from_coin(coin);
