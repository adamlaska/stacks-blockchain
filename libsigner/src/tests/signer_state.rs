// Copyright (C) 2020-2025 Stacks Open Internet Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
use std::collections::HashMap;

use blockstack_lib::chainstate::stacks::{
    StacksTransaction, TokenTransferMemo, TransactionAnchorMode, TransactionAuth,
    TransactionPayload, TransactionPostConditionMode, TransactionVersion,
};
use clarity::types::chainstate::{
    ConsensusHash, StacksAddress, StacksBlockId, StacksPrivateKey, StacksPublicKey,
};
use clarity::util::hash::Hash160;

use crate::v0::messages::{
    StateMachineUpdate as StateMachineUpdateMessage, StateMachineUpdateContent,
    StateMachineUpdateMinerState,
};
use crate::v0::signer_state::{GlobalStateEvaluator, ReplayTransactionSet, SignerStateMachine};

fn generate_global_state_evaluator(num_addresses: u32) -> GlobalStateEvaluator {
    let address_weights = generate_random_address_with_equal_weights(num_addresses);
    let active_protocol_version = 0;
    let local_supported_signer_protocol_version = 1;

    let update = StateMachineUpdateMessage::new(
        active_protocol_version,
        local_supported_signer_protocol_version,
        StateMachineUpdateContent::V0 {
            burn_block: ConsensusHash([0x55; 20]),
            burn_block_height: 100,
            current_miner: StateMachineUpdateMinerState::ActiveMiner {
                current_miner_pkh: Hash160([0xab; 20]),
                tenure_id: ConsensusHash([0x44; 20]),
                parent_tenure_id: ConsensusHash([0x22; 20]),
                parent_tenure_last_block: StacksBlockId([0x33; 32]),
                parent_tenure_last_block_height: 1,
            },
        },
    )
    .unwrap();

    let mut address_updates = HashMap::new();
    for address in address_weights.keys() {
        address_updates.insert(*address, update.clone());
    }
    GlobalStateEvaluator::new(address_updates, address_weights)
}

fn generate_random_address_with_equal_weights(num_addresses: u32) -> HashMap<StacksAddress, u32> {
    let mut address_weights = HashMap::new();
    for _ in 0..num_addresses {
        let stacks_address = StacksAddress::p2pkh(false, &StacksPublicKey::new());
        address_weights.insert(stacks_address, 10);
    }
    address_weights
}

#[test]
fn determine_latest_supported_signer_protocol_versions() {
    let mut global_eval = generate_global_state_evaluator(5);

    let addresses: Vec<_> = global_eval.address_weights.keys().cloned().collect();
    let local_address = addresses[0];

    let local_update = global_eval
        .address_updates
        .get(&local_address)
        .unwrap()
        .clone();
    assert_eq!(
        global_eval
            .determine_latest_supported_signer_protocol_version()
            .unwrap(),
        local_update.local_supported_signer_protocol_version
    );

    let StateMachineUpdateMessage {
        active_signer_protocol_version,
        local_supported_signer_protocol_version,
        content:
            StateMachineUpdateContent::V0 {
                burn_block,
                burn_block_height,
                current_miner,
            },
        ..
    } = local_update.clone()
    else {
        panic!("Unexpected state machine update message version");
    };

    // Let's update 3 signers (60 percent) to support seperate but greater protocol versions
    for (i, address) in addresses.into_iter().skip(1).take(3).enumerate() {
        let new_version = local_update.local_supported_signer_protocol_version + i as u64 + 1;
        let new_update = StateMachineUpdateMessage::new(
            active_signer_protocol_version,
            new_version,
            StateMachineUpdateContent::V0 {
                burn_block,
                burn_block_height,
                current_miner: current_miner.clone(),
            },
        )
        .unwrap();
        global_eval.insert_update(address, new_update);
    }

    assert_eq!(
        global_eval
            .determine_latest_supported_signer_protocol_version()
            .unwrap(),
        local_supported_signer_protocol_version
    );

    // Let's tip the scales over to version number 2 by updating the local signer's version...
    // i.e. > 70% will have version 2 or higher in their map
    let local_update = StateMachineUpdateMessage::new(
        active_signer_protocol_version,
        3,
        StateMachineUpdateContent::V0 {
            burn_block,
            burn_block_height,
            current_miner,
        },
    )
    .unwrap();

    global_eval.insert_update(local_address, local_update);

    assert_eq!(
        global_eval
            .determine_latest_supported_signer_protocol_version()
            .unwrap(),
        local_supported_signer_protocol_version + 1
    );
}

