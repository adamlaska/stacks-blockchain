// Copyright (C) 2013-2020 Blockstack PBC, a public benefit corporation
// Copyright (C) 2020-2023 Stacks Open Internet Foundation
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

use std::net::{IpAddr, Ipv4Addr, SocketAddr};

use stacks_common::codec::StacksMessageCodec;
use stacks_common::types::chainstate::{ConsensusHash, StacksBlockId, StacksPrivateKey};
use stacks_common::types::StacksEpochId;

use super::TestRPC;
use crate::chainstate::stacks::db::blocks::test::*;
use crate::chainstate::stacks::db::test::instantiate_chainstate;
use crate::chainstate::stacks::test::make_codec_test_block;
use crate::chainstate::stacks::{StacksBlockHeader, StacksMicroblock};
use crate::net::api::getmicroblocks_indexed::StacksIndexedMicroblockStream;
use crate::net::api::*;
use crate::net::connection::ConnectionOptions;
use crate::net::http::HttpChunkGenerator;
use crate::net::httpcore::{RPCRequestHandler, StacksHttp, StacksHttpRequest};
use crate::net::ProtocolFamily;

#[test]
fn test_try_parse_request() {
    let addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 33333);
    let mut http = StacksHttp::new(addr.clone(), &ConnectionOptions::default());

    let request =
        StacksHttpRequest::new_getmicroblocks_indexed(addr.into(), StacksBlockId([0x22; 32]));
    let bytes = request.try_serialize().unwrap();

    debug!("Request:\n{}\n", std::str::from_utf8(&bytes).unwrap());

    let (parsed_preamble, offset) = http.read_preamble(&bytes).unwrap();
    let mut handler = getmicroblocks_indexed::RPCMicroblocksIndexedRequestHandler::new();
    let mut parsed_request = http
        .handle_try_parse_request(
            &mut handler,
            &parsed_preamble.expect_request(),
            &bytes[offset..],
        )
        .unwrap();

    // consumed path args and body
    assert_eq!(handler.tail_microblock_id, Some(StacksBlockId([0x22; 32])));

    // parsed request consumes headers that would not be in a constructed reqeuest
    parsed_request.clear_headers();
    let (preamble, contents) = parsed_request.destruct();

    assert_eq!(&preamble, request.preamble());

    handler.restart();
    assert!(handler.tail_microblock_id.is_none());
}

#[test]
fn test_try_make_response() {
    let addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::new(127, 0, 0, 1)), 33333);

    let mut rpc_test = TestRPC::setup(function_name!());

    // store an additional block and microblock stream, so we can fetch it.
    let privk = StacksPrivateKey::from_hex(
        "eb05c83546fdd2c79f10f5ad5434a90dd28f7e3acb7c092157aa1bc3656b012c01",
    )
    .unwrap();
    let parent_block = make_codec_test_block(25, StacksEpochId::latest());
    let parent_consensus_hash = ConsensusHash([0x02; 20]);
    let parent_index_block_hash = StacksBlockHeader::make_index_block_hash(
        &parent_consensus_hash,
        &parent_block.block_hash(),
    );

    let mut mblocks = make_sample_microblock_stream(&privk, &parent_block.block_hash());
    mblocks.truncate(15);

    let mut child_block = make_codec_test_block(25, StacksEpochId::latest());
    let child_consensus_hash = ConsensusHash([0x03; 20]);

    child_block.header.parent_block = parent_block.block_hash();
    child_block.header.parent_microblock = mblocks.last().as_ref().unwrap().block_hash();
    child_block.header.parent_microblock_sequence =
        mblocks.last().as_ref().unwrap().header.sequence;

    store_staging_block(
        rpc_test.peer_2.chainstate(),
        &parent_consensus_hash,
        &parent_block,
        &ConsensusHash([0x01; 20]),
        456,
        123,
    );
    set_block_processed(
        rpc_test.peer_2.chainstate(),
        &parent_consensus_hash,
        &parent_block.block_hash(),
        true,
    );

    store_staging_block(
        rpc_test.peer_2.chainstate(),
        &child_consensus_hash,
        &child_block,
        &parent_consensus_hash,
        456,
        123,
    );
    set_block_processed(
        rpc_test.peer_2.chainstate(),
        &child_consensus_hash,
        &child_block.block_hash(),
        true,
    );

    let index_microblock_hash = StacksBlockHeader::make_index_block_hash(
        &parent_consensus_hash,
        &mblocks.last().as_ref().unwrap().block_hash(),
    );

    for mblock in mblocks.iter() {
        store_staging_microblock(
            rpc_test.peer_2.chainstate(),
            &parent_consensus_hash,
            &parent_block.block_hash(),
            mblock,
        );
    }

    set_microblocks_processed(
        rpc_test.peer_2.chainstate(),
        &child_consensus_hash,
        &child_block.block_hash(),
        &mblocks.last().as_ref().unwrap().block_hash(),
    );

    let mut requests = vec![];

    // query existing microblock stream
    let request =
        StacksHttpRequest::new_getmicroblocks_indexed(addr.into(), index_microblock_hash.clone());
    requests.push(request);

    // query non-existant microblock stream
    let request =
        StacksHttpRequest::new_getmicroblocks_indexed(addr.into(), StacksBlockId([0x11; 32]));
    requests.push(request);

    let mut responses = rpc_test.run(requests);

    // got the microblock stream
    let response = responses.remove(0);
    let mut resp = response.decode_microblocks().unwrap();

    resp.reverse();
    debug!("microblocks: {:?}", &resp);
    assert_eq!(resp, mblocks);

    // no microblock stream
    let response = responses.remove(0);
    let (preamble, body) = response.destruct();

    assert_eq!(preamble.status_code, 404);
}

