-- Fills table --
-- Represents trade fills on Hypercore
CREATE TABLE IF NOT EXISTS fills AS TEMPLATE_EVENT;
ALTER TABLE fills
    -- fill-specific fields --
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS coin                        String,
    ADD COLUMN IF NOT EXISTS price                       String,
    ADD COLUMN IF NOT EXISTS size                        String,
    ADD COLUMN IF NOT EXISTS side                        String COMMENT 'FILL_SIDE_ASK or FILL_SIDE_BUY',
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
    -- PROJECTIONS --
    ADD PROJECTION IF NOT EXISTS prj_user (SELECT * ORDER BY user),
    ADD PROJECTION IF NOT EXISTS prj_coin (SELECT * ORDER BY coin),
    ADD PROJECTION IF NOT EXISTS prj_order_id (SELECT * ORDER BY order_id);