#[test]
fn determine_global_burn_views() {
    let mut global_eval = generate_global_state_evaluator(5);

    let addresses: Vec<_> = global_eval.address_weights.keys().cloned().collect();
    let local_address = addresses[0];
    let local_update = global_eval
        .address_updates
        .get(&local_address)
        .unwrap()
        .clone();
    let StateMachineUpdateMessage {
        active_signer_protocol_version,
        local_supported_signer_protocol_version,
        content:
            StateMachineUpdateContent::V0 {
                burn_block,
                burn_block_height,
                current_miner,
            },
        ..
    } = local_update.clone()
    else {
        panic!("Unexpected state machine update message version");
    };

    assert_eq!(
        global_eval.determine_global_burn_view().unwrap(),
        (burn_block, burn_block_height)
    );

    // Let's update 3 signers (60 percent) to support a new burn block view
    let new_update = StateMachineUpdateMessage::new(
        active_signer_protocol_version,
        local_supported_signer_protocol_version,
        StateMachineUpdateContent::V0 {
            burn_block,
            burn_block_height: burn_block_height.wrapping_add(1),
            current_miner: current_miner.clone(),
        },
    )
    .unwrap();
    for address in addresses.into_iter().skip(1).take(3) {
        global_eval.insert_update(address, new_update.clone());
    }

    assert!(
        global_eval.determine_global_burn_view().is_none(),
        "We should not have reached agreement on the burn block height"
    );

    // Let's tip the scales over to burn block height + 1
    global_eval.insert_update(local_address, new_update);
    assert_eq!(
        global_eval.determine_global_burn_view().unwrap(),
        (burn_block, burn_block_height.wrapping_add(1))
    );
}

#[test]
fn determine_global_states() {
    let mut global_eval = generate_global_state_evaluator(5);

    let addresses: Vec<_> = global_eval.address_weights.keys().cloned().collect();
    let local_address = addresses[0];
    let local_update = global_eval
        .address_updates
        .get(&local_address)
        .unwrap()
        .clone();
    let StateMachineUpdateMessage {
        active_signer_protocol_version,
        local_supported_signer_protocol_version,
        content:
            StateMachineUpdateContent::V0 {
                burn_block,
                burn_block_height,
                current_miner,
            },
        ..
    } = local_update.clone()
    else {
        panic!("Unexpected state machine update message version");
    };

    let state_machine = SignerStateMachine {
        burn_block,
        burn_block_height,
        current_miner: (&current_miner).into(),
        active_signer_protocol_version: local_supported_signer_protocol_version, // a majority of signers are saying they support version the same local_supported_signer_protocol_version, so update it here...
        tx_replay_set: ReplayTransactionSet::none(),
    };

    global_eval.insert_update(local_address, local_update);
    assert_eq!(global_eval.determine_global_state().unwrap(), state_machine);
    let new_miner = StateMachineUpdateMinerState::ActiveMiner {
        current_miner_pkh: Hash160([0x00; 20]),
        tenure_id: ConsensusHash([0x44; 20]),
        parent_tenure_id: ConsensusHash([0x22; 20]),
        parent_tenure_last_block: StacksBlockId([0x33; 32]),
        parent_tenure_last_block_height: 1,
    };

    let new_update = StateMachineUpdateMessage::new(
        active_signer_protocol_version,
        local_supported_signer_protocol_version,
        StateMachineUpdateContent::V0 {
            burn_block,
            burn_block_height,
            current_miner: new_miner.clone(),
        },
    )
    .unwrap();

    // Let's update 3 signers to some new miner key (60 percent)
    for address in addresses.into_iter().skip(1).take(3) {
        global_eval.insert_update(address, new_update.clone());
    }

    assert!(
        global_eval.determine_global_state().is_none(),
        "We should have a disagreement about the current miner"
    );

    let state_machine = SignerStateMachine {
        burn_block,
        burn_block_height,
        current_miner: (&new_miner).into(),
        active_signer_protocol_version: local_supported_signer_protocol_version, // a majority of signers are saying they support version the same local_supported_signer_protocol_version, so update it here...
        tx_replay_set: ReplayTransactionSet::none(),
    };

    global_eval.insert_update(local_address, new_update);
    // Let's tip the scales over to a different miner
    assert_eq!(global_eval.determine_global_state().unwrap(), state_machine)
}

