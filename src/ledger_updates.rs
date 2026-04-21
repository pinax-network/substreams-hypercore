use proto::pb::pinax::hypercore::v1::{
    event_body, ledger_update_delta, AccountActivationGas, AccountClassTransfer,
    ActivateDexAbstraction, Block, BorrowLend, CStakingTransfer, DeployGasAuction, Deposit, Event,
    InternalTransfer, LedgerUpdate, LeverageType, Liquidation, RewardsClaim, Send, SpotGenesis,
    SpotTransfer, SubAccountTransfer, VaultCreate, VaultDeposit, VaultDistribution,
    VaultLeaderCommission, VaultWithdraw, Withdraw,
};
use substreams::pb::substreams::Clock;
use substreams::Hex;
use substreams_database_change::tables::Tables;

use crate::{event_key, set_event_metadata};

pub fn process_ledger_updates(tables: &mut Tables, clock: &Clock, block: &Block) {
    for (event_index, event) in block.events.iter().enumerate() {
        process_event_ledger_updates(tables, clock, event_index, event);
    }
}

fn process_event_ledger_updates(tables: &mut Tables, clock: &Clock, event_index: usize, event: &Event) {
    for (body_index, body) in event.events.iter().enumerate() {
        let combined_index = event_index * 1000 + body_index;
        if let Some(event_body::Event::LedgerUpdate(ledger_update)) = &body.event {
            process_ledger_update(tables, clock, combined_index, event, ledger_update);
        }
    }
}

fn process_ledger_update(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    ledger_update: &LedgerUpdate,
) {
    let users: Vec<String> = ledger_update
        .users
        .iter()
        .map(|u| format!("0x{}", Hex::encode(u)))
        .collect();

    if let Some(delta) = &ledger_update.delta {
        if let Some(ref d) = delta.delta {
            match d {
                ledger_update_delta::Delta::SpotTransfer(spot_transfer) => {
                    process_spot_transfer(tables, clock, event_index, event, &users, spot_transfer);
                }
                ledger_update_delta::Delta::CStakingTransfer(c_staking_transfer) => {
                    process_c_staking_transfer(tables, clock, event_index, event, &users, c_staking_transfer);
                }
                ledger_update_delta::Delta::AccountClassTransfer(account_class_transfer) => {
                    process_account_class_transfer(tables, clock, event_index, event, &users, account_class_transfer);
                }
                ledger_update_delta::Delta::InternalTransfer(internal_transfer) => {
                    process_internal_transfer(tables, clock, event_index, event, &users, internal_transfer);
                }
                ledger_update_delta::Delta::SubAccountTransfer(sub_account_transfer) => {
                    process_sub_account_transfer(tables, clock, event_index, event, &users, sub_account_transfer);
                }
                ledger_update_delta::Delta::Send(send) => {
                    process_send(tables, clock, event_index, event, &users, send);
                }
                ledger_update_delta::Delta::Deposit(deposit) => {
                    process_deposit(tables, clock, event_index, event, &users, deposit);
                }
                ledger_update_delta::Delta::Withdraw(withdraw) => {
                    process_withdraw(tables, clock, event_index, event, &users, withdraw);
                }
                ledger_update_delta::Delta::VaultDeposit(vault_deposit) => {
                    process_vault_deposit(tables, clock, event_index, event, &users, vault_deposit);
                }
                ledger_update_delta::Delta::RewardsClaim(rewards_claim) => {
                    process_rewards_claim(tables, clock, event_index, event, &users, rewards_claim);
                }
                ledger_update_delta::Delta::VaultWithdraw(vault_withdraw) => {
                    process_vault_withdraw(tables, clock, event_index, event, &users, vault_withdraw);
                }
                ledger_update_delta::Delta::VaultLeaderCommission(vault_leader_commission) => {
                    process_vault_leader_commission(tables, clock, event_index, event, &users, vault_leader_commission);
                }
                ledger_update_delta::Delta::DeployGasAuction(deploy_gas_auction) => {
                    process_deploy_gas_auction(tables, clock, event_index, event, &users, deploy_gas_auction);
                }
                ledger_update_delta::Delta::AccountActivationGas(account_activation_gas) => {
                    process_account_activation_gas(tables, clock, event_index, event, &users, account_activation_gas);
                }
                ledger_update_delta::Delta::ActivateDexAbstraction(activate_dex_abstraction) => {
                    process_activate_dex_abstraction(tables, clock, event_index, event, &users, activate_dex_abstraction);
                }
                ledger_update_delta::Delta::Liquidation(liquidation) => {
                    process_liquidation(tables, clock, event_index, event, &users, liquidation);
                }
                ledger_update_delta::Delta::SpotGenesis(spot_genesis) => {
                    process_spot_genesis(tables, clock, event_index, event, &users, spot_genesis);
                }
                ledger_update_delta::Delta::VaultDistribution(vault_distribution) => {
                    process_vault_distribution(tables, clock, event_index, event, &users, vault_distribution);
                }
                ledger_update_delta::Delta::BorrowLend(borrow_lend) => {
                    process_borrow_lend(tables, clock, event_index, event, &users, borrow_lend);
                }
                ledger_update_delta::Delta::VaultCreate(vault_create) => {
                    process_vault_create(tables, clock, event_index, event, &users, vault_create);
                }
            }
        }
    }
}

