//! Windows Filtering Platform primitives used by strict per-application mode.
//!
//! This module deliberately exposes an explicit block backend. A block rule is
//! the fail-closed fallback required by the strict policy contract; it is not a
//! proxy redirect and must not be reported as an armed redirect backend.

use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

const MAX_EXECUTABLE_PATH_BYTES: usize = 1024;
const MAX_DISPLAY_NAME_CHARS: usize = 96;
const RECOVERY_MARKER_FILE_NAME: &str = "strict-recovery.json";
const MAX_RECOVERY_TARGETS: usize = 128;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StrictAppTarget {
    executable: PathBuf,
}

impl StrictAppTarget {
    /// Validates and canonicalizes an application executable for strict mode.
    ///
    /// Requiring an existing regular `.exe` prevents path confusion and keeps
    /// the privileged WFP operation from becoming an arbitrary path primitive.
    pub fn new(path: impl AsRef<Path>) -> Result<Self, String> {
        let requested = path.as_ref();
        if requested.as_os_str().to_string_lossy().len() > MAX_EXECUTABLE_PATH_BYTES {
            return Err("application path exceeds the 1024-byte limit".to_owned());
        }
        if !requested.is_absolute() {
            return Err("application path must be absolute".to_owned());
        }
        if requested
            .to_string_lossy()
            .chars()
            .any(|character| matches!(character, '\r' | '\n'))
        {
            return Err("application path contains a control character".to_owned());
        }
        if !requested
            .extension()
            .is_some_and(|extension| extension.eq_ignore_ascii_case("exe"))
        {
            return Err("strict application target must be an .exe".to_owned());
        }
        let executable = requested
            .canonicalize()
            .map_err(|error| format!("application executable is unavailable: {error}"))?;
        let metadata = std::fs::metadata(&executable)
            .map_err(|error| format!("application executable metadata unavailable: {error}"))?;
        if !metadata.is_file() {
            return Err("application target is not a regular file".to_owned());
        }
        let filename = executable
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or_default();
        if matches!(
            filename.to_ascii_lowercase().as_str(),
            "flclashcore.exe" | "flclashhelperservice.exe"
        ) {
            return Err("FlClashX service binaries cannot be strict targets".to_owned());
        }
        Ok(Self { executable })
    }

    pub fn display_name(&self) -> String {
        let filename = self
            .executable
            .file_name()
            .and_then(|value| value.to_str())
            .unwrap_or("application");
        format!("FlClashX strict block: {filename}")
            .chars()
            .take(MAX_DISPLAY_NAME_CHARS)
            .collect()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockFilterPlan {
    pub executable: PathBuf,
    pub display_name: String,
    /// Windows ALE connect layers covered by this plan.
    pub layers: [&'static str; 2],
}

impl BlockFilterPlan {
    pub fn for_target(target: &StrictAppTarget) -> Self {
        Self {
            executable: target.executable.clone(),
            display_name: target.display_name(),
            layers: ["ALE_AUTH_CONNECT_V4", "ALE_AUTH_CONNECT_V6"],
        }
    }
}

/// Builds the platform-independent plan without touching WFP state.
pub fn build_block_filter_plan(path: impl AsRef<Path>) -> Result<BlockFilterPlan, String> {
    let target = StrictAppTarget::new(path)?;
    Ok(BlockFilterPlan::for_target(&target))
}

#[cfg(windows)]
#[allow(dead_code)]
mod platform {
    use super::*;
    use std::ffi::c_void;
    use std::ptr::{null, null_mut};
    use serde::{Deserialize, Serialize};
    use windows_sys::core::{GUID, PCWSTR};
    use windows_sys::Win32::Foundation::HANDLE;
    use windows_sys::Win32::NetworkManagement::WindowsFilteringPlatform::*;

    #[derive(Debug, Clone, Serialize, Deserialize)]
    struct RecoveryMarker {
        version: u32,
        targets: Vec<String>,
    }

    fn recovery_marker_path() -> PathBuf {
        let root = std::env::var_os("ProgramData")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from(r"C:\ProgramData"));
        root.join("FlClashX").join(RECOVERY_MARKER_FILE_NAME)
    }

    fn load_recovery_marker() -> Result<RecoveryMarker, String> {
        let path = recovery_marker_path();
        if !path.exists() {
            return Ok(RecoveryMarker {
                version: 1,
                targets: Vec::new(),
            });
        }
        let text = fs::read_to_string(&path)
            .map_err(|error| format!("read strict recovery marker failed: {error}"))?;
        let marker: RecoveryMarker = serde_json::from_str(&text)
            .map_err(|error| format!("parse strict recovery marker failed: {error}"))?;
        if marker.version != 1 || marker.targets.len() > MAX_RECOVERY_TARGETS {
            return Err("strict recovery marker has an unsupported version or size".to_owned());
        }
        Ok(marker)
    }

    fn store_recovery_marker(marker: &RecoveryMarker) -> Result<(), String> {
        if marker.targets.len() > MAX_RECOVERY_TARGETS {
            return Err("strict recovery marker target limit reached".to_owned());
        }
        let path = recovery_marker_path();
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|error| {
                format!("create strict recovery marker directory failed: {error}")
            })?;
        }
        let temporary = path.with_extension(format!("json.{}.tmp", std::process::id()));
        let payload = serde_json::to_vec(marker)
            .map_err(|error| format!("serialize strict recovery marker failed: {error}"))?;
        fs::write(&temporary, payload)
            .map_err(|error| format!("write strict recovery marker failed: {error}"))?;
        fs::rename(&temporary, &path)
            .map_err(|error| format!("commit strict recovery marker failed: {error}"))
    }

