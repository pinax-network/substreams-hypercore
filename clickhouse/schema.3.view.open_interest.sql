-- Open Interest view --
-- Provides a convenient interface for querying open interest data with merged aggregates
CREATE VIEW IF NOT EXISTS open_interest AS
SELECT
    -- bar interval --
    timestamp,
    interval_min,

    -- timestamp & block number --
    min(min_timestamp) AS min_timestamp,
    max(max_timestamp) AS max_timestamp,
    min(min_block_num) AS min_block_num,
    max(max_block_num) AS max_block_num,

    -- trading identity --
    coin,

    -- open interest aggregates --
    sum(total_szi) AS total_szi,
    sum(abs_szi) AS abs_szi,
    sum(long_szi) AS long_szi,
    sum(short_szi) AS short_szi,

    -- funding aggregates --
    sum(total_funding) AS total_funding,
    sum(positive_funding) AS positive_funding,
    sum(negative_funding) AS negative_funding,

    -- funding rate --
    avgMerge(avg_funding_rate) AS avg_funding_rate,

    -- counts --
    sum(funding_events) AS funding_events,
    sum(long_positions) AS long_positions,
    sum(short_positions) AS short_positions,

    -- unique counts --
    uniqMerge(uniq_user) AS uniq_user

FROM state_open_interest
GROUP BY
    interval_min,
    coin,
    timestamp;
