-- Cross-chain deposits/withdrawals state table --
-- Aggregates cross-chain deposit and withdrawal events for detecting arbitrage bot activity and fund flow patterns
CREATE TABLE IF NOT EXISTS state_c_deposits_withdrawals (
    -- bar interval --
    timestamp               DateTime('UTC') COMMENT 'beginning of the bar',
    interval_min            UInt16 DEFAULT 1 COMMENT 'bar interval in minutes (1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w)',

    -- timestamp & block number --
    min_timestamp           SimpleAggregateFunction(min, DateTime('UTC')) COMMENT 'first timestamp seen',
    max_timestamp           SimpleAggregateFunction(max, DateTime('UTC')) COMMENT 'last timestamp seen',
    min_block_num           SimpleAggregateFunction(min, UInt64) COMMENT 'first block number seen',
    max_block_num           SimpleAggregateFunction(max, UInt64) COMMENT 'last block number seen',

    -- deposit aggregates --
    deposit_volume          SimpleAggregateFunction(sum, Float64) COMMENT 'total deposit volume in the window',
    deposit_count           SimpleAggregateFunction(sum, UInt64) COMMENT 'number of deposits in the window',

    -- withdrawal aggregates --
    withdrawal_volume           SimpleAggregateFunction(sum, Float64) COMMENT 'total withdrawal volume in the window',
    withdrawal_finalized_volume SimpleAggregateFunction(sum, Float64) COMMENT 'total finalized withdrawal volume in the window',
    withdrawal_pending_volume   SimpleAggregateFunction(sum, Float64) COMMENT 'total pending withdrawal volume in the window',
    withdrawal_count            SimpleAggregateFunction(sum, UInt64) COMMENT 'number of withdrawals in the window',
    withdrawal_finalized_count  SimpleAggregateFunction(sum, UInt64) COMMENT 'number of finalized withdrawals in the window',
    withdrawal_pending_count    SimpleAggregateFunction(sum, UInt64) COMMENT 'number of pending withdrawals in the window',

    -- net flow --
    net_flow                SimpleAggregateFunction(sum, Float64) COMMENT 'net flow (deposits - withdrawals) in the window',
    gross_volume            SimpleAggregateFunction(sum, Float64) COMMENT 'total volume (deposits + withdrawals) in the window',

    -- unique counts --
    uniq_user               AggregateFunction(uniq, String) COMMENT 'unique user addresses (depositors + withdrawers) in the window',

    -- indexes --
    INDEX idx_timestamp         (timestamp)         TYPE minmax                 GRANULARITY 1,
    INDEX idx_gross_volume      (gross_volume)      TYPE minmax                 GRANULARITY 1,
    INDEX idx_net_flow          (net_flow)          TYPE minmax                 GRANULARITY 1,
    INDEX idx_deposit_count     (deposit_count)     TYPE minmax                 GRANULARITY 1,
    INDEX idx_withdrawal_count  (withdrawal_count)  TYPE minmax                 GRANULARITY 1
)
ENGINE = AggregatingMergeTree
ORDER BY (
    interval_min,
    timestamp
)
COMMENT 'Cross-chain deposits/withdrawals aggregated data for detecting arbitrage bot activity and fund flow patterns';

-- Materialized view to populate state_c_deposits_withdrawals from c_deposits table --
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_c_deposits_withdrawals_deposits
TO state_c_deposits_withdrawals
AS
WITH
    -- predefined intervals --
    -- in minutes: 1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w
    [1, 5, 10, 30, 60, 240, 1440, 10080] AS intervals,

    -- parse amount as Float64 for calculations
    toFloat64OrZero(amount) AS amount_f64

SELECT
    arrayJoin(intervals) AS interval_min,
    -- floor to the interval in seconds
    toDateTime(intDiv(toUInt32(d.timestamp), interval_min * 60) * interval_min * 60, 'UTC') AS timestamp,

    -- timestamp & block number --
    min(d.timestamp) AS min_timestamp,
    max(d.timestamp) AS max_timestamp,
    min(d.block_num) AS min_block_num,
    max(d.block_num) AS max_block_num,

    -- deposit aggregates --
    sum(amount_f64)                                         AS deposit_volume,
    count()                                                 AS deposit_count,

    -- withdrawal aggregates (zero for deposits) --
    toFloat64(0)                                            AS withdrawal_volume,
    toFloat64(0)                                            AS withdrawal_finalized_volume,
    toFloat64(0)                                            AS withdrawal_pending_volume,
    toUInt64(0)                                             AS withdrawal_count,
    toUInt64(0)                                             AS withdrawal_finalized_count,
    toUInt64(0)                                             AS withdrawal_pending_count,

    -- net flow (positive for deposits) --
    sum(amount_f64)                                         AS net_flow,
    sum(amount_f64)                                         AS gross_volume,

    -- unique counts --
    uniqState(d.user)                                       AS uniq_user

FROM c_deposits d
WHERE amount_f64 > 0
GROUP BY
    -- bar interval
    interval_min,
    -- bar beginning
    timestamp;

-- Materialized view to populate state_c_deposits_withdrawals from c_withdrawals table --
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_state_c_deposits_withdrawals_withdrawals
TO state_c_deposits_withdrawals
AS
WITH
    -- predefined intervals --
    -- in minutes: 1m, 5m, 10m, 30m, 1h, 4h, 1d, 1w
    [1, 5, 10, 30, 60, 240, 1440, 10080] AS intervals,

    -- parse amount as Float64 for calculations
    toFloat64OrZero(amount) AS amount_f64

SELECT
    arrayJoin(intervals) AS interval_min,
    -- floor to the interval in seconds
    toDateTime(intDiv(toUInt32(w.timestamp), interval_min * 60) * interval_min * 60, 'UTC') AS timestamp,

    -- timestamp & block number --
    min(w.timestamp) AS min_timestamp,
    max(w.timestamp) AS max_timestamp,
    min(w.block_num) AS min_block_num,
    max(w.block_num) AS max_block_num,

    -- deposit aggregates (zero for withdrawals) --
    toFloat64(0)                                            AS deposit_volume,
    toUInt64(0)                                             AS deposit_count,

    -- withdrawal aggregates --
    sum(amount_f64)                                         AS withdrawal_volume,
    sum(if(w.is_finalized, amount_f64, 0))                  AS withdrawal_finalized_volume,
    sum(if(NOT w.is_finalized, amount_f64, 0))              AS withdrawal_pending_volume,
    count()                                                 AS withdrawal_count,
    sum(if(w.is_finalized, 1, 0))                           AS withdrawal_finalized_count,
    sum(if(NOT w.is_finalized, 1, 0))                       AS withdrawal_pending_count,

    -- net flow (negative for withdrawals) --
    sum(-amount_f64)                                        AS net_flow,
    sum(amount_f64)                                         AS gross_volume,

    -- unique counts --
    uniqState(w.user)                                       AS uniq_user

FROM c_withdrawals w
WHERE amount_f64 > 0
GROUP BY
    -- bar interval
    interval_min,
    -- bar beginning
    timestamp;