    fn record_recovery_target(path: &Path) -> Result<(), String> {
        let mut marker = load_recovery_marker()?;
        let value = path.to_string_lossy().to_string();
        if !marker
            .targets
            .iter()
            .any(|target| target.eq_ignore_ascii_case(&value))
        {
            marker.targets.push(value);
            store_recovery_marker(&marker)?;
        }
        Ok(())
    }

    fn clear_recovery_target(path: &Path) -> Result<(), String> {
        let mut marker = load_recovery_marker()?;
        let value = path.to_string_lossy();
        marker
            .targets
            .retain(|target| !target.eq_ignore_ascii_case(&value));
        if marker.targets.is_empty() {
            let marker_path = recovery_marker_path();
            match fs::remove_file(marker_path) {
                Ok(()) => {}
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                Err(error) => return Err(format!("remove strict recovery marker failed: {error}")),
            }
            Ok(())
        } else {
            store_recovery_marker(&marker)
        }
    }

    pub struct InstalledBlockFilters {
        keys: [GUID; 2],
    }

    fn status(operation: &str, code: u32) -> String {
        format!("{operation} failed with Windows error {code} (0x{code:08x})")
    }

    fn wide_path(path: &Path) -> Result<Vec<u16>, String> {
        let value = path.as_os_str().to_string_lossy();
        if value.encode_utf16().any(|unit| unit == 0) {
            return Err("application path contains an embedded NUL".to_owned());
        }
        Ok(value.encode_utf16().chain(std::iter::once(0)).collect())
    }

    fn app_id(path: &Path) -> Result<Vec<u8>, String> {
        let wide = wide_path(path)?;
        let mut blob_ptr = null_mut();
        let code = unsafe { FwpmGetAppIdFromFileName0(wide.as_ptr() as PCWSTR, &mut blob_ptr) };
        if code != 0 {
            return Err(status("FwpmGetAppIdFromFileName0", code));
        }
        let Some(blob) = (!blob_ptr.is_null()).then(|| unsafe { &*blob_ptr }) else {
            return Err("FwpmGetAppIdFromFileName0 returned an empty app id".to_owned());
        };
        let bytes = if blob.size == 0 || blob.data.is_null() {
            Vec::new()
        } else {
            unsafe { std::slice::from_raw_parts(blob.data, blob.size as usize).to_vec() }
        };
        let mut raw = blob_ptr as *mut c_void;
        unsafe { FwpmFreeMemory0(&mut raw) };
        if bytes.is_empty() {
            return Err("Windows returned an empty app id".to_owned());
        }
        Ok(bytes)
    }

    fn filter_key_for(path: &Path, v6: bool, kind: &[u8]) -> GUID {
        let mut hasher = Sha256::new();
        hasher.update(path.to_string_lossy().to_ascii_lowercase().as_bytes());
        hasher.update([u8::from(v6)]);
        hasher.update(kind);
        let digest = hasher.finalize();
        GUID::from_u128(u128::from_be_bytes(
            digest[..16].try_into().expect("sha256 size"),
        ))
    }

    fn filter_key(path: &Path, v6: bool) -> GUID {
        filter_key_for(path, v6, b"block")
    }

