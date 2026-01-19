-- C Deposits table --
-- Represents cross-chain deposit events
CREATE TABLE IF NOT EXISTS c_deposits AS TEMPLATE_EVENT;
ALTER TABLE c_deposits
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS amount                      String,
    -- PROJECTIONS --
    ADD PROJECTION IF NOT EXISTS prj_user (SELECT * ORDER BY user);

-- C Withdrawals table --
-- Represents cross-chain withdrawal events
CREATE TABLE IF NOT EXISTS c_withdrawals AS TEMPLATE_EVENT;
ALTER TABLE c_withdrawals
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS amount                      String,
    ADD COLUMN IF NOT EXISTS is_finalized                Bool,
    -- PROJECTIONS --
    ADD PROJECTION IF NOT EXISTS prj_user (SELECT * ORDER BY user);
