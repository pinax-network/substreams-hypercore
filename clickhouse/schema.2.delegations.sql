-- Delegations table --
-- Represents delegation/undelegation events
CREATE TABLE IF NOT EXISTS delegations AS TEMPLATE_EVENT;
ALTER TABLE delegations
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS validator                   String,
    ADD COLUMN IF NOT EXISTS amount                      String,
    ADD COLUMN IF NOT EXISTS is_undelegate               Bool,
    -- PROJECTIONS --
    ADD PROJECTION IF NOT EXISTS prj_user (SELECT * ORDER BY user),
    ADD PROJECTION IF NOT EXISTS prj_validator (SELECT * ORDER BY validator);
