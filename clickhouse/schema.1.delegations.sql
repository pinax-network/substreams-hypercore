-- Delegations table --
-- Represents delegation/undelegation events
CREATE TABLE IF NOT EXISTS delegations AS TEMPLATE_EVENT;
ALTER TABLE delegations
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS validator                   String,
    ADD COLUMN IF NOT EXISTS amount                      String,
    ADD COLUMN IF NOT EXISTS amount_num                  Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS is_undelegate               Bool;
