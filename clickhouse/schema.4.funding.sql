-- Funding Deltas table --
-- Represents funding rate deltas
CREATE TABLE IF NOT EXISTS funding_deltas AS TEMPLATE_EVENT;
ALTER TABLE funding_deltas
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS coin                        String,
    ADD COLUMN IF NOT EXISTS funding_amount              String,
    ADD COLUMN IF NOT EXISTS szi                         String,
    ADD COLUMN IF NOT EXISTS funding_rate                String,
    -- PROJECTIONS --
    ADD PROJECTION IF NOT EXISTS prj_user (SELECT * ORDER BY user),
    ADD PROJECTION IF NOT EXISTS prj_coin (SELECT * ORDER BY coin);
