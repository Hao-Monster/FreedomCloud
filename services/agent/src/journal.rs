use std::collections::{HashMap, VecDeque};

use serde_json::Value;

pub const MAX_REPLAY_ENTRIES: usize = 128;

#[derive(Debug, Default)]
pub struct ReplayJournal {
    entries: HashMap<String, String>,
    proxy_order: VecDeque<String>,
    pending: HashMap<String, String>,
    pending_order: VecDeque<String>,
}

impl ReplayJournal {
    pub fn stage(&mut self, line: &str) {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            return;
        };
        if replay_key(&value).is_none() {
            return;
        }
        let Some(id) = value.get("id").and_then(Value::as_str) else {
            return;
        };
        if let Some(position) = self.pending_order.iter().position(|item| item == id) {
            self.pending_order.remove(position);
        }
        self.pending_order.push_back(id.to_owned());
        self.pending.insert(id.to_owned(), line.to_owned());
        while self.pending.len() > MAX_REPLAY_ENTRIES {
            if let Some(oldest) = self.pending_order.pop_front() {
                self.pending.remove(&oldest);
            }
        }
    }

    pub fn commit_response(&mut self, line: &str) {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            return;
        };
        let Some(id) = value.get("id").and_then(Value::as_str) else {
            return;
        };
        let Some(staged) = self.pending.remove(id) else {
            return;
        };
        if let Some(position) = self.pending_order.iter().position(|item| item == id) {
            self.pending_order.remove(position);
        }
        if value.get("code").and_then(Value::as_i64) == Some(0) {
            self.record(&staged);
        }
    }

    pub fn discard_pending(&mut self) {
        self.pending.clear();
        self.pending_order.clear();
    }

    pub fn record(&mut self, line: &str) {
        let Ok(value) = serde_json::from_str::<Value>(line) else {
            return;
        };
        let Some(key) = replay_key(&value) else {
            return;
        };

        if key.starts_with("changeProxy:") {
            if let Some(position) = self.proxy_order.iter().position(|item| item == &key) {
                self.proxy_order.remove(position);
            }
            self.proxy_order.push_back(key.clone());
        }
        self.entries.insert(key, line.to_owned());

        while self.entries.len() > MAX_REPLAY_ENTRIES {
            let Some(oldest_proxy) = self.proxy_order.pop_front() else {
                break;
            };
            self.entries.remove(&oldest_proxy);
        }
    }

    pub fn replay_lines(&self) -> Vec<String> {
        let mut entries = self.entries.iter().collect::<Vec<_>>();
        entries.sort_by(|(left_key, _), (right_key, _)| {
            replay_rank(left_key)
                .cmp(&replay_rank(right_key))
                .then_with(|| left_key.cmp(right_key))
        });

        entries
            .into_iter()
            .enumerate()
            .filter_map(|(index, (_, line))| {
                let mut value = serde_json::from_str::<Value>(line).ok()?;
                value["id"] = Value::String(format!("_agent-replay-{index}"));
                serde_json::to_string(&value).ok()
            })
            .collect()
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn listener_running(&self) -> Option<bool> {
        let line = self.entries.get("listener")?;
        let value = serde_json::from_str::<Value>(line).ok()?;
        match value.get("method")?.as_str()? {
            "startListener" => Some(true),
            "stopListener" => Some(false),
            _ => None,
        }
    }
}

pub fn replay_key(value: &Value) -> Option<String> {
    let object = value.as_object()?;
    object.get("id")?.as_str()?;
    object.get("data")?;
    let method = object.get("method")?.as_str()?;
    match method {
        "initClash" | "setState" | "setupConfig" | "updateConfig" => Some(method.to_owned()),
        "startListener" | "stopListener" => Some("listener".to_owned()),
        "startLog" | "stopLog" => Some("log".to_owned()),
        "changeProxy" => {
            let data = object.get("data")?;
            let data = match data {
                Value::String(value) => serde_json::from_str::<Value>(value).ok()?,
                value => value.clone(),
            };
            let group = data
                .get("group-name")
                .or_else(|| data.get("groupName"))?
                .as_str()?;
            if group.is_empty() || group.len() > 512 {
                return None;
            }
            Some(format!("changeProxy:{group}"))
        }
        _ => None,
    }
}

