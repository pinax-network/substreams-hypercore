-- Fills table --
-- Represents trade fills on Hypercore
CREATE TABLE IF NOT EXISTS fills AS TEMPLATE_EVENT;
ALTER TABLE fills
    -- fill-specific fields --
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS coin                        LowCardinality(String),
    ADD COLUMN IF NOT EXISTS dex                         LowCardinality(String) MATERIALIZED dex_from_coin(coin),
    ADD COLUMN IF NOT EXISTS price                       Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS size                        Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS side                        LowCardinality(String) COMMENT 'BID or ASK',
    ADD COLUMN IF NOT EXISTS fill_time                   DateTime('UTC'),
    ADD COLUMN IF NOT EXISTS start_position              String,
    ADD COLUMN IF NOT EXISTS direction                   LowCardinality(String) COMMENT 'Trading direction enum',
    ADD COLUMN IF NOT EXISTS closed_pnl                  String,
    ADD COLUMN IF NOT EXISTS closed_pnl_num              Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS order_id                    UInt64,
    ADD COLUMN IF NOT EXISTS crossed                     Bool,
    ADD COLUMN IF NOT EXISTS fee                         Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS transaction_id              UInt64,
    ADD COLUMN IF NOT EXISTS fee_token                   LowCardinality(String),
    ADD COLUMN IF NOT EXISTS twap_id                     UInt64 COMMENT 'Time-Weighted Average Price Identifier',
    ADD COLUMN IF NOT EXISTS client_order_id             String,

    -- PROJECTIONS for analytics (minute & count) --
    ADD PROJECTION IF NOT EXISTS prj_coin_count ( SELECT coin, count(), min(block_num), max(block_num), min(timestamp), max(timestamp), min(minute), max(minute) GROUP BY coin ),
    ADD PROJECTION IF NOT EXISTS prj_dex_count ( SELECT dex, count(), min(block_num), max(block_num), min(timestamp), max(timestamp), min(minute), max(minute) GROUP BY dex ),
    ADD PROJECTION IF NOT EXISTS prj_user_count ( SELECT user, count(), min(block_num), max(block_num), min(timestamp), max(timestamp), min(minute), max(minute) GROUP BY user ),
    ADD PROJECTION IF NOT EXISTS prj_side_count ( SELECT side, count(), min(block_num), max(block_num), min(timestamp), max(timestamp), min(minute), max(minute) GROUP BY side ),
    ADD PROJECTION IF NOT EXISTS prj_direction_count ( SELECT direction, count(), min(block_num), max(block_num), min(timestamp), max(timestamp), min(minute), max(minute) GROUP BY direction ),

    -- minute projections --
    ADD PROJECTION IF NOT EXISTS prj_coin_by_minute ( SELECT coin, minute, count() GROUP BY coin, minute ),
    ADD PROJECTION IF NOT EXISTS prj_dex_by_minute ( SELECT dex, minute, count() GROUP BY dex, minute ),
    ADD PROJECTION IF NOT EXISTS prj_dex_coin_by_minute ( SELECT dex, coin, minute, count() GROUP BY dex, coin, minute ),
    ADD PROJECTION IF NOT EXISTS prj_user_by_minute ( SELECT user, minute, count() GROUP BY user, minute ),
    ADD PROJECTION IF NOT EXISTS prj_side_by_minute ( SELECT side, minute, count() GROUP BY side, minute ),
    ADD PROJECTION IF NOT EXISTS prj_direction_by_minute ( SELECT direction, minute, count() GROUP BY direction, minute ),
    ADD PROJECTION IF NOT EXISTS prj_all_by_minute ( SELECT dex, coin, side, direction, minute, count() GROUP BY dex, coin, side, direction, minute );

-- Fills Liquidation table --
-- Represents liquidation trade fills on Hypercore
-- Only contains fills that have liquidation data
CREATE TABLE IF NOT EXISTS fills_liquidation AS fills;
ALTER TABLE fills_liquidation
    -- liquidation field --
    ADD COLUMN IF NOT EXISTS liquidated_user             String,
    ADD COLUMN IF NOT EXISTS mark_px                     Float64 COMMENT 'Mark price for liquidation',
    ADD COLUMN IF NOT EXISTS liquidation_method          String,

    -- PROJECTIONS for analytics (minute & count) --
    ADD PROJECTION IF NOT EXISTS prj_liquidated_user_count ( SELECT liquidated_user, count(), min(block_num), max(block_num), min(timestamp), max(timestamp), min(minute), max(minute) GROUP BY liquidated_user ),
    ADD PROJECTION IF NOT EXISTS prj_dex_liquidated_user_count ( SELECT dex, liquidated_user, count(), min(block_num), max(block_num), min(timestamp), max(timestamp), min(minute), max(minute) GROUP BY dex, liquidated_user ),
    ADD PROJECTION IF NOT EXISTS prj_liquidated_user_by_minute ( SELECT liquidated_user, minute, count() GROUP BY liquidated_user, minute ),
    ADD PROJECTION IF NOT EXISTS prj_dex_liquidated_user_by_minute ( SELECT dex, liquidated_user, minute, count() GROUP BY dex, liquidated_user, minute );