fn set_ledger_event_metadata(
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    row: &mut substreams_database_change::tables::Row,
) {
    set_event_metadata(clock, event_index, &event.hash, event.time.as_ref(), row);
    row.set("users", users.join(","));
}

fn process_spot_transfer(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    spot_transfer: &SpotTransfer,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_spot_transfers", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("token", &spot_transfer.token);
    row.set("amount", &spot_transfer.amount);
    row.set("usdc_value", &spot_transfer.usdc_value);
    row.set("user", format!("0x{}", Hex::encode(&spot_transfer.user)));
    row.set("destination", format!("0x{}", Hex::encode(&spot_transfer.destination)));
    row.set("fee", &spot_transfer.fee);
    row.set("native_token_fee", &spot_transfer.native_token_fee);
    row.set("nonce", spot_transfer.nonce);
    row.set("fee_token", &spot_transfer.fee_token);
}

fn process_c_staking_transfer(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    c_staking_transfer: &CStakingTransfer,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_c_staking_transfers", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("token", &c_staking_transfer.token);
    row.set("amount", &c_staking_transfer.amount);
    row.set("is_deposit", c_staking_transfer.is_deposit);
}

fn process_account_class_transfer(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    account_class_transfer: &AccountClassTransfer,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_account_class_transfers", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("usdc", &account_class_transfer.usdc);
    row.set("to_perp", account_class_transfer.to_perp);
}

fn process_internal_transfer(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    internal_transfer: &InternalTransfer,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_internal_transfers", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("usdc", &internal_transfer.usdc);
    row.set("user", format!("0x{}", Hex::encode(&internal_transfer.user)));
    row.set("destination", format!("0x{}", Hex::encode(&internal_transfer.destination)));
    row.set("fee", &internal_transfer.fee);
}

fn process_sub_account_transfer(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    sub_account_transfer: &SubAccountTransfer,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_sub_account_transfers", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("usdc", &sub_account_transfer.usdc);
    row.set("user", format!("0x{}", Hex::encode(&sub_account_transfer.user)));
    row.set("destination", format!("0x{}", Hex::encode(&sub_account_transfer.destination)));
}

fn process_send(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    send: &Send,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_sends", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("user", format!("0x{}", Hex::encode(&send.user)));
    row.set("destination", format!("0x{}", Hex::encode(&send.destination)));
    row.set("source_dex", &send.source_dex);
    row.set("destination_dex", &send.destination_dex);
    row.set("token", &send.token);
    row.set("amount", &send.amount);
    row.set("usdc_value", &send.usdc_value);
    row.set("fee", &send.fee);
    row.set("native_token_fee", &send.native_token_fee);
    row.set("nonce", send.nonce);
    row.set("fee_token", &send.fee_token);
}

fn process_deposit(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    deposit: &Deposit,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_deposits", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("usdc", &deposit.usdc);
}

fn process_withdraw(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    withdraw: &Withdraw,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_withdrawals", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("usdc", &withdraw.usdc);
    row.set("nonce", withdraw.nonce);
    row.set("fee", &withdraw.fee);
}

