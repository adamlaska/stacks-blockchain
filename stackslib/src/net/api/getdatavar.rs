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

use clarity::vm::ast::parser::v1::CLARITY_NAME_REGEX;
use clarity::vm::clarity::ClarityConnection;
use clarity::vm::database::{ClarityDatabase, StoreType};
use clarity::vm::representations::{CONTRACT_NAME_REGEX_STRING, STANDARD_PRINCIPAL_REGEX_STRING};
use clarity::vm::types::QualifiedContractIdentifier;
use clarity::vm::{ClarityName, ContractName};
use regex::{Captures, Regex};
use stacks_common::types::chainstate::StacksAddress;
use stacks_common::types::net::PeerHost;
use stacks_common::util::hash::to_hex;

use crate::net::http::{
    parse_json, Error, HttpNotFound, HttpRequest, HttpRequestContents, HttpRequestPreamble,
    HttpResponse, HttpResponseContents, HttpResponsePayload, HttpResponsePreamble,
};
use crate::net::httpcore::{
    request, HttpPreambleExtensions, HttpRequestContentsExtensions, RPCRequestHandler,
    StacksHttpRequest, StacksHttpResponse,
};
use crate::net::{Error as NetError, StacksNodeState, TipRequest};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct DataVarResponse {
    pub data: String,
    #[serde(rename = "proof")]
    #[serde(default)]
    #[serde(skip_serializing_if = "Option::is_none")]
    pub marf_proof: Option<String>,
}

#[derive(Clone)]
pub struct RPCGetDataVarRequestHandler {
    pub contract_identifier: Option<QualifiedContractIdentifier>,
    pub varname: Option<ClarityName>,
}
impl RPCGetDataVarRequestHandler {
    pub fn new() -> Self {
        Self {
            contract_identifier: None,
            varname: None,
        }
    }
}

/// Decode the HTTP request
impl HttpRequest for RPCGetDataVarRequestHandler {
    fn verb(&self) -> &'static str {
        "GET"
    }

    fn path_regex(&self) -> Regex {
        Regex::new(&format!(
            "^/v2/data_var/(?P<address>{})/(?P<contract>{})/(?P<varname>{})$",
            *STANDARD_PRINCIPAL_REGEX_STRING, *CONTRACT_NAME_REGEX_STRING, *CLARITY_NAME_REGEX
        ))
        .unwrap()
    }

    fn metrics_identifier(&self) -> &str {
        "/v2/data_var/:principal/:contract_name/:var_name"
    }

    /// Try to decode this request.
    /// There's nothing to load here, so just make sure the request is well-formed.
    fn try_parse_request(
        &mut self,
        preamble: &HttpRequestPreamble,
        captures: &Captures,
        query: Option<&str>,
        _body: &[u8],
    ) -> Result<HttpRequestContents, Error> {
        if preamble.get_content_length() != 0 {
            return Err(Error::DecodeError(
                "Invalid Http request: expected 0-length body".to_string(),
            ));
        }

        let contract_identifier = request::get_contract_address(captures, "address", "contract")?;
        let varname = request::get_clarity_name(captures, "varname")?;

        self.contract_identifier = Some(contract_identifier);
        self.varname = Some(varname);

        let contents = HttpRequestContents::new().query_string(query);
        Ok(contents)
    }
}

/// Handle the HTTP request
impl RPCRequestHandler for RPCGetDataVarRequestHandler {
    /// Reset internal state
    fn restart(&mut self) {
        self.contract_identifier = None;
        self.varname = None;
    }