#[test]
fn determine_global_states_with_tx_replay_set() {
    let mut global_eval = generate_global_state_evaluator(5);

    let addresses: Vec<_> = global_eval.address_weights.keys().cloned().collect();
    let local_address = addresses[0];
    let local_update = global_eval
        .address_updates
        .get(&local_address)
        .unwrap()
        .clone();
    let StateMachineUpdateMessage {
        content:
            StateMachineUpdateContent::V0 {
                burn_block,
                burn_block_height,
                current_miner,
            },
        ..
    } = local_update.clone()
    else {
        panic!("Unexpected state machine update message version");
    };

    let local_supported_signer_protocol_version = 1;
    let active_signer_protocol_version = 1;

    let state_machine = SignerStateMachine {
        burn_block,
        burn_block_height,
        current_miner: (&current_miner).into(),
        active_signer_protocol_version, // a majority of signers are saying they support version the same local_supported_signer_protocol_version, so update it here...
        tx_replay_set: ReplayTransactionSet::none(),
    };

    let burn_block = ConsensusHash([20u8; 20]);
    let burn_block_height = burn_block_height + 1;
    assert_eq!(global_eval.determine_global_state().unwrap(), state_machine);

    let no_tx_replay_set_update = StateMachineUpdateMessage::new(
        active_signer_protocol_version,
        local_supported_signer_protocol_version,
        StateMachineUpdateContent::V1 {
            burn_block: ConsensusHash([20u8; 20]),
            burn_block_height,
            current_miner: current_miner.clone(),
            replay_transactions: vec![],
        },
    )
    .unwrap();

    // Let's update 3 signers to some new tx_replay_set but one that has no txs in it
    for address in addresses.iter().skip(1).take(3) {
        global_eval.insert_update(*address, no_tx_replay_set_update.clone());
    }

    // we have disagreement about the burn block height
    assert!(
        global_eval.determine_global_state().is_none(),
        "We should have disagreement about the burn view"
    );

    global_eval.insert_update(local_address, no_tx_replay_set_update.clone());

    let new_burn_view_state_machine = SignerStateMachine {
        burn_block,
        burn_block_height,
        current_miner: (&current_miner).into(),
        active_signer_protocol_version: local_supported_signer_protocol_version, // a majority of signers are saying they support version the same local_supported_signer_protocol_version, so update it here...
        tx_replay_set: ReplayTransactionSet::none(),
    };

    // Let's tip the scales over to the correct burn view
    global_eval.insert_update(local_address, no_tx_replay_set_update);
    assert_eq!(
        global_eval.determine_global_state().unwrap(),
        new_burn_view_state_machine
    );

    let pk = StacksPrivateKey::random();
    let tx = StacksTransaction {
        version: TransactionVersion::Testnet,
        chain_id: 0x80000000,
        auth: TransactionAuth::from_p2pkh(&pk).unwrap(),
        anchor_mode: TransactionAnchorMode::Any,
        post_condition_mode: TransactionPostConditionMode::Allow,
        post_conditions: vec![],
        payload: TransactionPayload::TokenTransfer(
            local_address.into(),
            123,
            TokenTransferMemo([0u8; 34]),
        ),
    };

    let tx_replay_set_update = StateMachineUpdateMessage::new(
        active_signer_protocol_version,
        local_supported_signer_protocol_version,
        StateMachineUpdateContent::V1 {
            burn_block,
            burn_block_height,
            current_miner: current_miner.clone(),
            replay_transactions: vec![tx.clone()],
        },
    )
    .unwrap();

    // Let's update 3 signers to some new non empty replay set
    for address in addresses.into_iter().skip(1).take(3) {
        global_eval.insert_update(address, tx_replay_set_update.clone());
    }

    // We still have a valid view but with no global tx set so we aren't blocked entirely but also aren't enforcing the tx replays set
    assert_eq!(
        global_eval.determine_global_state().unwrap(),
        new_burn_view_state_machine
    );

    // Let's tip the scales over to require a tx replay set
    global_eval.insert_update(local_address, tx_replay_set_update.clone());

    let tx_replay_state_machine = SignerStateMachine {
        burn_block,
        burn_block_height,
        current_miner: (&current_miner).into(),
        active_signer_protocol_version,
        tx_replay_set: ReplayTransactionSet::new(vec![tx]),
    };

    assert_eq!(
        global_eval.determine_global_state().unwrap(),
        tx_replay_state_machine
    );
}