fn process_vault_deposit(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    vault_deposit: &VaultDeposit,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_vault_deposits", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("vault", format!("0x{}", Hex::encode(&vault_deposit.vault)));
    row.set("usdc", &vault_deposit.usdc);
}

fn process_rewards_claim(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    rewards_claim: &RewardsClaim,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_rewards_claims", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("amount", &rewards_claim.amount);
    row.set("token", &rewards_claim.token);
}

fn process_vault_withdraw(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    vault_withdraw: &VaultWithdraw,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_vault_withdrawals", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("vault", format!("0x{}", Hex::encode(&vault_withdraw.vault)));
    row.set("user", format!("0x{}", Hex::encode(&vault_withdraw.user)));
    row.set("requested_usd", &vault_withdraw.requested_usd);
    row.set("commission", &vault_withdraw.commission);
    row.set("closing_cost", &vault_withdraw.closing_cost);
    row.set("basis", &vault_withdraw.basis);
    row.set("net_withdrawn_usd", &vault_withdraw.net_withdrawn_usd);
}

fn process_vault_leader_commission(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    vault_leader_commission: &VaultLeaderCommission,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_vault_leader_commissions", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("user", format!("0x{}", Hex::encode(&vault_leader_commission.user)));
    row.set("usdc", &vault_leader_commission.usdc);
}

fn process_deploy_gas_auction(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    deploy_gas_auction: &DeployGasAuction,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_deploy_gas_auctions", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("token", &deploy_gas_auction.token);
    row.set("amount", &deploy_gas_auction.amount);
}

fn process_account_activation_gas(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    account_activation_gas: &AccountActivationGas,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_account_activation_gas", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("amount", &account_activation_gas.amount);
    row.set("token", &account_activation_gas.token);
}

fn process_activate_dex_abstraction(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    activate_dex_abstraction: &ActivateDexAbstraction,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_activate_dex_abstractions", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("dex", &activate_dex_abstraction.dex);
    row.set("token", &activate_dex_abstraction.token);
    row.set("amount", &activate_dex_abstraction.amount);
}

fn process_liquidation(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    liquidation: &Liquidation,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_liquidations", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("liquidated_ntl_pos", &liquidation.liquidated_ntl_pos);
    row.set("account_value", &liquidation.account_value);
    row.set("leverage_type", leverage_type_to_string(liquidation.leverage_type));

    // Serialize liquidated positions as JSON
    let positions_json: Vec<String> = liquidation
        .liquidated_positions
        .iter()
        .map(|p| format!(r#"{{"coin":"{}","szi":"{}"}}"#, p.coin, p.szi))
        .collect();
    row.set("liquidated_positions", format!("[{}]", positions_json.join(",")));
}

fn leverage_type_to_string(leverage_type: i32) -> &'static str {
    match LeverageType::try_from(leverage_type) {
        Ok(LeverageType::Cross) => "CROSS",
        Ok(LeverageType::Isolated) => "ISOLATED",
        _ => "UNSPECIFIED",
    }
}

fn process_spot_genesis(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    spot_genesis: &SpotGenesis,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_spot_genesis", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("token", &spot_genesis.token);
    row.set("amount", &spot_genesis.amount);
}

fn process_vault_distribution(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    vault_distribution: &VaultDistribution,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_vault_distributions", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("vault", format!("0x{}", Hex::encode(&vault_distribution.vault)));
    row.set("usdc", &vault_distribution.usdc);
}

fn process_borrow_lend(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    borrow_lend: &BorrowLend,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_borrow_lends", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("token", &borrow_lend.token);
    row.set("amount", &borrow_lend.amount);
    row.set("interest_amount", &borrow_lend.interest_amount);
    row.set("operation", &borrow_lend.operation);
}

fn process_vault_create(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    users: &[String],
    vault_create: &VaultCreate,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("ledger_vault_creates", key);

    set_ledger_event_metadata(clock, event_index, event, users, row);

    row.set("vault", format!("0x{}", Hex::encode(&vault_create.vault)));
    row.set("usdc", &vault_create.usdc);
    row.set("fee", &vault_create.fee);
}
