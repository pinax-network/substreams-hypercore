-- Funding Deltas table --
-- Represents funding rate deltas
CREATE TABLE IF NOT EXISTS funding_deltas AS TEMPLATE_EVENT;
ALTER TABLE funding_deltas
    ADD COLUMN IF NOT EXISTS user                        String,
    ADD COLUMN IF NOT EXISTS coin                        String,
    ADD COLUMN IF NOT EXISTS dex                         LowCardinality(String) MATERIALIZED dex_from_coin(coin),
    ADD COLUMN IF NOT EXISTS funding_amount              Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS szi                         Float64 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS funding_rate                Float64 DEFAULT 0,

    -- Skip index on user — high-cardinality column not in the sort key.
    -- Powers per-user lookups (e.g. /users/activity in Token API) without a full
    -- range scan of the time-sorted table. Adds ~2% disk for ~5-11x speedup
    -- on `WHERE user = ?` over a time-bounded window.
    ADD INDEX IF NOT EXISTS idx_user user TYPE bloom_filter(0.001) GRANULARITY 1,

    -- PROJECTIONS for dex analytics --
    ADD PROJECTION IF NOT EXISTS prj_dex_count ( SELECT dex, count(), min(block_num), max(block_num), min(timestamp), max(timestamp), min(minute), max(minute) GROUP BY dex ),
    ADD PROJECTION IF NOT EXISTS prj_dex_by_minute ( SELECT dex, minute, count() GROUP BY dex, minute ),
    ADD PROJECTION IF NOT EXISTS prj_dex_coin_by_minute ( SELECT dex, coin, minute, count() GROUP BY dex, coin, minute ),
    ADD PROJECTION IF NOT EXISTS prj_dex_user_by_minute ( SELECT dex, user, minute, count() GROUP BY dex, user, minute ),
    ADD PROJECTION IF NOT EXISTS prj_dex_coin_user_by_minute ( SELECT dex, coin, user, minute, count() GROUP BY dex, coin, user, minute );

ALTER TABLE funding_deltas
    MODIFY COLUMN IF EXISTS dex                         LowCardinality(String) MATERIALIZED dex_from_coin(coin);
