# Clickhouse Polymarket

This directory contains the ClickHouse schema for ingesting Polymarket event data from Substreams.

## Schema Structure

The schema is organized into layers, with numbered prefixes indicating the dependency order:

### Layer 0: Foundation (`schema.0.*`)

- **`schema.0.blocks.sql`** - Block metadata table
- **`schema.0.templates.sql`** - Template tables for transactions and logs that other tables inherit from

### Layer 1: Event Tables (`schema.1.*`)

Event-specific tables that extend the template tables:

- **`schema.1.conditional_tokens.sql`** - ConditionalTokens contract events (ConditionPreparation, ConditionResolution, PositionSplit, PositionsMerge, PayoutRedemption)
- **`schema.1.ctf_exchange.sql`** - CTFExchange contract events (OrderFilled, OrdersMatched, FeeCharged, etc.)
- **`schema.1.fee_module.sql`** - FeeModule contract events
- **`schema.1.negrisk_adapter.sql`** - NegRiskAdapter contract events
- **`schema.1.safe_proxy_factory.sql`** - SafeProxyFactory contract events
- **`schema.1.uma_ctf_adapter.sql`** - UmaCtfAdapter contract events

### Layer 2: Materialized Views (`schema.2.mv.*`)

AggregatingMergeTree tables with materialized views for real-time aggregation:

- **`schema.2.mv.state_open_interest.sql`** - Open interest aggregated by condition and time interval
- **`schema.2.mv.state_orderbook.sql`** - Order book metrics aggregated by asset and time interval
- **`schema.2.mv.state_user_condition_position.sql`** - User positions by condition (from splits/merges/redemptions)
- **`schema.2.mv.state_user_position.sql`** - User positions by token (from exchange trades)

### Layer 3: Views (`schema.3.view.*`)

Convenience views that query the aggregated state tables:

- **`schema.3.view.open_interest.sql`** - Open interest views (per-condition and global)
- **`schema.3.view.orderbook.sql`** - Order book views (per-asset and global)
- **`schema.3.view.user_condition_position.sql`** - User condition position views
- **`schema.3.view.user_position.sql`** - User position views with PNL calculations

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

## USDC Decimals

USDC has 6 decimals. The views provide both raw amounts (in base units) and scaled amounts (divided by 10^6) for convenience.
