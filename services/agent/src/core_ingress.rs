use std::collections::HashSet;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};

use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};

use crate::endpoint::random_token;
use crate::protocol::MAX_MESSAGE_LINE_BYTES;

const STRICT_INGRESS_PROTOCOL: u32 = 1;
const MAX_STRICT_INGRESS_ENTRIES: usize = 128;
const MAX_TARGET_GROUP_BYTES: usize = 256;
const CONFIGURE_STRICT_INGRESS_METHOD: &str = "configureStrictIngress";

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CoreStrictIngressRequest<'a> {
    protocol: u32,
    generation: u64,
    entries: Vec<CoreStrictIngressRequestEntry<'a>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CoreStrictIngressRequestEntry<'a> {
    target_group: &'a str,
    username: &'a str,
    password: &'a str,
}

#[derive(Serialize)]
struct CoreActionRequest<'a> {
    id: &'a str,
    method: &'static str,
    data: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct CoreActionResponse {
    id: String,
    method: String,
    code: i32,
    data: CoreStrictIngressResult,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CoreStrictIngressResult {
    protocol: u32,
    generation: u64,
    entries: Vec<CoreStrictIngressResultEntry>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct CoreStrictIngressResultEntry {
    target_group: String,
    endpoint: String,
}

#[derive(Clone)]
struct PendingStrictIngressEntry {
    target_group: String,
    username: String,
    password: String,
}

struct PendingStrictIngress {
    generation: u64,
    id: String,
    entries: Vec<PendingStrictIngressEntry>,
}

pub struct StrictIngressCoreAction {
    generation: u64,
    id: String,
    line: String,
}

impl StrictIngressCoreAction {
    pub fn generation(&self) -> u64 {
        self.generation
    }

    pub fn id(&self) -> &str {
        &self.id
    }

    /// The line contains session credentials and must never be logged or persisted.
    pub fn line(&self) -> &str {
        &self.line
    }
}

pub enum StrictIngressChange {
    Unchanged,
    Request(StrictIngressCoreAction),
}

#[derive(Clone)]
pub struct StrictIngressEndpoint {
    target_group: String,
    endpoint: SocketAddrV4,
    username: String,
    password: String,
}

impl StrictIngressEndpoint {
    pub fn target_group(&self) -> &str {
        &self.target_group
    }

    pub fn endpoint(&self) -> SocketAddrV4 {
        self.endpoint
    }

    pub fn username(&self) -> &str {
        &self.username
    }

    pub fn password(&self) -> &str {
        &self.password
    }
}

#[derive(Clone)]
pub struct StrictIngressDescriptor {
    generation: u64,
    entries: Vec<StrictIngressEndpoint>,
}

impl StrictIngressDescriptor {
    pub fn generation(&self) -> u64 {
        self.generation
    }

    pub fn entries(&self) -> &[StrictIngressEndpoint] {
        &self.entries
    }
}

#[derive(Default)]
pub struct StrictIngressCoordinator {
    generation: u64,
    pending: Option<PendingStrictIngress>,
    active: Option<StrictIngressDescriptor>,
}

impl StrictIngressCoordinator {
    pub fn begin<I, S>(&mut self, target_groups: I) -> Result<StrictIngressChange>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<str>,
    {
        if self.pending.is_some() {
            bail!("strict ingress transition is already pending");
        }

        let mut groups = Vec::new();
        for target in target_groups {
            if groups.len() == MAX_STRICT_INGRESS_ENTRIES {
                bail!("strict ingress target count exceeds the policy bound");
            }
            let target = target.as_ref();
            validate_target_group(target)?;
            groups.push(target.to_owned());
        }
        groups.sort_unstable();
        groups.dedup();

        if self
            .active
            .as_ref()
            .map(|active| {
                active
                    .entries
                    .iter()
                    .map(|entry| entry.target_group.as_str())
                    .eq(groups.iter().map(String::as_str))
            })
            .unwrap_or(groups.is_empty())
        {
            return Ok(StrictIngressChange::Unchanged);
        }

        let generation = self
            .generation
            .checked_add(1)
            .context("strict ingress generation overflow")?;
        let id = format!("_agent-strict-ingress-{generation}");
        let entries = groups
            .into_iter()
            .map(|target_group| PendingStrictIngressEntry {
                target_group,
                username: random_token(),
                password: random_token(),
            })
            .collect::<Vec<_>>();
        let request = CoreStrictIngressRequest {
            protocol: STRICT_INGRESS_PROTOCOL,
            generation,
            entries: entries
                .iter()
                .map(|entry| CoreStrictIngressRequestEntry {
                    target_group: &entry.target_group,
                    username: &entry.username,
                    password: &entry.password,
                })
                .collect(),
        };
        let data = serde_json::to_string(&request)?;
        let line = serde_json::to_string(&CoreActionRequest {
            id: &id,
            method: CONFIGURE_STRICT_INGRESS_METHOD,
            data,
        })?;
        if line.len() > MAX_MESSAGE_LINE_BYTES {
            bail!("strict ingress Core action exceeds the message bound");
        }
        self.generation = generation;
        self.pending = Some(PendingStrictIngress {
            generation,
            id: id.clone(),
            entries,
        });
        Ok(StrictIngressChange::Request(StrictIngressCoreAction {
            generation,
            id,
            line,
        }))
    }

    pub fn complete(&mut self, response_line: &str) -> Result<Option<StrictIngressDescriptor>> {
        let pending = self
            .pending
            .take()
            .context("strict ingress response has no pending transition")?;
        if response_line.is_empty() || response_line.len() > MAX_MESSAGE_LINE_BYTES {
            bail!("strict ingress Core response size is invalid");
        }
        let response: CoreActionResponse = serde_json::from_str(response_line)?;
        if response.id != pending.id
            || response.method != CONFIGURE_STRICT_INGRESS_METHOD
            || response.code != 0
        {
            bail!("strict ingress Core response correlation failed");
        }
        if response.data.protocol != STRICT_INGRESS_PROTOCOL
            || response.data.generation != pending.generation
            || response.data.entries.len() != pending.entries.len()
        {
            bail!("strict ingress Core response shape does not match the request");
        }

        let mut endpoints = HashSet::with_capacity(pending.entries.len());
        let mut committed = Vec::with_capacity(pending.entries.len());
        for (expected, actual) in pending.entries.into_iter().zip(response.data.entries) {
            if actual.target_group != expected.target_group {
                bail!("strict ingress Core response target order is invalid");
            }
            let endpoint: SocketAddr = actual
                .endpoint
                .parse()
                .context("strict ingress Core endpoint is invalid")?;
            let SocketAddr::V4(endpoint) = endpoint else {
                bail!("strict ingress Core endpoint is not IPv4 loopback");
            };
            if endpoint.ip() != &Ipv4Addr::LOCALHOST || endpoint.port() == 0 {
                bail!("strict ingress Core endpoint is not exact loopback");
            }
            if !endpoints.insert(endpoint) {
                bail!("strict ingress Core endpoint is duplicated");
            }
            committed.push(StrictIngressEndpoint {
                target_group: expected.target_group,
                endpoint,
                username: expected.username,
                password: expected.password,
            });
        }

        if committed.is_empty() {
            self.active = None;
        } else {
            self.active = Some(StrictIngressDescriptor {
                generation: pending.generation,
                entries: committed,
            });
        }
        Ok(self.active.clone())
    }

    pub fn abort_pending(&mut self) {
        self.pending = None;
    }

    pub fn core_lost(&mut self) {
        self.pending = None;
        self.active = None;
    }

    pub fn has_pending(&self) -> bool {
        self.pending.is_some()
    }

    pub fn active(&self) -> Option<&StrictIngressDescriptor> {
        self.active.as_ref()
    }
}

fn validate_target_group(target: &str) -> Result<()> {
    if target.is_empty()
        || target.len() > MAX_TARGET_GROUP_BYTES
        || target.trim() != target
        || target.contains(['\0', '\r', '\n'])
    {
        bail!("strict ingress target group is invalid");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use serde_json::{json, Value};

    use super::*;

    fn successful_response(action: &StrictIngressCoreAction, ports: &[u16]) -> String {
        let line: Value = serde_json::from_str(action.line()).unwrap();
        let request: Value = serde_json::from_str(line["data"].as_str().unwrap()).unwrap();
        let entries = request["entries"]
            .as_array()
            .unwrap()
            .iter()
            .zip(ports)
            .map(|(entry, port)| {
                json!({
                    "targetGroup": entry["targetGroup"],
                    "endpoint": format!("127.0.0.1:{port}"),
                })
            })
            .collect::<Vec<_>>();
        json!({
            "id": line["id"],
            "method": "configureStrictIngress",
            "code": 0,
            "data": {
                "protocol": 1,
                "generation": request["generation"],
                "entries": entries,
            }
        })
        .to_string()
    }

    #[test]
    fn plans_are_canonical_bounded_and_agent_credentialed() {
        let mut coordinator = StrictIngressCoordinator::default();
        let StrictIngressChange::Request(action) = coordinator
            .begin(["Work", "GLOBAL", "Work"])
            .expect("prepare strict ingresses")
        else {
            panic!("initial plan was treated as unchanged");
        };
        let line: Value = serde_json::from_str(action.line()).unwrap();
        assert_eq!(line["method"], "configureStrictIngress");
        let request: Value = serde_json::from_str(line["data"].as_str().unwrap()).unwrap();
        assert_eq!(request["generation"], 1);
        let entries = request["entries"].as_array().unwrap();
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0]["targetGroup"], "GLOBAL");
        assert_eq!(entries[1]["targetGroup"], "Work");
        for entry in entries {
            for field in ["username", "password"] {
                let credential = entry[field].as_str().unwrap();
                assert_eq!(credential.len(), 64);
                assert!(credential.bytes().all(|byte| byte.is_ascii_hexdigit()));
            }
        }

        coordinator.abort_pending();
        assert!(coordinator.begin([" invalid"]).is_err());
        let too_many = (0..129).map(|index| format!("group-{index:03}"));
        assert!(coordinator.begin(too_many).is_err());
    }

    #[test]
    fn exact_core_result_commits_endpoints_and_credentials() {
        let mut coordinator = StrictIngressCoordinator::default();
        let StrictIngressChange::Request(action) = coordinator.begin(["Work", "GLOBAL"]).unwrap()
        else {
            panic!("missing Core request");
        };
        let response = successful_response(&action, &[41001, 41002]);
        let descriptor = coordinator
            .complete(&response)
            .expect("complete strict ingress")
            .expect("active descriptor");

        assert_eq!(descriptor.generation(), 1);
        assert_eq!(descriptor.entries().len(), 2);
        assert_eq!(descriptor.entries()[0].target_group(), "GLOBAL");
        assert_eq!(descriptor.entries()[0].endpoint().port(), 41001);
        assert_eq!(descriptor.entries()[1].target_group(), "Work");
        assert_eq!(descriptor.entries()[1].endpoint().port(), 41002);
        assert_eq!(descriptor.entries()[0].username().len(), 64);
        assert_eq!(descriptor.entries()[0].password().len(), 64);
    }

    #[test]
    fn malformed_or_mismatched_results_never_replace_the_active_descriptor() {
        let mut coordinator = StrictIngressCoordinator::default();
        let StrictIngressChange::Request(first) = coordinator.begin(["GLOBAL"]).unwrap() else {
            panic!("missing initial request");
        };
        coordinator
            .complete(&successful_response(&first, &[42001]))
            .unwrap();

        let StrictIngressChange::Request(second) = coordinator.begin(["Work"]).unwrap() else {
            panic!("missing replacement request");
        };
        let malformed =
            successful_response(&second, &[42002]).replace("127.0.0.1:42002", "127.0.0.2:42002");
        assert!(coordinator.complete(&malformed).is_err());
        assert_eq!(coordinator.active().unwrap().generation(), 1);
        assert_eq!(
            coordinator.active().unwrap().entries()[0].target_group(),
            "GLOBAL"
        );
        assert!(!coordinator.has_pending());

        let StrictIngressChange::Request(third) = coordinator.begin(["Work"]).unwrap() else {
            panic!("missing retry request");
        };
        let unknown = successful_response(&third, &[42003])
            .replace("\"code\":0", "\"unknown\":true,\"code\":0");
        assert!(coordinator.complete(&unknown).is_err());
        assert_eq!(coordinator.active().unwrap().generation(), 1);
    }

    #[test]
    fn unchanged_plans_avoid_rebind_but_core_loss_forces_fresh_credentials() {
        let mut coordinator = StrictIngressCoordinator::default();
        let StrictIngressChange::Request(first) = coordinator.begin(["Work", "GLOBAL"]).unwrap()
        else {
            panic!("missing initial request");
        };
        coordinator
            .complete(&successful_response(&first, &[43001, 43002]))
            .unwrap();
        assert!(matches!(
            coordinator.begin(["GLOBAL", "Work", "GLOBAL"]).unwrap(),
            StrictIngressChange::Unchanged
        ));

        let old_username = coordinator.active().unwrap().entries()[0]
            .username()
            .to_owned();
        coordinator.core_lost();
        let StrictIngressChange::Request(rebuilt) = coordinator.begin(["GLOBAL", "Work"]).unwrap()
        else {
            panic!("Core loss did not force a new request");
        };
        let line: Value = serde_json::from_str(rebuilt.line()).unwrap();
        let request: Value = serde_json::from_str(line["data"].as_str().unwrap()).unwrap();
        assert_eq!(request["generation"], 2);
        assert_ne!(request["entries"][0]["username"], old_username);
    }

    #[test]
    fn empty_plan_revokes_and_clears_the_descriptor() {
        let mut coordinator = StrictIngressCoordinator::default();
        let StrictIngressChange::Request(first) = coordinator.begin(["GLOBAL"]).unwrap() else {
            panic!("missing initial request");
        };
        coordinator
            .complete(&successful_response(&first, &[44001]))
            .unwrap();

        let StrictIngressChange::Request(revoke) =
            coordinator.begin(std::iter::empty::<&str>()).unwrap()
        else {
            panic!("missing revoke request");
        };
        assert!(coordinator
            .complete(&successful_response(&revoke, &[]))
            .unwrap()
            .is_none());
        assert!(coordinator.active().is_none());
        assert!(matches!(
            coordinator.begin(std::iter::empty::<&str>()).unwrap(),
            StrictIngressChange::Unchanged
        ));
    }
}
