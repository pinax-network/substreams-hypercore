use crate::pb::pinax::hypercore::v1::{
    event_body, Block, CDeposit, CWithdrawal, Delegation, Event, Funding, FundingDelta,
    ValidatorReward, ValidatorRewards,
};
use substreams::pb::substreams::Clock;
use substreams::Hex;
use substreams_database_change::tables::Tables;

use crate::{event_key, parse_f64, set_event_metadata};

pub fn process_events(tables: &mut Tables, clock: &Clock, block: &Block) {
    for (event_index, event) in block.events.iter().enumerate() {
        process_event(tables, clock, event_index, event);
    }
}

fn process_event(tables: &mut Tables, clock: &Clock, event_index: usize, event: &Event) {
    for (body_index, body) in event.events.iter().enumerate() {
        let combined_index = event_index * 1000 + body_index; // Create unique index
        if let Some(ref evt) = body.event {
            match evt {
                event_body::Event::Delegation(delegation) => {
                    process_delegation(tables, clock, combined_index, event, delegation);
                }
                event_body::Event::CDeposit(c_deposit) => {
                    process_c_deposit(tables, clock, combined_index, event, c_deposit);
                }
                event_body::Event::CWithdrawal(c_withdrawal) => {
                    process_c_withdrawal(tables, clock, combined_index, event, c_withdrawal);
                }
                event_body::Event::Funding(funding) => {
                    process_funding(tables, clock, combined_index, event, funding);
                }
                event_body::Event::ValidatorRewards(validator_rewards) => {
                    process_validator_rewards(tables, clock, combined_index, event, validator_rewards);
                }
                event_body::Event::LedgerUpdate(_) => {
                    // LedgerUpdate is handled by ledger_updates module
                }
            }
        }
    }
}

fn process_delegation(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    delegation: &Delegation,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("delegations", key);

    set_event_metadata(clock, event_index, &event.hash, event.time.as_ref(), row);

    row.set("user", format!("0x{}", Hex::encode(&delegation.user)));
    row.set("validator", format!("0x{}", Hex::encode(&delegation.validator)));
    row.set("amount", &delegation.amount);
    row.set("is_undelegate", delegation.is_undelegate);
}

fn process_c_deposit(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    c_deposit: &CDeposit,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("c_deposits", key);

    set_event_metadata(clock, event_index, &event.hash, event.time.as_ref(), row);

    // Parse amount as f64 (default to 0.0 if parsing fails)
    let amount = parse_f64(&c_deposit.amount);

    row.set("user", format!("0x{}", Hex::encode(&c_deposit.user)));
    row.set("amount", amount.to_string());
}

fn process_c_withdrawal(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    c_withdrawal: &CWithdrawal,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("c_withdrawals", key);

    set_event_metadata(clock, event_index, &event.hash, event.time.as_ref(), row);

    // Parse amount as f64 (default to 0.0 if parsing fails)
    let amount = parse_f64(&c_withdrawal.amount);

    row.set("user", format!("0x{}", Hex::encode(&c_withdrawal.user)));
    row.set("amount", amount.to_string());
    row.set("is_finalized", c_withdrawal.is_finalized);
}

fn process_funding(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    funding: &Funding,
) {
    for (delta_index, delta) in funding.deltas.iter().enumerate() {
        let combined_index = event_index * 1000 + delta_index;
        process_funding_delta(tables, clock, combined_index, event, delta);
    }
}

fn process_funding_delta(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    delta: &FundingDelta,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("funding_deltas", key);

    set_event_metadata(clock, event_index, &event.hash, event.time.as_ref(), row);

    // Parse funding amounts as f64 (default to 0.0 if parsing fails)
    let funding_amount = parse_f64(&delta.funding_amount);
    let szi = parse_f64(&delta.szi);
    let funding_rate = parse_f64(&delta.funding_rate);

    row.set("user", format!("0x{}", Hex::encode(&delta.user)));
    row.set("coin", &delta.coin);
    row.set("funding_amount", funding_amount.to_string());
    row.set("szi", szi.to_string());
    row.set("funding_rate", funding_rate.to_string());
}

fn process_validator_rewards(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    validator_rewards: &ValidatorRewards,
) {
    for (reward_index, reward) in validator_rewards.validator_to_reward.iter().enumerate() {
        let combined_index = event_index * 1000 + reward_index;
        process_validator_reward(tables, clock, combined_index, event, reward);
    }
}

fn process_validator_reward(
    tables: &mut Tables,
    clock: &Clock,
    event_index: usize,
    event: &Event,
    reward: &ValidatorReward,
) {
    let key = event_key(clock, event_index, &event.hash);
    let row = tables.create_row("validator_rewards", key);

    set_event_metadata(clock, event_index, &event.hash, event.time.as_ref(), row);

    row.set("validator", format!("0x{}", Hex::encode(&reward.validator)));
    row.set("reward", &reward.reward);
}