#[test]
fn test_stream_indexed_microblocks() {
    let mut chainstate = instantiate_chainstate(false, 0x80000000, function_name!());
    let privk = StacksPrivateKey::from_hex(
        "eb05c83546fdd2c79f10f5ad5434a90dd28f7e3acb7c092157aa1bc3656b012c01",
    )
    .unwrap();

    let block = make_empty_coinbase_block(&privk);
    let mut mblocks = make_sample_microblock_stream(&privk, &block.block_hash());
    mblocks.truncate(5);

    let mut child_block = make_empty_coinbase_block(&privk);
    child_block.header.parent_block = block.block_hash();
    child_block.header.parent_microblock = mblocks.last().as_ref().unwrap().block_hash();
    child_block.header.parent_microblock_sequence =
        mblocks.last().as_ref().unwrap().header.sequence;

    let consensus_hash = ConsensusHash([2u8; 20]);
    let parent_consensus_hash = ConsensusHash([1u8; 20]);
    let child_consensus_hash = ConsensusHash([3u8; 20]);

    // store microblocks to staging
    for (i, mblock) in mblocks.iter().enumerate() {
        store_staging_microblock(
            &mut chainstate,
            &consensus_hash,
            &block.block_hash(),
            mblock,
        );
    }

    // store block to staging
    store_staging_block(
        &mut chainstate,
        &consensus_hash,
        &block,
        &parent_consensus_hash,
        1,
        2,
    );

    // store child block to staging
    store_staging_block(
        &mut chainstate,
        &child_consensus_hash,
        &child_block,
        &consensus_hash,
        1,
        2,
    );

    // accept it
    set_block_processed(&mut chainstate, &consensus_hash, &block.block_hash(), true);
    set_block_processed(
        &mut chainstate,
        &child_consensus_hash,
        &child_block.block_hash(),
        true,
    );

    for i in 0..mblocks.len() {
        // set different parts of this stream as confirmed
        set_microblocks_processed(
            &mut chainstate,
            &child_consensus_hash,
            &child_block.block_hash(),
            &mblocks[i].block_hash(),
        );

        // verify that we can stream everything
        let microblock_index_header =
            StacksBlockHeader::make_index_block_hash(&consensus_hash, &mblocks[i].block_hash());

        let mut stream =
            StacksIndexedMicroblockStream::new(&chainstate, &microblock_index_header).unwrap();

        let mut confirmed_mblock_bytes = vec![];
        loop {
            let mut next_bytes = stream.generate_next_chunk().unwrap();
            if next_bytes.is_empty() {
                break;
            }
            test_debug!(
                "Got {} more bytes from staging; add to {} total",
                next_bytes.len(),
                confirmed_mblock_bytes.len()
            );
            confirmed_mblock_bytes.append(&mut next_bytes);
        }

        // decode stream (should be length-prefixed)
        let mut confirmed_mblocks =
            Vec::<StacksMicroblock>::consensus_deserialize(&mut &confirmed_mblock_bytes[..])
                .unwrap();

        confirmed_mblocks.reverse();

        assert_eq!(confirmed_mblocks.len(), mblocks[0..(i + 1)].len());
        for j in 0..(i + 1) {
            test_debug!("check {}", j);
            assert_eq!(confirmed_mblocks[j], mblocks[j])
        }
    }
}
