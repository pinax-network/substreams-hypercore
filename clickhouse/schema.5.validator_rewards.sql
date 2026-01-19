-- Validator Rewards table --
-- Represents validator reward distributions
CREATE TABLE IF NOT EXISTS validator_rewards AS TEMPLATE_EVENT;
ALTER TABLE validator_rewards
    ADD COLUMN IF NOT EXISTS validator                   String,
    ADD COLUMN IF NOT EXISTS reward                      String,
    -- PROJECTIONS --
    ADD PROJECTION IF NOT EXISTS prj_validator (SELECT * ORDER BY validator);