    /// Make the response
    fn try_handle_request(
        &mut self,
        preamble: HttpRequestPreamble,
        contents: HttpRequestContents,
        node: &mut StacksNodeState,
    ) -> Result<(HttpResponsePreamble, HttpResponseContents), NetError> {
        let contract_identifier = self.contract_identifier.take().ok_or(NetError::SendError(
            "`contract_identifier` not set".to_string(),
        ))?;
        let var_name = self
            .varname
            .take()
            .ok_or(NetError::SendError("`varname` not set".to_string()))?;

        let tip = match node.load_stacks_chain_tip(&preamble, &contents) {
            Ok(tip) => tip,
            Err(error_resp) => {
                return error_resp.try_into_contents().map_err(NetError::from);
            }
        };

        let with_proof = contents.get_with_proof();
        let key = ClarityDatabase::make_key_for_trip(
            &contract_identifier,
            StoreType::Variable,
            &var_name,
        );

        let data_opt = node.with_node_state(|_network, sortdb, chainstate, _mempool, _rpc_args| {
            chainstate.maybe_read_only_clarity_tx(
                &sortdb.index_handle_at_block(chainstate, &tip)?,
                &tip,
                |clarity_tx| {
                    clarity_tx.with_clarity_db_readonly(|clarity_db| {
                        let (value_hex, marf_proof): (String, _) = if with_proof {
                            clarity_db
                                .get_data_with_proof(&key)
                                .ok()
                                .flatten()
                                .map(|(a, b)| (a, Some(format!("0x{}", to_hex(&b)))))?
                        } else {
                            clarity_db
                                .get_data(&key)
                                .ok()
                                .flatten()
                                .map(|a| (a, None))?
                        };

                        let data = format!("0x{}", value_hex);
                        Some(DataVarResponse { data, marf_proof })
                    })
                },
            )
        });

        let data_resp = match data_opt {
            Ok(Some(Some(data))) => data,
            Ok(Some(None)) => {
                return StacksHttpResponse::new_error(
                    &preamble,
                    &HttpNotFound::new("Data var not found".to_string()),
                )
                .try_into_contents()
                .map_err(NetError::from);
            }
            Ok(None) | Err(_) => {
                return StacksHttpResponse::new_error(
                    &preamble,
                    &HttpNotFound::new("Chain tip not found".to_string()),
                )
                .try_into_contents()
                .map_err(NetError::from);
            }
        };

        let mut preamble = HttpResponsePreamble::ok_json(&preamble);
        preamble.set_canonical_stacks_tip_height(Some(node.canonical_stacks_tip_height()));
        let body = HttpResponseContents::try_from_json(&data_resp)?;
        Ok((preamble, body))
    }
}

/// Decode the HTTP response
impl HttpResponse for RPCGetDataVarRequestHandler {
    fn try_parse_response(
        &self,
        preamble: &HttpResponsePreamble,
        body: &[u8],
    ) -> Result<HttpResponsePayload, Error> {
        let datavar: DataVarResponse = parse_json(preamble, body)?;
        Ok(HttpResponsePayload::try_from_json(datavar)?)
    }
}

impl StacksHttpRequest {
    /// Make a new request for a data var
    pub fn new_getdatavar(
        host: PeerHost,
        contract_addr: StacksAddress,
        contract_name: ContractName,
        var_name: ClarityName,
        tip_req: TipRequest,
        with_proof: bool,
    ) -> StacksHttpRequest {
        StacksHttpRequest::new_for_peer(
            host,
            "GET".into(),
            format!(
                "/v2/data_var/{}/{}/{}",
                &contract_addr, &contract_name, &var_name
            ),
            HttpRequestContents::new()
                .for_tip(tip_req)
                .query_arg("proof".into(), if with_proof { "1" } else { "0" }.into()),
        )
        .expect("FATAL: failed to construct request from infallible data")
    }
}

impl StacksHttpResponse {
    pub fn decode_data_var_response(self) -> Result<DataVarResponse, NetError> {
        let contents = self.get_http_payload_ok()?;
        let contents_json: serde_json::Value = contents.try_into()?;
        let resp: DataVarResponse = serde_json::from_value(contents_json)
            .map_err(|_e| NetError::DeserializeError("Failed to load from JSON".to_string()))?;
        Ok(resp)
    }
}
