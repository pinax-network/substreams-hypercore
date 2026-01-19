# Clickhouse Hypercore

This directory contains the ClickHouse schema for ingesting Hypercore blockchain data from Substreams.

## Schema Structure

The schema is organized into layers, with numbered prefixes indicating the dependency order:

### Layer 0: Foundation (`schema.0.*`)

- **`schema.0.blocks.sql`** - Block metadata table
- **`schema.0.templates.sql`** - Template tables for event data that other tables inherit from

### Layer 1: Event Tables (`schema.1.*`)

Event-specific tables that extend the template tables:

- **`schema.1.fills.sql`** - Trade fill events with minute & count projections for analytics
- **`schema.1.c_deposits_withdrawals.sql`** - Cross-chain deposit and withdrawal events
- **`schema.1.delegations.sql`** - Staking delegation/undelegation events
- **`schema.1.funding.sql`** - Funding rate delta events
- **`schema.1.ledger_updates.sql`** - Various ledger update events (transfers, deposits, withdrawals, etc.)
- **`schema.1.validator_rewards.sql`** - Validator reward distribution events

### Layer 2: Materialized Views (`schema.2.mv.*`)

AggregatingMergeTree tables with materialized views for real-time aggregation:

- **`schema.2.mv.state_ohlcv_fills.sql`** - OHLCV (Open, High, Low, Close, Volume) candlestick data aggregated from fills

### Layer 3: Views (`schema.3.view.*`)

Convenience views that query the aggregated state tables:

- **`schema.3.view.ohlcv_fills.sql`** - OHLCV view for querying candlestick data with merged aggregates

## Time Intervals

The materialized views aggregate data at multiple time intervals:
- 1 minute (1m)
- 5 minutes (5m)
- 10 minutes (10m)
- 30 minutes (30m)
- 1 hour (60m)
- 4 hours (240m)
- 1 day (1440m)
- 1 week (10080m)

## Fills Projections

The fills table includes specialized projections for analytics:

### Count Projections
Aggregate counts with min/max block and timestamp ranges:
- `prj_coin_count` - Counts by trading pair
- `prj_user_count` - Counts by user
- `prj_side_count` - Counts by buy/sell side
- `prj_direction_count` - Counts by trading direction

### Minute Projections
Counts grouped by minute for time-series analysis:
- `prj_coin_by_minute` - Fills per coin per minute
- `prj_user_by_minute` - Fills per user per minute
- `prj_side_by_minute` - Fills per side per minute
- `prj_direction_by_minute` - Fills per direction per minute
- `prj_all_by_minute` - Combined grouping by coin, side, direction, and minute
