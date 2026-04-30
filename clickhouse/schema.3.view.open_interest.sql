-- Funding snapshot observation view --
-- Provides a convenient interface for querying merged funding snapshot observations by dex and coin
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

    -- DEX/coin identity --
    dex,
    coin,

    -- funding snapshot observation aggregates --
    sum(sum_szi_observations) AS sum_szi_observations,
    sum(sum_abs_szi_observations) AS sum_abs_szi_observations,
    sum(sum_long_szi_observations) AS sum_long_szi_observations,
    sum(sum_short_szi_observations) AS sum_short_szi_observations,

    -- funding aggregates --
    sum(total_funding) AS total_funding,
    sum(positive_funding) AS positive_funding,
    sum(negative_funding) AS negative_funding,

    -- funding rate --
    avgMerge(avg_funding_rate) AS avg_funding_rate,

    -- counts --
    sum(funding_events) AS funding_events,
    sum(long_positions) AS long_positions,
    sum(short_positions) AS short_positions

FROM state_open_interest
GROUP BY
    interval_min,
    dex,
    coin,
    timestamp;
