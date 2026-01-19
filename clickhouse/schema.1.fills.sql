-- Fills table --
-- Represents trade fills on Hypercore
CREATE TABLE IF NOT EXISTS fills AS TEMPLATE_EVENT;
ALTER TABLE fills
    -- fill-specific fields --
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS coin                        String,
    ADD COLUMN IF NOT EXISTS price                       String,
    ADD COLUMN IF NOT EXISTS size                        String,
    ADD COLUMN IF NOT EXISTS side                        String COMMENT 'ASK or BUY',
    ADD COLUMN IF NOT EXISTS fill_time                   DateTime('UTC'),
    ADD COLUMN IF NOT EXISTS start_position              String,
    ADD COLUMN IF NOT EXISTS direction                   String COMMENT 'Trading direction enum',
    ADD COLUMN IF NOT EXISTS closed_pnl                  String,
    ADD COLUMN IF NOT EXISTS order_id                    UInt64,
    ADD COLUMN IF NOT EXISTS crossed                     Bool,
    ADD COLUMN IF NOT EXISTS fee                         String,
    ADD COLUMN IF NOT EXISTS transaction_id              UInt64,
    ADD COLUMN IF NOT EXISTS fee_token                   String,
    ADD COLUMN IF NOT EXISTS twap_id                     UInt64 COMMENT 'Time-Weighted Average Price Identifier',
    ADD COLUMN IF NOT EXISTS client_order_id             String,
    -- liquidation fields (optional) --
    ADD COLUMN IF NOT EXISTS liquidated_user             String,
    ADD COLUMN IF NOT EXISTS mark_px                     String,
    ADD COLUMN IF NOT EXISTS liquidation_method          String,

    -- PROJECTIONS for analytics (minute & count) --
    ADD PROJECTION IF NOT EXISTS prj_coin_count ( SELECT coin, count(), min(block_num), max(block_num), min(timestamp), max(timestamp), min(minute), max(minute) GROUP BY coin ),
    ADD PROJECTION IF NOT EXISTS prj_user_count ( SELECT user, count(), min(block_num), max(block_num), min(timestamp), max(timestamp), min(minute), max(minute) GROUP BY user ),
    ADD PROJECTION IF NOT EXISTS prj_side_count ( SELECT side, count(), min(block_num), max(block_num), min(timestamp), max(timestamp), min(minute), max(minute) GROUP BY side ),
    ADD PROJECTION IF NOT EXISTS prj_direction_count ( SELECT direction, count(), min(block_num), max(block_num), min(timestamp), max(timestamp), min(minute), max(minute) GROUP BY direction ),

    -- minute projections --
    ADD PROJECTION IF NOT EXISTS prj_coin_by_minute ( SELECT coin, minute, count() GROUP BY coin, minute ),
    ADD PROJECTION IF NOT EXISTS prj_user_by_minute ( SELECT user, minute, count() GROUP BY user, minute ),
    ADD PROJECTION IF NOT EXISTS prj_side_by_minute ( SELECT side, minute, count() GROUP BY side, minute ),
    ADD PROJECTION IF NOT EXISTS prj_direction_by_minute ( SELECT direction, minute, count() GROUP BY direction, minute ),
    ADD PROJECTION IF NOT EXISTS prj_all_by_minute ( SELECT coin, side, direction, minute, count() GROUP BY coin, side, direction, minute );
