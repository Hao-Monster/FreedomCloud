use std::collections::HashSet;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::net::{Ipv4Addr, Ipv6Addr, SocketAddr, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::Result;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::logging::AgentLogger;

pub const INTERNET_SETTINGS_SUBKEY: &str =
    r"Software\Microsoft\Windows\CurrentVersion\Internet Settings";
const MANAGED_PORTS_FILE_NAME: &str = "freedomnet-managed-ports.json";
const LOOPBACK_PROBE_TIMEOUT: Duration = Duration::from_millis(30);
const WIN32_CLEANUP_TIMEOUT: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct InternetSettingsSnapshot {
    pub proxy_enable: u32,
    pub proxy_server: Option<String>,
    pub auto_config_url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CleanupOutcome {
    Skipped(&'static str),
    Cleared { port: u16 },
}

pub trait SystemProxyBackend: Send + Sync {
    fn read_internet_settings(&self) -> Result<InternetSettingsSnapshot>;
    fn disable_system_proxy(&self) -> Result<()>;
    fn is_loopback_port_listening(&self, port: u16) -> bool;
}

#[derive(Debug, Default)]
pub struct NoopSystemProxyBackend;

impl SystemProxyBackend for NoopSystemProxyBackend {
    fn read_internet_settings(&self) -> Result<InternetSettingsSnapshot> {
        Ok(InternetSettingsSnapshot::default())
    }

    fn disable_system_proxy(&self) -> Result<()> {
        Ok(())
    }

    fn is_loopback_port_listening(&self, _port: u16) -> bool {
        false
    }
}

#[cfg(windows)]
#[derive(Debug, Default)]
pub struct WindowsSystemProxyBackend;

#[cfg(windows)]
impl SystemProxyBackend for WindowsSystemProxyBackend {
    fn read_internet_settings(&self) -> Result<InternetSettingsSnapshot> {
        windows_impl::read_internet_settings()
    }

    fn disable_system_proxy(&self) -> Result<()> {
        windows_impl::disable_system_proxy()
    }

    fn is_loopback_port_listening(&self, port: u16) -> bool {
        probe_loopback_tcp(port)
    }
}

pub fn default_platform_backend() -> Arc<dyn SystemProxyBackend> {
    #[cfg(windows)]
    {
        Arc::new(WindowsSystemProxyBackend)
    }
    #[cfg(not(windows))]
    {
        Arc::new(NoopSystemProxyBackend)
    }
}

/// Parses a Windows `Internet Settings\ProxyServer` string and returns the port
/// ONLY when every non-empty entry points to loopback (`127.0.0.1`, `localhost`,
/// or `[::1]`) on the exact same valid port (`1..=65535`).
pub fn parse_owned_loopback_port(proxy_server: &str) -> Option<u16> {
    let mut matched_port: Option<u16> = None;
    for raw_segment in proxy_server.split(';') {
        let segment = raw_segment.trim();
        if segment.is_empty() {
            continue;
        }
        let address = match segment.split_once('=') {
            Some((scheme, rest)) => {
                let scheme = scheme.trim();
                if scheme.is_empty() || !scheme.bytes().all(|byte| byte.is_ascii_alphanumeric()) {
                    return None;
                }
                rest.trim()
            }
            None => segment,
        };
        let port = parse_loopback_endpoint(address)?;
        match matched_port {
            None => matched_port = Some(port),
            Some(existing) if existing == port => {}
            Some(_) => return None,
        }
    }
    matched_port
}

fn parse_loopback_endpoint(endpoint: &str) -> Option<u16> {
    let mut rest = endpoint.trim();
    if let Some((scheme, after)) = rest.split_once("://") {
        if scheme.is_empty()
            || !scheme
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || byte == b'+' || byte == b'-')
        {
            return None;
        }
        rest = after;
    }
    if let Some(stripped) = rest.strip_suffix('/') {
        rest = stripped;
    }
    if rest.contains(['/', '?', '#']) {
        return None;
    }
    let (host, port_str) = if let Some(after_bracket) = rest.strip_prefix('[') {
        let (bracketed_host, tail) = after_bracket.split_once("]:")?;
        if bracketed_host != "::1" {
            return None;
        }
        ("[::1]", tail)
    } else {
        let (host, port_str) = rest.rsplit_once(':')?;
        if host.contains(':') {
            return None;
        }
        if !host.eq_ignore_ascii_case("127.0.0.1") && !host.eq_ignore_ascii_case("localhost") {
            return None;
        }
        (host, port_str)
    };
    let _ = host;
    let port = port_str.parse::<u16>().ok()?;
    (port > 0).then_some(port)
}

pub fn extract_mixed_port_from_core_action(line: &str) -> Option<u16> {
    let action = serde_json::from_str::<Value>(line).ok()?;
    let method = action.get("method")?.as_str()?;
    if !matches!(method, "setupConfig" | "updateConfig") {
        return None;
    }
    let raw_data = action.get("data")?;
    let owned_data;
    let data = match raw_data {
        Value::String(text) => {
            owned_data = serde_json::from_str::<Value>(text).ok()?;
            &owned_data
        }
        value => value,
    };
    let raw_port = match method {
        "setupConfig" => data
            .get("config")
            .and_then(|config| config.get("mixed-port"))
            .or_else(|| data.get("mixed-port")),
        "updateConfig" => data.get("mixed-port"),
        _ => None,
    }?;
    let port = raw_port.as_u64()?;
    u16::try_from(port).ok().filter(|port| *port > 0)
}

fn has_external_pac(snapshot: &InternetSettingsSnapshot) -> bool {
    snapshot
        .auto_config_url
        .as_deref()
        .is_some_and(|url| !url.trim().is_empty())
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct PersistedManagedPorts {
    ports: Vec<u16>,
}

#[derive(Debug, Default)]
struct ManagedProxyState {
    managed_ports: HashSet<u16>,
    persisted_ports: Option<HashSet<u16>>,
}

pub struct SystemProxyManager {
    backend: Arc<dyn SystemProxyBackend>,
    home_dir: PathBuf,
    state: Mutex<ManagedProxyState>,
}

impl SystemProxyManager {
    pub fn new(backend: Arc<dyn SystemProxyBackend>, home_dir: PathBuf) -> Self {
        let persisted_ports = load_persisted_ports(&home_dir);
        Self {
            backend,
            home_dir,
            state: Mutex::new(ManagedProxyState {
                managed_ports: HashSet::new(),
                persisted_ports,
            }),
        }
    }

    pub fn platform_default(home_dir: PathBuf) -> Self {
        Self::new(default_platform_backend(), home_dir)
    }

    pub fn record_core_action(&self, line: &str) {
        if let Some(port) = extract_mixed_port_from_core_action(line) {
            self.record_managed_port(port);
        }
    }

    pub fn record_managed_port(&self, port: u16) {
        if port == 0 {
            return;
        }
        let snapshot_ports = {
            let Ok(mut state) = self.state.lock() else {
                return;
            };
            if !state.managed_ports.insert(port) {
                return;
            }
            if state.managed_ports.len() > 16 {
                state.managed_ports.clear();
                state.managed_ports.insert(port);
            }
            state.persisted_ports = None;
            let mut ports: Vec<u16> = state.managed_ports.iter().copied().collect();
            ports.sort_unstable();
            ports
        };
        let _ = save_persisted_ports(&self.home_dir, &snapshot_ports);
    }

    pub fn cleanup_orphan_on_startup(
        &self,
        core_running: bool,
        logger: &AgentLogger,
    ) -> CleanupOutcome {
        if core_running {
            return CleanupOutcome::Skipped("core_running");
        }
        let snapshot = match self.backend.read_internet_settings() {
            Ok(snapshot) => snapshot,
            Err(error) => {
                logger.log(format!(
                    "system proxy startup orphan inspection failed: {error:#}"
                ));
                return CleanupOutcome::Skipped("read_failed");
            }
        };
        if snapshot.proxy_enable == 0 {
            return CleanupOutcome::Skipped("proxy_disabled");
        }
        if has_external_pac(&snapshot) {
            return CleanupOutcome::Skipped("external_pac");
        }
        let Some(port) = snapshot
            .proxy_server
            .as_deref()
            .and_then(parse_owned_loopback_port)
        else {
            return CleanupOutcome::Skipped("not_loopback_proxy");
        };
        let owned_or_untracked = {
            let Ok(state) = self.state.lock() else {
                return CleanupOutcome::Skipped("state_poisoned");
            };
            match state.persisted_ports.as_ref() {
                Some(persisted) if !persisted.is_empty() => persisted.contains(&port),
                _ => true,
            }
        };
        if !owned_or_untracked {
            return CleanupOutcome::Skipped("not_owned_port");
        }
        if self.backend.is_loopback_port_listening(port) {
            return CleanupOutcome::Skipped("port_still_listening");
        }
        self.apply_disable(port, "startup_orphan", Some(logger))
    }

    pub fn cleanup_if_owned(&self, reason: &str, logger: Option<&AgentLogger>) -> CleanupOutcome {
        let managed_ports = {
            let Ok(state) = self.state.lock() else {
                return CleanupOutcome::Skipped("state_poisoned");
            };
            state.managed_ports.clone()
        };
        if managed_ports.is_empty() {
            return CleanupOutcome::Skipped("no_managed_ports");
        }
        let snapshot = match self.backend.read_internet_settings() {
            Ok(snapshot) => snapshot,
            Err(error) => {
                if let Some(logger) = logger {
                    logger.log(format!(
                        "system proxy inspection failed reason={reason}: {error:#}"
                    ));
                }
                return CleanupOutcome::Skipped("read_failed");
            }
        };
        if snapshot.proxy_enable == 0 {
            return CleanupOutcome::Skipped("proxy_disabled");
        }
        if has_external_pac(&snapshot) {
            return CleanupOutcome::Skipped("external_pac");
        }
        let Some(port) = snapshot
            .proxy_server
            .as_deref()
            .and_then(parse_owned_loopback_port)
        else {
            return CleanupOutcome::Skipped("not_loopback_proxy");
        };
        if !managed_ports.contains(&port) {
            return CleanupOutcome::Skipped("not_owned_port");
        }
        self.apply_disable(port, reason, logger)
    }

    pub async fn cleanup_if_owned_async(
        self: &Arc<Self>,
        reason: &'static str,
        logger: Arc<AgentLogger>,
    ) -> CleanupOutcome {
        let manager = Arc::clone(self);
        let task_logger = Arc::clone(&logger);
        match tokio::time::timeout(
            WIN32_CLEANUP_TIMEOUT,
            tokio::task::spawn_blocking(move || {
                manager.cleanup_if_owned(reason, Some(&task_logger))
            }),
        )
        .await
        {
            Ok(Ok(outcome)) => outcome,
            Ok(Err(error)) => {
                logger.log(format!(
                    "system proxy cleanup worker failed reason={reason}: {error}"
                ));
                CleanupOutcome::Skipped("worker_failed")
            }
            Err(_) => {
                logger.log(format!(
                    "system proxy cleanup timed out reason={reason}"
                ));
                CleanupOutcome::Skipped("timed_out")
            }
        }
    }

    fn apply_disable(
        &self,
        port: u16,
        reason: &str,
        logger: Option<&AgentLogger>,
    ) -> CleanupOutcome {
        match self.backend.disable_system_proxy() {
            Ok(()) => {
                if let Ok(mut state) = self.state.lock() {
                    state.persisted_ports = None;
                }
                remove_persisted_ports(&self.home_dir);
                if let Some(logger) = logger {
                    logger.log(format!(
                        "cleared owned Windows system proxy port={port} reason={reason}"
                    ));
                }
                CleanupOutcome::Cleared { port }
            }
            Err(error) => {
                if let Some(logger) = logger {
                    logger.log(format!(
                        "failed to clear owned Windows system proxy port={port} reason={reason}: {error:#}"
                    ));
                }
                CleanupOutcome::Skipped("disable_failed")
            }
        }
    }
}

pub struct AgentProxyCleanupGuard {
    manager: Arc<SystemProxyManager>,
    logger: Arc<AgentLogger>,
}

impl AgentProxyCleanupGuard {
    pub fn new(manager: Arc<SystemProxyManager>, logger: Arc<AgentLogger>) -> Self {
        Self { manager, logger }
    }
}

impl Drop for AgentProxyCleanupGuard {
    fn drop(&mut self) {
        let _ = self
            .manager
            .cleanup_if_owned("agent_drop", Some(&self.logger));
    }
}

fn persisted_ports_path(home_dir: &Path) -> Option<PathBuf> {
    if home_dir.as_os_str().is_empty() {
        return None;
    }
    Some(home_dir.join(MANAGED_PORTS_FILE_NAME))
}

fn load_persisted_ports(home_dir: &Path) -> Option<HashSet<u16>> {
    let path = persisted_ports_path(home_dir)?;
    let contents = fs::read(path).ok()?;
    let decoded = serde_json::from_slice::<PersistedManagedPorts>(&contents).ok()?;
    let ports: HashSet<u16> = decoded.ports.into_iter().filter(|port| *port > 0).collect();
    (!ports.is_empty()).then_some(ports)
}

fn save_persisted_ports(home_dir: &Path, ports: &[u16]) -> Result<()> {
    let Some(path) = persisted_ports_path(home_dir) else {
        return Ok(());
    };
    if !home_dir.is_dir() {
        return Ok(());
    }
    let payload = serde_json::to_vec(&PersistedManagedPorts {
        ports: ports.to_vec(),
    })?;
    let pending = path.with_extension(format!("tmp-{}", std::process::id()));
    let mut file = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .open(&pending)?;
    file.write_all(&payload)?;
    file.sync_all()?;
    drop(file);
    if path.exists() {
        let _ = fs::remove_file(&path);
    }
    fs::rename(pending, path)?;
    Ok(())
}

fn remove_persisted_ports(home_dir: &Path) {
    if let Some(path) = persisted_ports_path(home_dir) {
        let _ = fs::remove_file(path);
    }
}

#[allow(dead_code)]
pub(crate) fn probe_loopback_tcp(port: u16) -> bool {
    let v4 = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    if TcpStream::connect_timeout(&v4, LOOPBACK_PROBE_TIMEOUT).is_ok() {
        return true;
    }
    let v6 = SocketAddr::from((Ipv6Addr::LOCALHOST, port));
    TcpStream::connect_timeout(&v6, LOOPBACK_PROBE_TIMEOUT).is_ok()
}

#[cfg(windows)]
mod windows_impl {
    use super::*;
    use anyhow::bail;
    use std::ffi::OsStr;
    use std::os::windows::ffi::OsStrExt;
    use windows_sys::Win32::Foundation::{
        ERROR_FILE_NOT_FOUND, ERROR_INSUFFICIENT_BUFFER, ERROR_MORE_DATA, ERROR_SUCCESS,
    };

    const RAS_ERROR_BUFFER_TOO_SMALL: u32 = 603;
    use windows_sys::Win32::NetworkManagement::Rras::{RasEnumEntriesW, RASENTRYNAMEW};
    use windows_sys::Win32::Networking::WinInet::{
        InternetSetOptionW, INTERNET_OPTION_PER_CONNECTION_OPTION, INTERNET_OPTION_REFRESH,
        INTERNET_OPTION_SETTINGS_CHANGED, INTERNET_PER_CONN_FLAGS, INTERNET_PER_CONN_OPTIONW,
        INTERNET_PER_CONN_OPTIONW_0, INTERNET_PER_CONN_OPTION_LISTW, PROXY_TYPE_DIRECT,
    };
    use windows_sys::Win32::System::Registry::{
        RegCloseKey, RegOpenKeyExW, RegQueryValueExW, RegSetValueExW, HKEY, HKEY_CURRENT_USER,
        KEY_READ, KEY_SET_VALUE, REG_DWORD, REG_EXPAND_SZ, REG_SZ, REG_VALUE_TYPE,
    };

    struct RegKeyGuard(HKEY);

    impl Drop for RegKeyGuard {
        fn drop(&mut self) {
            if !self.0.is_null() {
                unsafe {
                    RegCloseKey(self.0);
                }
            }
        }
    }

    pub(super) fn to_wide_null(value: &str) -> Vec<u16> {
        OsStr::new(value)
            .encode_wide()
            .chain(std::iter::once(0))
            .collect()
    }

    pub(super) fn decode_wide_z(units: &[u16]) -> String {
        let len = units
            .iter()
            .position(|unit| *unit == 0)
            .unwrap_or(units.len());
        String::from_utf16_lossy(&units[..len])
    }

    pub(super) fn read_internet_settings() -> Result<InternetSettingsSnapshot> {
        let subkey = to_wide_null(INTERNET_SETTINGS_SUBKEY);
        let mut hkey: HKEY = std::ptr::null_mut();
        let status = unsafe {
            RegOpenKeyExW(
                HKEY_CURRENT_USER,
                subkey.as_ptr(),
                0,
                KEY_READ,
                &mut hkey,
            )
        };
        if status == ERROR_FILE_NOT_FOUND {
            return Ok(InternetSettingsSnapshot::default());
        }
        if status != ERROR_SUCCESS {
            bail!("RegOpenKeyExW(KEY_READ) failed with error {status}");
        }
        let _guard = RegKeyGuard(hkey);

        let proxy_enable = read_reg_dword(hkey, "ProxyEnable")?.unwrap_or(0);
        let proxy_server = read_reg_string(hkey, "ProxyServer")?;
        let auto_config_url = read_reg_string(hkey, "AutoConfigURL")?;
        Ok(InternetSettingsSnapshot {
            proxy_enable,
            proxy_server,
            auto_config_url,
        })
    }

    fn read_reg_dword(hkey: HKEY, name: &str) -> Result<Option<u32>> {
        let value_name = to_wide_null(name);
        let mut value_type: REG_VALUE_TYPE = 0;
        let mut raw = [0u8; 4];
        let mut bytes = raw.len() as u32;
        let status = unsafe {
            RegQueryValueExW(
                hkey,
                value_name.as_ptr(),
                std::ptr::null(),
                &mut value_type,
                raw.as_mut_ptr(),
                &mut bytes,
            )
        };
        if status == ERROR_FILE_NOT_FOUND {
            return Ok(None);
        }
        if status != ERROR_SUCCESS {
            bail!("RegQueryValueExW({name}) failed with error {status}");
        }
        if value_type != REG_DWORD || bytes != 4 {
            return Ok(None);
        }
        Ok(Some(u32::from_le_bytes(raw)))
    }

    fn read_reg_string(hkey: HKEY, name: &str) -> Result<Option<String>> {
        let value_name = to_wide_null(name);
        for _ in 0..3 {
            let mut value_type: REG_VALUE_TYPE = 0;
            let mut bytes = 0u32;
            let status = unsafe {
                RegQueryValueExW(
                    hkey,
                    value_name.as_ptr(),
                    std::ptr::null(),
                    &mut value_type,
                    std::ptr::null_mut(),
                    &mut bytes,
                )
            };
            if status == ERROR_FILE_NOT_FOUND {
                return Ok(None);
            }
            if status != ERROR_SUCCESS {
                bail!("RegQueryValueExW({name}) size query failed with error {status}");
            }
            if value_type != REG_SZ && value_type != REG_EXPAND_SZ {
                return Ok(None);
            }
            if bytes == 0 {
                return Ok(Some(String::new()));
            }
            let unit_len = (bytes as usize).div_ceil(2);
            let mut buf = vec![0u16; unit_len];
            let mut read_bytes = (buf.len() * 2) as u32;
            let status = unsafe {
                RegQueryValueExW(
                    hkey,
                    value_name.as_ptr(),
                    std::ptr::null(),
                    &mut value_type,
                    buf.as_mut_ptr().cast::<u8>(),
                    &mut read_bytes,
                )
            };
            if status == ERROR_MORE_DATA {
                continue;
            }
            if status == ERROR_FILE_NOT_FOUND {
                return Ok(None);
            }
            if status != ERROR_SUCCESS {
                bail!("RegQueryValueExW({name}) read failed with error {status}");
            }
            let valid_units = (read_bytes as usize / 2).min(buf.len());
            return Ok(Some(decode_wide_z(&buf[..valid_units])));
        }
        bail!("RegQueryValueExW({name}) exceeded retry budget on concurrent resize")
    }

    fn write_proxy_enable_zero() -> Result<()> {
        let subkey = to_wide_null(INTERNET_SETTINGS_SUBKEY);
        let mut hkey: HKEY = std::ptr::null_mut();
        let status = unsafe {
            RegOpenKeyExW(
                HKEY_CURRENT_USER,
                subkey.as_ptr(),
                0,
                KEY_SET_VALUE,
                &mut hkey,
            )
        };
        if status == ERROR_FILE_NOT_FOUND {
            return Ok(());
        }
        if status != ERROR_SUCCESS {
            bail!("RegOpenKeyExW(KEY_SET_VALUE) failed with error {status}");
        }
        let _guard = RegKeyGuard(hkey);
        let value_name = to_wide_null("ProxyEnable");
        let disabled = 0u32.to_le_bytes();
        let status = unsafe {
            RegSetValueExW(
                hkey,
                value_name.as_ptr(),
                0,
                REG_DWORD,
                disabled.as_ptr(),
                disabled.len() as u32,
            )
        };
        if status != ERROR_SUCCESS {
            bail!("RegSetValueExW(ProxyEnable=0) failed with error {status}");
        }
        Ok(())
    }

    fn enumerate_ras_entries() -> Vec<RASENTRYNAMEW> {
        let mut entries = vec![RASENTRYNAMEW::default(); 1];
        let mut count = 0u32;
        for _ in 0..3 {
            entries[0].dwSize = std::mem::size_of::<RASENTRYNAMEW>() as u32;
            let mut bytes = (entries.len() * std::mem::size_of::<RASENTRYNAMEW>()) as u32;
            let error = unsafe {
                RasEnumEntriesW(
                    std::ptr::null(),
                    std::ptr::null(),
                    entries.as_mut_ptr(),
                    &mut bytes,
                    &mut count,
                )
            };
            if error == ERROR_SUCCESS {
                let valid = usize::try_from(count).unwrap_or(0).min(entries.len());
                entries.truncate(valid);
                return entries;
            }
            if error != RAS_ERROR_BUFFER_TOO_SMALL && error != ERROR_INSUFFICIENT_BUFFER {
                return Vec::new();
            }
            let entry_size = std::mem::size_of::<RASENTRYNAMEW>();
            let needed = (bytes as usize).div_ceil(entry_size);
            if needed == 0 || needed > 4096 {
                return Vec::new();
            }
            entries.resize(needed, RASENTRYNAMEW::default());
        }
        Vec::new()
    }

    pub(super) fn disable_system_proxy() -> Result<()> {
        let mut ras_entries = enumerate_ras_entries();
        let mut option = INTERNET_PER_CONN_OPTIONW {
            dwOption: INTERNET_PER_CONN_FLAGS,
            Value: INTERNET_PER_CONN_OPTIONW_0 {
                dwValue: PROXY_TYPE_DIRECT,
            },
        };
        let mut list = INTERNET_PER_CONN_OPTION_LISTW {
            dwSize: std::mem::size_of::<INTERNET_PER_CONN_OPTION_LISTW>() as u32,
            pszConnection: std::ptr::null_mut(),
            dwOptionCount: 1,
            dwOptionError: 0,
            pOptions: &mut option,
        };

        let mut first_error: Option<anyhow::Error> = None;
        let default_ok = unsafe {
            InternetSetOptionW(
                std::ptr::null(),
                INTERNET_OPTION_PER_CONNECTION_OPTION,
                (&raw const list).cast(),
                list.dwSize,
            )
        } != 0;
        if !default_ok {
            first_error = Some(anyhow::Error::from(std::io::Error::last_os_error()));
        }

        for entry in &mut ras_entries {
            list.pszConnection = entry.szEntryName.as_mut_ptr();
            let ok = unsafe {
                InternetSetOptionW(
                    std::ptr::null(),
                    INTERNET_OPTION_PER_CONNECTION_OPTION,
                    (&raw const list).cast(),
                    list.dwSize,
                )
            } != 0;
            if !ok && first_error.is_none() {
                first_error = Some(anyhow::Error::from(std::io::Error::last_os_error()));
            }
        }

        if let Err(err) = write_proxy_enable_zero() {
            if first_error.is_none() {
                first_error = Some(err);
            }
        }

        let changed_ok = unsafe {
            InternetSetOptionW(
                std::ptr::null(),
                INTERNET_OPTION_SETTINGS_CHANGED,
                std::ptr::null(),
                0,
            )
        } != 0;
        if !changed_ok && first_error.is_none() {
            first_error = Some(anyhow::Error::from(std::io::Error::last_os_error()));
        }

        let refresh_ok = unsafe {
            InternetSetOptionW(
                std::ptr::null(),
                INTERNET_OPTION_REFRESH,
                std::ptr::null(),
                0,
            )
        } != 0;
        if !refresh_ok && first_error.is_none() {
            first_error = Some(anyhow::Error::from(std::io::Error::last_os_error()));
        }

        match first_error {
            Some(err) => Err(err),
            None => Ok(()),
        }
    }

    #[cfg(test)]
    mod tests {
        use super::*;

        #[test]
        fn wide_encoding_and_wininet_struct_layout_are_valid() {
            let wide = to_wide_null("127.0.0.1:7890");
            assert_eq!(wide.last().copied(), Some(0));
            assert_eq!(decode_wide_z(&wide), "127.0.0.1:7890");
            assert!(std::mem::size_of::<INTERNET_PER_CONN_OPTION_LISTW>() >= 20);
            assert!(std::mem::size_of::<INTERNET_PER_CONN_OPTIONW>() >= 12);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    struct TempDir(PathBuf);

    impl TempDir {
        fn new(prefix: &str) -> Self {
            let nonce = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .expect("system clock")
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "freedomnet-{prefix}-{}-{nonce}",
                std::process::id()
            ));
            fs::create_dir_all(&path).expect("create temp dir");
            Self(path)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    struct MockProxyBackend {
        snapshot: Mutex<InternetSettingsSnapshot>,
        listening_ports: Mutex<HashSet<u16>>,
        disable_calls: AtomicUsize,
        fail_disable: bool,
    }

    impl MockProxyBackend {
        fn new(snapshot: InternetSettingsSnapshot) -> Self {
            Self {
                snapshot: Mutex::new(snapshot),
                listening_ports: Mutex::new(HashSet::new()),
                disable_calls: AtomicUsize::new(0),
                fail_disable: false,
            }
        }

        fn with_listening(self, port: u16) -> Self {
            self.listening_ports.lock().unwrap().insert(port);
            self
        }

        fn calls(&self) -> usize {
            self.disable_calls.load(Ordering::Acquire)
        }

        fn proxy_enable(&self) -> u32 {
            self.snapshot.lock().unwrap().proxy_enable
        }
    }

    impl SystemProxyBackend for MockProxyBackend {
        fn read_internet_settings(&self) -> Result<InternetSettingsSnapshot> {
            Ok(self.snapshot.lock().unwrap().clone())
        }

        fn disable_system_proxy(&self) -> Result<()> {
            self.disable_calls.fetch_add(1, Ordering::AcqRel);
            if self.fail_disable {
                anyhow::bail!("simulated WinInet failure");
            }
            self.snapshot.lock().unwrap().proxy_enable = 0;
            Ok(())
        }

        fn is_loopback_port_listening(&self, port: u16) -> bool {
            self.listening_ports.lock().unwrap().contains(&port)
        }
    }

    #[test]
    fn parses_owned_loopback_proxy_server_variants() {
        for (input, expected) in [
            ("127.0.0.1:7890", Some(7890)),
            (" 127.0.0.1:17890 ", Some(17890)),
            ("localhost:7890", Some(7890)),
            ("LOCALHOST:7890", Some(7890)),
            ("[::1]:7890", Some(7890)),
            ("http://127.0.0.1:7890", Some(7890)),
            ("http=127.0.0.1:7890;https=127.0.0.1:7890", Some(7890)),
            (
                "http=127.0.0.1:7890;https=localhost:7890;socks=127.0.0.1:7890;",
                Some(7890),
            ),
            ("socks=http://127.0.0.1:7890", Some(7890)),
            ("", None),
            ("   ", None),
            (";;", None),
            ("127.0.0.1:0", None),
            ("127.0.0.1:70000", None),
            ("127.0.0.1:abc", None),
            ("127.0.0.1", None),
            ("corp-proxy.internal:8080", None),
            ("10.0.0.1:7890", None),
            ("192.168.1.2:7890", None),
            ("http=127.0.0.1:7890;https=corp-proxy.internal:8080", None),
            ("http=127.0.0.1:7890;https=127.0.0.1:8888", None),
            ("http=http://corp.local/proxy.pac", None),
        ] {
            assert_eq!(
                parse_owned_loopback_port(input),
                expected,
                "input={input:?}"
            );
        }
    }

    #[test]
    fn clears_only_when_proxy_enable_nonzero_and_owned_managed_port() {
        let home = TempDir::new("proxy-clear");
        let logger = AgentLogger::new(&home.0);
        let backend = Arc::new(MockProxyBackend::new(InternetSettingsSnapshot {
            proxy_enable: 1,
            proxy_server: Some("http=127.0.0.1:7890;https=localhost:7890".to_owned()),
            auto_config_url: Some(String::new()),
        }));
        let manager = SystemProxyManager::new(backend.clone(), home.0.clone());
        manager.record_managed_port(7890);
        assert!(home.0.join(MANAGED_PORTS_FILE_NAME).exists());

        let outcome = manager.cleanup_if_owned("core_failed", Some(&logger));
        assert_eq!(outcome, CleanupOutcome::Cleared { port: 7890 });
        assert_eq!(backend.calls(), 1);
        assert_eq!(backend.proxy_enable(), 0);
        assert!(!home.0.join(MANAGED_PORTS_FILE_NAME).exists());

        // Idempotent when already disabled.
        let second = manager.cleanup_if_owned("agent_drop", Some(&logger));
        assert_eq!(second, CleanupOutcome::Skipped("proxy_disabled"));
        assert_eq!(backend.calls(), 1);
    }

    #[test]
    fn never_clears_corporate_pac_non_loopback_or_unowned_ports() {
        let home = TempDir::new("proxy-protect");
        let logger = AgentLogger::new(&home.0);

        let cases = [
            (
                "external_proxy",
                InternetSettingsSnapshot {
                    proxy_enable: 1,
                    proxy_server: Some("corp-proxy.internal:8080".to_owned()),
                    auto_config_url: None,
                },
            ),
            (
                "corporate_pac",
                InternetSettingsSnapshot {
                    proxy_enable: 1,
                    proxy_server: Some("127.0.0.1:7890".to_owned()),
                    auto_config_url: Some("https://corp.example.com/proxy.pac".to_owned()),
                },
            ),
            (
                "other_loopback_port",
                InternetSettingsSnapshot {
                    proxy_enable: 1,
                    proxy_server: Some("127.0.0.1:8888".to_owned()),
                    auto_config_url: None,
                },
            ),
            (
                "already_disabled",
                InternetSettingsSnapshot {
                    proxy_enable: 0,
                    proxy_server: Some("127.0.0.1:7890".to_owned()),
                    auto_config_url: None,
                },
            ),
        ];

        for (name, snapshot) in cases {
            let backend = Arc::new(MockProxyBackend::new(snapshot));
            let manager = SystemProxyManager::new(backend.clone(), home.0.clone());
            manager.record_managed_port(7890);
            let outcome = manager.cleanup_if_owned("shutdown", Some(&logger));
            assert!(
                matches!(outcome, CleanupOutcome::Skipped(_)),
                "case {name} unexpectedly cleared: {outcome:?}"
            );
            assert_eq!(backend.calls(), 0, "case {name} called disable");
        }
    }

    #[test]
    fn startup_orphan_check_requires_dead_port_and_no_running_core() {
        let home = TempDir::new("proxy-orphan");
        let logger = AgentLogger::new(&home.0);

        // 1. Live listener on 127.0.0.1:7890 -> must NOT clear.
        let live_backend = Arc::new(
            MockProxyBackend::new(InternetSettingsSnapshot {
                proxy_enable: 1,
                proxy_server: Some("127.0.0.1:7890".to_owned()),
                auto_config_url: None,
            })
            .with_listening(7890),
        );
        let manager = SystemProxyManager::new(live_backend.clone(), home.0.clone());
        assert_eq!(
            manager.cleanup_orphan_on_startup(false, &logger),
            CleanupOutcome::Skipped("port_still_listening")
        );
        assert_eq!(live_backend.calls(), 0);

        // 2. Core already running -> must NOT clear.
        let dead_backend = Arc::new(MockProxyBackend::new(InternetSettingsSnapshot {
            proxy_enable: 1,
            proxy_server: Some("127.0.0.1:7890".to_owned()),
            auto_config_url: None,
        }));
        let manager = SystemProxyManager::new(dead_backend.clone(), home.0.clone());
        assert_eq!(
            manager.cleanup_orphan_on_startup(true, &logger),
            CleanupOutcome::Skipped("core_running")
        );
        assert_eq!(dead_backend.calls(), 0);

        // 3. No core running, dead loopback port, no persisted mismatch -> clears.
        assert_eq!(
            manager.cleanup_orphan_on_startup(false, &logger),
            CleanupOutcome::Cleared { port: 7890 }
        );
        assert_eq!(dead_backend.calls(), 1);
        assert_eq!(dead_backend.proxy_enable(), 0);

        // 4. Persisted FreedomNet port [7890] must NOT clear unowned dead loopback 8888.
        let writer_manager =
            SystemProxyManager::new(Arc::new(NoopSystemProxyBackend), home.0.clone());
        writer_manager.record_managed_port(7890);
        let other_dead_backend = Arc::new(MockProxyBackend::new(InternetSettingsSnapshot {
            proxy_enable: 1,
            proxy_server: Some("127.0.0.1:8888".to_owned()),
            auto_config_url: None,
        }));
        let reload_manager = SystemProxyManager::new(other_dead_backend.clone(), home.0.clone());
        assert_eq!(
            reload_manager.cleanup_orphan_on_startup(false, &logger),
            CleanupOutcome::Skipped("not_owned_port")
        );
        assert_eq!(other_dead_backend.calls(), 0);

        // 5. Persisted FreedomNet port [7890] DOES clear dead 7890 on reload.
        let matching_dead_backend = Arc::new(MockProxyBackend::new(InternetSettingsSnapshot {
            proxy_enable: 1,
            proxy_server: Some("127.0.0.1:7890".to_owned()),
            auto_config_url: None,
        }));
        let matching_reload =
            SystemProxyManager::new(matching_dead_backend.clone(), home.0.clone());
        assert_eq!(
            matching_reload.cleanup_orphan_on_startup(false, &logger),
            CleanupOutcome::Cleared { port: 7890 }
        );
        assert_eq!(matching_dead_backend.calls(), 1);
        assert_eq!(matching_dead_backend.proxy_enable(), 0);
    }

    #[test]
    fn extracts_mixed_port_from_setup_and_update_config_actions() {
        assert_eq!(
            extract_mixed_port_from_core_action(
                r#"{"id":"1","method":"setupConfig","data":{"config":{"mixed-port":7890},"test-url":"https://x"}}"#
            ),
            Some(7890)
        );
        assert_eq!(
            extract_mixed_port_from_core_action(
                r#"{"id":"2","method":"updateConfig","data":"{\"mixed-port\":17890,\"allow-lan\":false}"}"#
            ),
            Some(17890)
        );
        assert_eq!(
            extract_mixed_port_from_core_action(
                r#"{"id":"3","method":"updateConfig","data":{"mixed-port":0}}"#
            ),
            None
        );
        assert_eq!(
            extract_mixed_port_from_core_action(
                r#"{"id":"4","method":"changeProxy","data":{"group-name":"PROXY","proxy-name":"n1"}}"#
            ),
            None
        );
    }

    #[test]
    fn probe_loopback_tcp_distinguishes_live_and_dead_listeners() {
        let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0)).expect("bind loopback");
        let port = listener.local_addr().unwrap().port();
        assert!(probe_loopback_tcp(port));
        drop(listener);
        assert!(!probe_loopback_tcp(port));
    }

    #[test]
    fn drop_guard_clears_owned_proxy_on_unwind_or_exit() {
        let home = TempDir::new("proxy-drop");
        let logger = AgentLogger::new(&home.0);
        let backend = Arc::new(MockProxyBackend::new(InternetSettingsSnapshot {
            proxy_enable: 1,
            proxy_server: Some("127.0.0.1:7890".to_owned()),
            auto_config_url: None,
        }));
        let manager = Arc::new(SystemProxyManager::new(backend.clone(), home.0.clone()));
        manager.record_managed_port(7890);

        {
            let _guard = AgentProxyCleanupGuard::new(Arc::clone(&manager), Arc::clone(&logger));
        }

        assert_eq!(backend.calls(), 1);
        assert_eq!(backend.proxy_enable(), 0);
    }
}