    fn callout_filter_key(path: &Path, v6: bool) -> GUID {
        filter_key_for(path, v6, b"callout")
    }

    fn open_engine() -> Result<HANDLE, String> {
        let mut handle: HANDLE = 0;
        let code = unsafe { FwpmEngineOpen0(null(), 0, null(), null(), &mut handle) };
        if code != 0 {
            return Err(status("FwpmEngineOpen0", code));
        }
        if handle == 0 {
            return Err("FwpmEngineOpen0 returned a null engine handle".to_owned());
        }
        Ok(handle)
    }

    fn close_engine(handle: HANDLE) {
        unsafe {
            let _ = FwpmEngineClose0(handle);
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn add_filter_with_action(
        engine: HANDLE,
        path: &Path,
        app_id: &[u8],
        layer: GUID,
        key: GUID,
        display: &[u16],
        action_type: FWP_ACTION_TYPE,
        callout_key: GUID,
    ) -> Result<(), String> {
        let mut blob = FWP_BYTE_BLOB {
            size: app_id.len() as u32,
            data: app_id.as_ptr() as *mut u8,
        };
        let mut condition = FWPM_FILTER_CONDITION0 {
            fieldKey: FWPM_CONDITION_ALE_APP_ID,
            matchType: FWP_MATCH_EQUAL,
            conditionValue: FWP_CONDITION_VALUE0 {
                r#type: FWP_BYTE_BLOB_TYPE,
                Anonymous: FWP_CONDITION_VALUE0_0 {
                    byteBlob: &mut blob,
                },
            },
        };
        let filter = FWPM_FILTER0 {
            filterKey: key,
            displayData: FWPM_DISPLAY_DATA0 {
                name: display.as_ptr() as *mut u16,
                description: display.as_ptr() as *mut u16,
            },
            flags: FWPM_FILTER_FLAG_PERSISTENT,
            providerKey: null_mut(),
            providerData: FWP_BYTE_BLOB {
                size: 0,
                data: null_mut(),
            },
            layerKey: layer,
            subLayerKey: FWPM_SUBLAYER_UNIVERSAL,
            weight: FWP_VALUE0 {
                r#type: FWP_UINT8,
                Anonymous: FWP_VALUE0_0 { uint8: u8::MAX },
            },
            numFilterConditions: 1,
            filterCondition: &mut condition,
            action: FWPM_ACTION0 {
                r#type: action_type,
                Anonymous: FWPM_ACTION0_0 {
                    calloutKey: callout_key,
                },
            },
            Anonymous: FWPM_FILTER0_0 { rawContext: 0 },
            reserved: null_mut(),
            filterId: 0,
            effectiveWeight: FWP_VALUE0 {
                r#type: FWP_EMPTY,
                Anonymous: FWP_VALUE0_0 { uint64: null_mut() },
            },
        };
        let mut id = 0;
        let code = unsafe { FwpmFilterAdd0(engine, &filter, null_mut(), &mut id) };
        if code != 0 {
            return Err(format!(
                "{}: {}",
                path.display(),
                status("FwpmFilterAdd0", code)
            ));
        }
        Ok(())
    }

    fn add_filter(
        engine: HANDLE,
        path: &Path,
        app_id: &[u8],
        layer: GUID,
        key: GUID,
        display: &[u16],
    ) -> Result<(), String> {
        add_filter_with_action(
            engine,
            path,
            app_id,
            layer,
            key,
            display,
            FWP_ACTION_BLOCK,
            GUID::from_u128(0),
        )
    }

    pub fn install(plan: &BlockFilterPlan) -> Result<InstalledBlockFilters, String> {
        // Persist the intent before touching WFP. If the Helper or machine
        // dies after either filter is added, the next service start can remove
        // the deterministic keys instead of leaving an orphaned block.
        record_recovery_target(&plan.executable)?;
        let app_id = app_id(&plan.executable)?;
        let display = plan
            .display_name
            .encode_utf16()
            .chain(std::iter::once(0))
            .collect::<Vec<_>>();
        let engine = open_engine()?;
        let keys = [
            filter_key(&plan.executable, false),
            filter_key(&plan.executable, true),
        ];
        let result = (|| {
            add_filter(
                engine,
                &plan.executable,
                &app_id,
                FWPM_LAYER_ALE_AUTH_CONNECT_V4,
                keys[0],
                &display,
            )?;
            if let Err(error) = add_filter(
                engine,
                &plan.executable,
                &app_id,
                FWPM_LAYER_ALE_AUTH_CONNECT_V6,
                keys[1],
                &display,
            ) {
                unsafe {
                    let _ = FwpmFilterDeleteByKey0(engine, &keys[0]);
                }
                let _ = clear_recovery_target(&plan.executable);
                return Err(error);
            }
            Ok(InstalledBlockFilters { keys })
        })();
        close_engine(engine);
        if result.is_err() {
            let _ = clear_recovery_target(&plan.executable);
        }
        result
    }

    /// Installs terminating callout filters for the driver's ALE redirect
    /// callouts. This is broker plumbing only; the driver must be present and
    /// the callout data plane must be ready before a selected flow is allowed.
    pub fn install_callout_filters(
        plan: &BlockFilterPlan,
        callout_v4: GUID,
        callout_v6: GUID,
    ) -> Result<InstalledBlockFilters, String> {
        record_recovery_target(&plan.executable)?;
        let app_id = app_id(&plan.executable)?;
        let display = plan
            .display_name
            .encode_utf16()
            .chain(std::iter::once(0))
            .collect::<Vec<_>>();
        let engine = open_engine()?;
        let keys = [
            callout_filter_key(&plan.executable, false),
            callout_filter_key(&plan.executable, true),
        ];
        let result = (|| {
            add_filter_with_action(
                engine,
                &plan.executable,
                &app_id,
                FWPM_LAYER_ALE_CONNECT_REDIRECT_V4,
                keys[0],
                &display,
                FWP_ACTION_CALLOUT_TERMINATING,
                callout_v4,
            )?;
            if let Err(error) = add_filter_with_action(
                engine,
                &plan.executable,
                &app_id,
                FWPM_LAYER_ALE_CONNECT_REDIRECT_V6,
                keys[1],
                &display,
                FWP_ACTION_CALLOUT_TERMINATING,
                callout_v6,
            ) {
                unsafe {
                    let _ = FwpmFilterDeleteByKey0(engine, &keys[0]);
                }
                let _ = clear_recovery_target(&plan.executable);
                return Err(error);
            }
            Ok(InstalledBlockFilters { keys })
        })();
        close_engine(engine);
        if result.is_err() {
            let _ = clear_recovery_target(&plan.executable);
        }
        result
    }

    impl InstalledBlockFilters {
        pub fn remove(self) -> Result<(), String> {
            let engine = open_engine()?;
            let mut first_error = None;
            for key in self.keys {
                let code = unsafe { FwpmFilterDeleteByKey0(engine, &key) };
                if code != 0 && first_error.is_none() {
                    first_error = Some(status("FwpmFilterDeleteByKey0", code));
                }
            }
            close_engine(engine);
            first_error.map_or(Ok(()), Err)
        }
    }

    /// Removes the deterministic filters for a target, including filters that
    /// survived a Helper restart. `FWP_E_FILTER_NOT_FOUND` is treated as an
    /// idempotent success so recovery and uninstall can safely be retried.
    pub fn remove(plan: &BlockFilterPlan) -> Result<(), String> {
        const FWP_E_FILTER_NOT_FOUND: u32 = 0x8032_0003;
        let engine = open_engine()?;
        let keys = [
            filter_key(&plan.executable, false),
            filter_key(&plan.executable, true),
        ];
        let mut first_error = None;
        for key in keys {
            let code = unsafe { FwpmFilterDeleteByKey0(engine, &key) };
            if code != 0 && code != FWP_E_FILTER_NOT_FOUND && first_error.is_none() {
                first_error = Some(status("FwpmFilterDeleteByKey0", code));
            }
        }
        close_engine(engine);
        match first_error {
            Some(error) => Err(error),
            None => {
                clear_recovery_target(&plan.executable)?;
                Ok(())
            }
        }
    }

    /// Removes deterministic callout filters created by
    /// [`install_callout_filters`]. Missing filters are idempotent success.
    pub fn remove_callout_filters(plan: &BlockFilterPlan) -> Result<(), String> {
        const FWP_E_FILTER_NOT_FOUND: u32 = 0x8032_0003;
        let engine = open_engine()?;
        let keys = [
            callout_filter_key(&plan.executable, false),
            callout_filter_key(&plan.executable, true),
        ];
        let mut first_error = None;
        for key in keys {
            let code = unsafe { FwpmFilterDeleteByKey0(engine, &key) };
            if code != 0 && code != FWP_E_FILTER_NOT_FOUND && first_error.is_none() {
                first_error = Some(status("FwpmFilterDeleteByKey0", code));
            }
        }
        close_engine(engine);
        match first_error {
            Some(error) => Err(error),
            None => {
                clear_recovery_target(&plan.executable)?;
                Ok(())
            }
        }
    }

    /// Remove any deterministic strict filters left by a prior Helper crash,
    /// upgrade or interrupted uninstall. This function is intentionally
    /// fail-closed: a malformed marker is reported and left in place for the
    /// next recovery attempt instead of being silently discarded.
    pub fn recover_persistent_filters() -> Result<usize, String> {
        let marker = load_recovery_marker()?;
        let mut recovered = 0usize;
        let mut remaining = Vec::new();
        for raw_path in marker.targets {
            let path = PathBuf::from(&raw_path);
            let engine = match open_engine() {
                Ok(value) => value,
                Err(error) => {
                    remaining.push(raw_path);
                    return Err(error);
                }
            };
            let keys = [
                filter_key(&path, false),
                filter_key(&path, true),
                callout_filter_key(&path, false),
                callout_filter_key(&path, true),
            ];
            let mut failed = None;
            for key in keys {
                let code = unsafe { FwpmFilterDeleteByKey0(engine, &key) };
                if code != 0 && code != 0x8032_0003 && failed.is_none() {
                    failed = Some(status("FwpmFilterDeleteByKey0", code));
                }
            }
            close_engine(engine);
            if let Some(error) = failed {
                remaining.push(raw_path);
                return Err(error);
            }
            recovered = recovered.saturating_add(1);
        }
        if remaining.is_empty() {
            let marker_path = recovery_marker_path();
            let _ = fs::remove_file(marker_path);
        }
        Ok(recovered)
    }
}

#[cfg(windows)]
#[allow(unused_imports)]
pub use platform::{
    install, install_callout_filters, recover_persistent_filters, remove, remove_callout_filters,
    InstalledBlockFilters,
};

#[cfg(not(windows))]
pub fn install(_plan: &BlockFilterPlan) -> Result<(), String> {
    Err("Windows WFP backend is unavailable on this platform".to_owned())
}

#[cfg(not(windows))]
pub fn remove(_plan: &BlockFilterPlan) -> Result<(), String> {
    Err("Windows WFP backend is unavailable on this platform".to_owned())
}

#[cfg(not(windows))]
pub fn recover_persistent_filters() -> Result<usize, String> {
    Ok(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_executable(name: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let path = std::env::temp_dir().join(format!("flclashx-wfp-{nonce}-{name}.exe"));
        fs::write(&path, b"test").expect("write executable fixture");
        path
    }

    #[test]
    fn plan_requires_absolute_existing_executable() {
        let relative = PathBuf::from("edge.exe");
        assert!(StrictAppTarget::new(relative).is_err());
        let missing = std::env::temp_dir().join("flclashx-wfp-missing.exe");
        assert!(StrictAppTarget::new(missing).is_err());
    }

    #[test]
    fn plan_covers_both_ip_versions_and_is_bounded() {
        let path = temp_executable("edge");
        let target = StrictAppTarget::new(&path).expect("valid target");
        assert_eq!(target.executable, path.canonicalize().unwrap());
        let plan = build_block_filter_plan(&path).expect("valid plan");
        assert_eq!(plan.layers, ["ALE_AUTH_CONNECT_V4", "ALE_AUTH_CONNECT_V6"]);
        assert!(plan.display_name.len() <= MAX_DISPLAY_NAME_CHARS);
        let _ = fs::remove_file(path);
    }

    #[test]
    fn service_binaries_cannot_be_selected() {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("clock")
            .as_nanos();
        let directory = std::env::temp_dir().join(format!("flclashx-wfp-core-{nonce}"));
        fs::create_dir_all(&directory).expect("create service fixture directory");
        let path = directory.join("FlClashCore.exe");
        fs::write(&path, b"test").expect("write service fixture");
        assert!(StrictAppTarget::new(path.clone()).is_err());
        let _ = fs::remove_dir_all(directory);
    }

    #[test]
    fn display_name_truncation_is_unicode_safe() {
        let path = temp_executable(&"测".repeat(128));
        let target = StrictAppTarget::new(&path).expect("valid unicode target");
        let name = target.display_name();
        assert!(name.chars().count() <= MAX_DISPLAY_NAME_CHARS);
        let _ = fs::remove_file(path);
    }
}
