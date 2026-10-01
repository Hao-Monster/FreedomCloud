use std::collections::{HashMap, HashSet};
use std::net::{Ipv4Addr, SocketAddr};

use anyhow::{bail, Context, Result};
use serde_json::{json, Value};
use std::path::Path;
use crate::journal::{ReplayJournal, replay_key, MAX_REPLAY_ENTRIES};

/// Session credentials stay outside the ordinary journal and are persisted only
/// in the OS Keychain. Reusing exact ports lets a running NE keep its authenticated policy
/// across a Core-only crash without depending on a connected Flutter window.
#[derive(Clone, Default)]
pub(crate) struct MacStrictReplay {
    pending: HashMap<String, Value>,
    active: Option<Value>,
    last_generation: u64,
}

impl MacStrictReplay {
    pub(crate) fn from_snapshot(encoded: Option<&str>) -> Result<Self> {
        let Some(encoded) = encoded else { return Ok(Self::default()); };
        if encoded.len() > 128 * 1024 { bail!("stored strict ingress exceeds size bound"); }
        let request: Value = serde_json::from_str(encoded).context("invalid stored strict ingress")?;
        let object = request.as_object().context("invalid stored strict ingress object")?;
        if object.keys().any(|key| !["protocol", "generation", "entries", "udpPort"].contains(&key.as_str())) ||
            request["protocol"].as_u64() != Some(2) || request["generation"].as_u64().unwrap_or(0) == 0 {
            bail!("invalid stored strict ingress protocol");
        }
        let valid_port = |value: &Value| value.as_u64().is_some_and(|port| (1024..=65535).contains(&port));
        if !valid_port(&request["udpPort"]) { bail!("invalid stored strict UDP port"); }
        let entries = request["entries"].as_array().context("invalid stored strict entries")?;
        if entries.is_empty() || entries.len() > 128 { bail!("invalid stored strict entry count"); }
        let mut groups = HashSet::new();
        let mut ports = HashSet::new();
        let mut key_ids = HashSet::new();
        for entry in entries {
            let object = entry.as_object().context("invalid stored strict entry")?;
            if object.keys().any(|key| !["targetGroup", "username", "password", "port"].contains(&key.as_str())) {
                bail!("unknown stored strict entry field");
            }
            let group = entry["targetGroup"].as_str().context("invalid stored strict group")?;
            if group.is_empty() || group.len() > 256 || group.trim() != group || group.chars().any(|value| matches!(value, '\0' | '\r' | '\n')) ||
                !groups.insert(group) || !valid_port(&entry["port"]) || !ports.insert(entry["port"].as_u64()) {
                bail!("invalid stored strict target or port");
            }
            for name in ["username", "password"] {
                let value = entry[name].as_str().context("missing stored strict credential")?;
                if value.len() != 64 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
                    bail!("invalid stored strict credential");
                }
            }
            let key_id = entry["username"].as_str().unwrap()[..32].to_ascii_lowercase();
            if !key_ids.insert(key_id) { bail!("duplicate stored strict key id"); }
        }
        let last_generation = request["generation"].as_u64().unwrap();
        Ok(Self { pending: HashMap::new(), active: Some(request), last_generation })
    }

    pub(crate) fn encode_store(&self, journal: &ReplayJournal, home: &Path) -> Result<Option<String>> {
        let Some(strict) = self.active.as_ref() else { return Ok(None); };
        let encoded = json!({"schemaVersion": 1, "strict": strict, "coreActions": journal.replay_lines()}).to_string();
        let _ = Self::decode_store(Some(&encoded), home)?;
        Ok(Some(encoded))
    }

    pub(crate) fn decode_store(encoded: Option<&str>, home: &Path) -> Result<(Self, ReplayJournal)> {
        let Some(encoded) = encoded else { return Ok((Self::default(), ReplayJournal::default())); };
        if encoded.len() > 4 * 1024 * 1024 { bail!("macOS recovery snapshot exceeds 4 MiB"); }
        let value: Value = serde_json::from_str(encoded).context("invalid macOS recovery snapshot")?;
        let object = value.as_object().context("invalid macOS recovery envelope")?;
        if value["schemaVersion"].as_u64() != Some(1) ||
            object.keys().any(|key| !["schemaVersion", "strict", "coreActions"].contains(&key.as_str())) {
            bail!("unsupported macOS recovery snapshot");
        }
        let strict = Self::from_snapshot(Some(&value["strict"].to_string()))?;
        let lines = value["coreActions"].as_array().context("missing Core recovery actions")?;
        if lines.len() > MAX_REPLAY_ENTRIES { bail!("Core recovery action bound exceeded"); }
        let mut journal = ReplayJournal::default();
        let mut keys = HashSet::new();
        for line in lines {
            let line = line.as_str().context("invalid Core recovery action")?;
            let action: Value = serde_json::from_str(line).context("invalid Core recovery action JSON")?;
            let key = replay_key(&action).context("Core recovery action is not replayable")?;
            if !keys.insert(key.clone()) { bail!("duplicate Core recovery action"); }
            if key == "initClash" {
                let params: Value = serde_json::from_str(action["data"].as_str().context("invalid Core initialization")?)?;
                let requested = Path::new(params["home-dir"].as_str().context("missing Core home")?)
                    .canonicalize().context("stored Core home is unavailable")?;
                if requested != home.canonicalize()? { bail!("stored Core home does not match Agent owner"); }
            }
            journal.record(line);
        }
        if !keys.contains("initClash") || !keys.contains("setupConfig") || !keys.contains("listener") {
            bail!("strict recovery requires complete Core initialization and listener intent");
        }
        Ok((strict, journal))
    }

    pub(crate) fn stage(&mut self, action: &Value) -> Result<()> {
        if action.get("method").and_then(Value::as_str) != Some("configureStrictIngress") {
            return Ok(());
        }
        let id = action.get("id").and_then(Value::as_str).context("missing strict request id")?;
        let data = action.get("data").and_then(Value::as_str).context("invalid strict request data")?;
        if data.len() > 128 * 1024 || self.pending.len() >= 16 || self.pending.contains_key(id) {
            bail!("strict ingress pending request bound exceeded");
        }
        let request: Value = serde_json::from_str(data)?;
        if request.get("protocol").and_then(Value::as_u64) != Some(2) ||
            request.get("generation").and_then(Value::as_u64).unwrap_or(0) == 0 ||
            request.get("entries").and_then(Value::as_array).map_or(true, |entries| entries.len() > 128) {
            bail!("invalid strict ingress request");
        }
        self.pending.insert(id.to_owned(), request);
        Ok(())
    }

    pub(crate) fn commit_response(&mut self, response: &Value) -> Result<()> {
        let Some(id) = response.get("id").and_then(Value::as_str) else { return Ok(()); };
        let Some(mut request) = self.pending.remove(id) else { return Ok(()); };
        if response.get("code").and_then(Value::as_i64) != Some(0) { return Ok(()); }
        let result = response.get("data").context("missing strict ingress result")?;
        if response.get("method").and_then(Value::as_str) != Some("configureStrictIngress") ||
            result.get("protocol").and_then(Value::as_u64) != Some(2) || result["generation"] != request["generation"] {
            bail!("strict ingress response contract mismatch");
        }
        let generation = request["generation"].as_u64().context("invalid strict generation")?;
        if generation < self.last_generation { return Ok(()); }
        let results = result.get("entries").and_then(Value::as_array).context("missing strict ingress endpoints")?;
        let entries = request.get_mut("entries").and_then(Value::as_array_mut).context("missing strict ingress entries")?;
        if entries.len() != results.len() { bail!("strict ingress endpoint count mismatch"); }
        if entries.is_empty() {
            self.active = None;
            self.last_generation = generation;
            return Ok(());
        }
        let mut ports = HashSet::new();
        let mut groups = HashSet::new();
        for entry in entries {
            let group = entry.get("targetGroup").and_then(Value::as_str).context("invalid strict target group")?;
            if !groups.insert(group.to_owned()) { bail!("duplicate strict ingress target"); }
            let matching = results.iter().filter(|item| item.get("targetGroup").and_then(Value::as_str) == Some(group)).collect::<Vec<_>>();
            if matching.len() != 1 { bail!("missing or duplicate strict ingress endpoint"); }
            let port = loopback_port(&matching[0]["endpoint"])?;
            if !ports.insert(port) { bail!("duplicate strict ingress port"); }
            if let Some(requested) = entry.get("port").and_then(Value::as_u64) {
                if requested != 0 && requested != u64::from(port) { bail!("strict ingress port changed"); }
            }
            entry["port"] = json!(port);
        }
        let udp_port = loopback_port(&result["udpEndpoint"])?;
        if let Some(requested) = request.get("udpPort").and_then(Value::as_u64) {
            if requested != 0 && requested != u64::from(udp_port) { bail!("strict UDP ingress port changed"); }
        }
        request["udpPort"] = json!(udp_port);
        self.active = Some(request);
        self.last_generation = generation;
        Ok(())
    }

    pub(crate) fn discard_pending(&mut self) { self.pending.clear(); }

    pub(crate) fn replay_line(&self) -> Option<String> {
        self.active.as_ref().map(|request| json!({
            "id": "_agent-macos-strict-replay", "method": "configureStrictIngress", "data": request.to_string()
        }).to_string())
    }

    pub(crate) fn stopped_replay_line(&self) -> Option<String> {
        self.active.as_ref().map(|request| json!({
            "id": "_agent-macos-strict-intent", "method": "restoreStrictIngressIntent", "data": request.to_string()
        }).to_string())
    }

    pub(crate) fn validate_replay(&mut self, response: &Value) -> Result<()> {
        let request = self.active.clone().context("missing strict replay intent")?;
        self.pending.insert("_agent-macos-strict-replay".to_owned(), request);
        if response.get("code").and_then(Value::as_i64) != Some(0) {
            self.pending.remove("_agent-macos-strict-replay");
            bail!("Core rejected strict ingress recovery");
        }
        self.commit_response(response)
    }
}

fn loopback_port(value: &Value) -> Result<u16> {
    let endpoint: SocketAddr = value.as_str().context("invalid strict endpoint")?.parse()?;
    match endpoint {
        SocketAddr::V4(endpoint) if endpoint.ip() == &Ipv4Addr::LOCALHOST && endpoint.port() >= 1024 => Ok(endpoint.port()),
        _ => bail!("strict recovery endpoint must be unprivileged IPv4 loopback"),
    }
}
