# substreams-hypercore

Substreams for indexing [Hypercore](https://www.hyperliquid.xyz/) blockchain data.

## Overview

This repository contains Substreams modules for extracting and processing Hypercore blockchain data, with support for ClickHouse as a sink database.

## Block Structure

A Hypercore `Block` contains:

```protobuf
message Block {
  BlockHeader block_header = 1;
  repeated Fill fills = 2;
  repeated Event events = 3;
}

message BlockHeader {
  uint64 block_number = 1;
  google.protobuf.Timestamp block_time = 2;
}
```

## Events Structure

### Event Wrapper

All events are wrapped in an `Event` message that contains metadata and a list of event bodies:

```protobuf
message Event {
  google.protobuf.Timestamp time = 1;
  bytes hash = 2;
  repeated EventBody events = 3;
}
```

### Event Types

The `EventBody` message uses a `oneof` to represent different event types:

| Event Type | Description | ClickHouse Table |
|------------|-------------|------------------|
| `Delegation` | Staking delegation/undelegation events | `delegations` |
| `CDeposit` | Cross-chain deposit events | `c_deposits` |
| `CWithdrawal` | Cross-chain withdrawal events | `c_withdrawals` |
| `Funding` | Funding rate events with deltas | `funding_deltas` |
| `ValidatorRewards` | Validator reward distributions | `validator_rewards` |
| `LedgerUpdate` | Account ledger changes (see below) | Various tables |

---

## Event Type Details

### Delegation

Represents staking delegation or undelegation events.

| Field | Type | Description |
|-------|------|-------------|
| `user` | `bytes` | User address performing the delegation |
| `validator` | `bytes` | Validator address |
| `amount` | `string` | Delegation amount |
| `is_undelegate` | `bool` | `true` if undelegating, `false` if delegating |

### CDeposit (Cross-chain Deposit)

Represents cross-chain deposit events.

| Field | Type | Description |
|-------|------|-------------|
| `user` | `bytes` | User address receiving the deposit |
| `amount` | `string` | Deposit amount |

### CWithdrawal (Cross-chain Withdrawal)

Represents cross-chain withdrawal events.

| Field | Type | Description |
|-------|------|-------------|
| `user` | `bytes` | User address initiating withdrawal |
| `amount` | `string` | Withdrawal amount |
| `is_finalized` | `bool` | Whether the withdrawal is finalized |

### Funding

Contains funding rate deltas for perpetual positions.

| Field | Type | Description |
|-------|------|-------------|
| `deltas` | `repeated FundingDelta` | List of funding deltas |

#### FundingDelta

| Field | Type | Description |
|-------|------|-------------|
| `user` | `bytes` | User address |
| `coin` | `string` | Trading pair/coin symbol |
| `funding_amount` | `string` | Funding payment amount |
| `szi` | `string` | Signed position size |
| `funding_rate` | `string` | Funding rate applied |

### ValidatorRewards

Contains validator reward distributions.

| Field | Type | Description |
|-------|------|-------------|
| `validator_to_reward` | `repeated ValidatorReward` | List of validator rewards |

#### ValidatorReward

| Field | Type | Description |
|-------|------|-------------|
| `validator` | `bytes` | Validator address |
| `reward` | `string` | Reward amount |

---

## Ledger Update Events

`LedgerUpdate` events represent changes to user account ledgers. Each update includes:

```protobuf
message LedgerUpdate {
  repeated bytes users = 1;
  LedgerUpdateDelta delta = 2;
}
```

### Ledger Update Delta Types

| Delta Type | Description | ClickHouse Table |
|------------|-------------|------------------|
| `SpotTransfer` | Spot token transfers | `ledger_spot_transfers` |
| `CStakingTransfer` | Cross-chain staking transfers | `ledger_c_staking_transfers` |
| `AccountClassTransfer` | Transfers between spot and perp accounts | `ledger_account_class_transfers` |
| `InternalTransfer` | Internal USDC transfers | `ledger_internal_transfers` |
| `SubAccountTransfer` | Sub-account USDC transfers | `ledger_sub_account_transfers` |
| `Send` | Cross-DEX token sends | `ledger_sends` |
| `Deposit` | USDC deposits | `ledger_deposits` |
| `Withdraw` | USDC withdrawals | `ledger_withdrawals` |
| `VaultDeposit` | Vault deposits | `ledger_vault_deposits` |
| `RewardsClaim` | Rewards claims | `ledger_rewards_claims` |
| `VaultWithdraw` | Vault withdrawals | `ledger_vault_withdrawals` |
| `VaultLeaderCommission` | Vault leader commission payments | `ledger_vault_leader_commissions` |
| `DeployGasAuction` | Gas auction deployments | `ledger_deploy_gas_auctions` |
| `AccountActivationGas` | Account activation gas fees | `ledger_account_activation_gas` |
| `ActivateDexAbstraction` | DEX abstraction activations | `ledger_activate_dex_abstractions` |
| `Liquidation` | Account liquidations | `ledger_liquidations` |
| `SpotGenesis` | Spot genesis token allocations | `ledger_spot_genesis` |
| `VaultDistribution` | Vault profit distributions | `ledger_vault_distributions` |
| `BorrowLend` | Borrow/lend operations | `ledger_borrow_lends` |
| `VaultCreate` | Vault creation events | `ledger_vault_creates` |

### Ledger Update Delta Details

#### SpotTransfer

| Field | Type | Description |
|-------|------|-------------|
| `token` | `string` | Token symbol |
| `amount` | `string` | Transfer amount |
| `usdc_value` | `string` | USDC equivalent value |
| `user` | `bytes` | Source user address |
| `destination` | `bytes` | Destination user address |
| `fee` | `string` | Transfer fee |
| `native_token_fee` | `string` | Fee in native token |
| `nonce` | `uint64` | Transaction nonce |
| `fee_token` | `string` | Token used for fee payment |

#### CStakingTransfer

| Field | Type | Description |
|-------|------|-------------|
| `token` | `string` | Token symbol |
| `amount` | `string` | Transfer amount |
| `is_deposit` | `bool` | `true` if deposit, `false` if withdrawal |

#### AccountClassTransfer

| Field | Type | Description |
|-------|------|-------------|
| `usdc` | `string` | USDC amount transferred |
| `to_perp` | `bool` | `true` if transferring to perp, `false` if to spot |

#### InternalTransfer

| Field | Type | Description |
|-------|------|-------------|
| `usdc` | `string` | USDC amount |
| `user` | `bytes` | Source user address |
| `destination` | `bytes` | Destination user address |
| `fee` | `string` | Transfer fee |

#### SubAccountTransfer

| Field | Type | Description |
|-------|------|-------------|
| `usdc` | `string` | USDC amount |
| `user` | `bytes` | Source user/sub-account address |
| `destination` | `bytes` | Destination user/sub-account address |

#### Send

| Field | Type | Description |
|-------|------|-------------|
| `user` | `bytes` | Source user address |
| `destination` | `bytes` | Destination user address |
| `source_dex` | `string` | Source DEX identifier |
| `destination_dex` | `string` | Destination DEX identifier |
| `token` | `string` | Token symbol |
| `amount` | `string` | Token amount |
| `usdc_value` | `string` | USDC equivalent value |
| `fee` | `string` | Transfer fee |
| `native_token_fee` | `string` | Fee in native token |
| `nonce` | `uint64` | Transaction nonce |
| `fee_token` | `string` | Token used for fee payment |

#### Deposit

| Field | Type | Description |
|-------|------|-------------|
| `usdc` | `string` | USDC deposit amount |

#### Withdraw

| Field | Type | Description |
|-------|------|-------------|
| `usdc` | `string` | USDC withdrawal amount |
| `nonce` | `uint64` | Withdrawal nonce |
| `fee` | `string` | Withdrawal fee |

#### VaultDeposit

| Field | Type | Description |
|-------|------|-------------|
| `vault` | `bytes` | Vault address |
| `usdc` | `string` | USDC deposit amount |

#### RewardsClaim

| Field | Type | Description |
|-------|------|-------------|
| `amount` | `string` | Claimed reward amount |
| `token` | `string` | Reward token symbol |

#### VaultWithdraw

| Field | Type | Description |
|-------|------|-------------|
| `vault` | `bytes` | Vault address |
| `user` | `bytes` | User withdrawing |
| `requested_usd` | `string` | Requested USD amount |
| `commission` | `string` | Commission charged |
| `closing_cost` | `string` | Position closing cost |
| `basis` | `string` | Cost basis |
| `net_withdrawn_usd` | `string` | Net withdrawn USD amount |

#### VaultLeaderCommission

| Field | Type | Description |
|-------|------|-------------|
| `user` | `bytes` | Vault leader address |
| `usdc` | `string` | Commission amount in USDC |

#### DeployGasAuction

| Field | Type | Description |
|-------|------|-------------|
| `token` | `string` | Token symbol |
| `amount` | `string` | Gas auction amount |

#### AccountActivationGas

| Field | Type | Description |
|-------|------|-------------|
| `amount` | `string` | Gas amount |
| `token` | `string` | Token symbol |

#### ActivateDexAbstraction

| Field | Type | Description |
|-------|------|-------------|
| `dex` | `string` | DEX identifier |
| `token` | `string` | Token symbol |
| `amount` | `string` | Amount for activation |

#### Liquidation

| Field | Type | Description |
|-------|------|-------------|
| `liquidated_ntl_pos` | `string` | Liquidated notional position value |
| `account_value` | `string` | Account value at liquidation |
| `leverage_type` | `LeverageType` | `CROSS` or `ISOLATED` |
| `liquidated_positions` | `repeated LiquidatedPosition` | List of liquidated positions |

##### LiquidatedPosition

| Field | Type | Description |
|-------|------|-------------|
| `coin` | `string` | Coin/trading pair |
| `szi` | `string` | Signed position size |

#### SpotGenesis

| Field | Type | Description |
|-------|------|-------------|
| `token` | `string` | Token symbol |
| `amount` | `string` | Genesis allocation amount |

#### VaultDistribution

| Field | Type | Description |
|-------|------|-------------|
| `vault` | `bytes` | Vault address |
| `usdc` | `string` | Distribution amount in USDC |

#### BorrowLend

| Field | Type | Description |
|-------|------|-------------|
| `token` | `string` | Token symbol |
| `amount` | `string` | Borrow/lend amount |
| `interest_amount` | `string` | Interest amount |
| `operation` | `string` | Operation type (borrow/repay/lend/withdraw) |

#### VaultCreate

| Field | Type | Description |
|-------|------|-------------|
| `vault` | `bytes` | New vault address |
| `usdc` | `string` | Initial USDC deposit |
| `fee` | `string` | Creation fee |

---

## Fill Events

Fills represent trade executions on Hypercore.

```protobuf
message Fill {
  bytes user = 1;
  string coin = 2;
  string price = 3;
  string size = 4;
  FillSide side = 5;
  google.protobuf.Timestamp time = 6;
  string start_position = 7;
  TradingDirection direction = 8;
  string closed_pnl = 9;
  bytes hash = 10;
  uint64 order_id = 11;
  bool crossed = 12;
  string fee = 13;
  uint64 transaction_id = 14;
  string fee_token = 15;
  uint64 twap_id = 16;
  bytes client_order_id = 17;
  FillLiquidation liquidation = 18;
  string deployer_fee = 19;
  string builder = 20;
  string builder_fee = 21;
  string priority_gas = 22;
}
```

### Fill Fields

| Field | Type | Description |
|-------|------|-------------|
| `user` | `bytes` | User address |
| `coin` | `string` | Trading pair (e.g., "BTC", "ETH") |
| `price` | `string` | Execution price |
| `size` | `string` | Fill size |
| `side` | `FillSide` | `ASK` or `BUY` |
| `time` | `Timestamp` | Fill timestamp |
| `start_position` | `string` | Position size before fill |
| `direction` | `TradingDirection` | Trading direction (see below) |
| `closed_pnl` | `string` | Realized PnL from closing position |
| `hash` | `bytes` | Transaction hash |
| `order_id` | `uint64` | Order identifier |
| `crossed` | `bool` | Whether the order crossed the spread |
| `fee` | `string` | Trading fee |
| `transaction_id` | `uint64` | Transaction identifier |
| `fee_token` | `string` | Token used for fee payment |
| `twap_id` | `uint64` | TWAP order identifier (0 if not TWAP) |
| `client_order_id` | `bytes` | Client-specified order ID |
| `liquidation` | `FillLiquidation` | Liquidation details (if applicable) |
| `deployer_fee` | `string` | HIP-3 deployer fee paid on this fill |
| `builder` | `string` | Builder code address (HIP-3 builder-deployed venues) |
| `builder_fee` | `string` | Builder fee paid on this fill |
| `priority_gas` | `string` | Priority gas paid for this fill |

### FillSide Enum

| Value | Description |
|-------|-------------|
| `FILL_SIDE_UNSPECIFIED` | Unknown side |
| `FILL_SIDE_ASK` | Sell side |
| `FILL_SIDE_BUY` | Buy side |

### TradingDirection Enum

| Value | Description |
|-------|-------------|
| `TRADING_DIRECTION_UNSPECIFIED` | Unknown direction |
| `TRADING_DIRECTION_BUY` | Spot buy |
| `TRADING_DIRECTION_SELL` | Spot sell |
| `TRADING_DIRECTION_OPEN_LONG` | Open long position |
| `TRADING_DIRECTION_CLOSE_LONG` | Close long position |
| `TRADING_DIRECTION_OPEN_SHORT` | Open short position |
| `TRADING_DIRECTION_CLOSE_SHORT` | Close short position |
| `TRADING_DIRECTION_LONG_TO_SHORT` | Flip from long to short |
| `TRADING_DIRECTION_SHORT_TO_LONG` | Flip from short to long |
| `TRADING_DIRECTION_SPOT_DUST_CONVERSION` | Dust conversion |
| `TRADING_DIRECTION_LIQUIDATED_CROSS_LONG` | Cross long liquidation |
| `TRADING_DIRECTION_LIQUIDATED_CROSS_SHORT` | Cross short liquidation |
| `TRADING_DIRECTION_LIQUIDATED_ISOLATED_LONG` | Isolated long liquidation |
| `TRADING_DIRECTION_LIQUIDATED_ISOLATED_SHORT` | Isolated short liquidation |
| `TRADING_DIRECTION_AUTO_DELEVERAGING` | Auto-deleveraging event |
| `TRADING_DIRECTION_SETTLEMENT` | Position settlement |
| `TRADING_DIRECTION_NET_CHILD_VAULTS` | Net child vault positions |
| `TRADING_DIRECTION_BACKSTOP_BORROW_LIQUIDATION` | Backstop borrow liquidation |
| `TRADING_DIRECTION_PARTIAL_BORROW_LIQUIDATION` | Partial borrow liquidation |
| `TRADING_DIRECTION_SPLIT_OUTCOME` | HIP-4 split: X collateral → X Yes + X No outcome shares (mint) |
| `TRADING_DIRECTION_MERGE_OUTCOME` | HIP-4 merge: X Yes + X No → X collateral (burn) |
| `TRADING_DIRECTION_MERGE_QUESTION` | HIP-4 question merge: X Yes of every leg → X collateral (multi-outcome) |
| `TRADING_DIRECTION_NEGATE_OUTCOME` | HIP-4 negate: X No of outcome A → X Yes of every sibling under same question |

HIP-4 directions (`SPLIT_OUTCOME`, `MERGE_OUTCOME`, `MERGE_QUESTION`, `NEGATE_OUTCOME`) are outcome-share composition operations on `#N` coins. As of **v0.4.0** these — along with all other fills on `#`-prefixed coins — are skipped here and processed by [substreams-hyperliquid-outcomes](https://github.com/pinax-network/substreams-hyperliquid-outcomes). `SETTLEMENT` still applies to non-outcome perp position settlements and remains recorded in this package's `fills` table; the `state_ohlcv_fills` and `state_user_by_coin` materialized views continue to exclude it (and the four HIP-4 directions, which never reach the table) so OHLCV bars and per-user volume aggregates reflect actual market activity.

### FillLiquidation

Present when the fill is part of a liquidation:

| Field | Type | Description |
|-------|------|-------------|
| `liquidated_user` | `bytes` | Address of liquidated user |
| `mark_px` | `string` | Mark price at liquidation |
| `method` | `string` | Liquidation method |

---

## ClickHouse Schema

The ClickHouse schema is organized in layers:

### Layer 0: Foundation

- `blocks` - Block metadata
- `TEMPLATE_EVENT` - Base template for all event tables

### Layer 1+: Event Tables

Each event type has its own table inheriting from `TEMPLATE_EVENT`, with projections for efficient querying by common fields like `user`, `validator`, `coin`, etc.

### Common Event Fields

All event tables share these base fields from `TEMPLATE_EVENT`:

| Field | Type | Description |
|-------|------|-------------|
| `block_num` | `UInt64` | Block number |
| `block_hash` | `String` | Block hash (hex with 0x prefix) |
| `timestamp` | `DateTime('UTC')` | Block timestamp |
| `minute` | `UInt32` | Relative minute number for partitioning |
| `event_index` | `UInt32` | Event index within the block |
| `event_hash` | `String` | Event/transaction hash (hex with 0x prefix) |
| `event_time` | `DateTime('UTC')` | Event-specific timestamp |

---

## Usage

### Building

```bash
cd clickhouse
make build
```

### Running with Substreams Sink

```bash
substreams-sink-sql run \
  clickhouse://<connection-string> \
  clickhouse/substreams.yaml \
  -e <hypercore-endpoint> \
  <start-block>:<stop-block>
```

## License

Apache-2.0