fn replay_rank(key: &str) -> u8 {
    match key {
        "initClash" => 0,
        "setState" => 1,
        "setupConfig" => 2,
        "updateConfig" => 3,
        value if value.starts_with("changeProxy:") => 4,
        "listener" => 5,
        "log" => 6,
        _ => 7,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn action(id: &str, method: &str, data: Value) -> String {
        json!({"id": id, "method": method, "data": data}).to_string()
    }

    #[test]
    fn journal_keeps_latest_state_in_dependency_order() {
        let mut journal = ReplayJournal::default();
        journal.record(&action("old", "updateConfig", json!("old")));
        journal.record(&action("init", "initClash", json!("init")));
        journal.record(&action("state", "setState", json!("state")));
        journal.record(&action("setup", "setupConfig", json!("setup")));
        journal.record(&action("new", "updateConfig", json!("new")));
        journal.record(&action("listener", "startListener", Value::Null));

        let lines = journal.replay_lines();
        let methods = lines
            .iter()
            .map(|line| {
                serde_json::from_str::<Value>(line).unwrap()["method"]
                    .as_str()
                    .unwrap()
                    .to_owned()
            })
            .collect::<Vec<_>>();
        assert_eq!(
            methods,
            [
                "initClash",
                "setState",
                "setupConfig",
                "updateConfig",
                "startListener"
            ]
        );
        assert!(lines[3].contains("new"));
        assert!(!lines[3].contains("old"));
    }

    #[test]
    fn journal_never_persists_ui_activity_or_read_only_calls() {
        let mut journal = ReplayJournal::default();
        journal.record(&action("ui", "setUiActive", json!(true)));
        journal.record(&action("read", "getConnections", Value::Null));
        journal.record(&action("logs", "startLog", Value::Null));

        assert_eq!(journal.len(), 1);
        assert_eq!(
            serde_json::from_str::<Value>(&journal.replay_lines()[0]).unwrap()["method"],
            "startLog"
        );
    }

    #[test]
    fn per_group_proxy_choices_are_bounded() {
        let mut journal = ReplayJournal::default();
        for index in 0..(MAX_REPLAY_ENTRIES + 20) {
            journal.record(&action(
                &format!("id-{index}"),
                "changeProxy",
                json!(format!(
                    r#"{{"group-name":"group-{index}","proxy-name":"node"}}"#
                )),
            ));
        }
        assert!(journal.len() <= MAX_REPLAY_ENTRIES);
    }

    #[test]
    fn malformed_messages_are_not_replayed() {
        let mut journal = ReplayJournal::default();
        journal.record("not-json");
        journal.record(r#"{"method":"setupConfig"}"#);
        assert!(journal.is_empty());
    }

    #[test]
    fn listener_state_tracks_the_latest_explicit_action() {
        let mut journal = ReplayJournal::default();
        assert_eq!(journal.listener_running(), None);
        journal.record(&action("start", "startListener", Value::Null));
        assert_eq!(journal.listener_running(), Some(true));
        journal.record(&action("stop", "stopListener", Value::Null));
        assert_eq!(journal.listener_running(), Some(false));
    }

    #[test]
    fn only_successful_mutations_enter_the_replay_journal() {
        let mut journal = ReplayJournal::default();
        journal.stage(&action("failed", "updateConfig", json!("bad")));
        journal.commit_response(
            &json!({"id":"failed","method":"updateConfig","code":-1,"data":"invalid"}).to_string(),
        );
        assert!(journal.is_empty());

        journal.stage(&action("ok", "updateConfig", json!("good")));
        journal.commit_response(
            &json!({"id":"ok","method":"updateConfig","code":0,"data":true}).to_string(),
        );
        assert_eq!(journal.len(), 1);
        assert!(journal.replay_lines()[0].contains("good"));
    }

    #[test]
    fn unconfirmed_mutations_are_bounded_and_discardable() {
        let mut journal = ReplayJournal::default();
        for index in 0..(MAX_REPLAY_ENTRIES + 20) {
            journal.stage(&action(
                &format!("pending-{index}"),
                "updateConfig",
                json!(index),
            ));
        }
        assert!(journal.pending.len() <= MAX_REPLAY_ENTRIES);
        journal.discard_pending();
        assert!(journal.pending.is_empty());
    }
}
