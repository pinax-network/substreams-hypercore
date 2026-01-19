-- Cross-chain deposits/withdrawals view --
-- Provides a convenient interface for querying cross-chain deposits/withdrawals data with merged aggregates
CREATE VIEW IF NOT EXISTS c_deposits_withdrawals AS
SELECT
    -- bar interval --
    timestamp,
    interval_min,

    -- timestamp & block number --
    min(min_timestamp) AS min_timestamp,
    max(max_timestamp) AS max_timestamp,
    min(min_block_num) AS min_block_num,
    max(max_block_num) AS max_block_num,

    -- deposit aggregates --
    sum(deposit_volume) AS deposit_volume,
    sum(deposit_count) AS deposit_count,

    -- withdrawal aggregates --
    sum(withdrawal_volume) AS withdrawal_volume,
    sum(withdrawal_finalized_volume) AS withdrawal_finalized_volume,
    sum(withdrawal_pending_volume) AS withdrawal_pending_volume,
    sum(withdrawal_count) AS withdrawal_count,
    sum(withdrawal_finalized_count) AS withdrawal_finalized_count,
    sum(withdrawal_pending_count) AS withdrawal_pending_count,

    -- net flow --
    sum(net_flow) AS net_flow,
    sum(gross_volume) AS gross_volume,

    -- unique counts --
    uniqMerge(uniq_depositor) AS uniq_depositor,
    uniqMerge(uniq_withdrawer) AS uniq_withdrawer,
    uniqMerge(uniq_user) AS uniq_user

FROM state_c_deposits_withdrawals
GROUP BY
    interval_min,
    timestamp;
