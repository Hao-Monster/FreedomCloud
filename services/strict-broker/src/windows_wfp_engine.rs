use std::collections::BTreeSet;
use std::ffi::c_void;
use std::ptr::{null, null_mut};
use std::slice;

use anyhow::{bail, Context, Result};
use flclash_strict_contract::StrictAction;
use windows_sys::core::GUID;
use windows_sys::Win32::Foundation::HANDLE;
use windows_sys::Win32::NetworkManagement::WindowsFilteringPlatform::{
    FwpmEngineClose0, FwpmEngineOpen0, FwpmFilterAdd0, FwpmFilterCreateEnumHandle0,
    FwpmFilterDeleteByKey0, FwpmFilterDestroyEnumHandle0, FwpmFilterEnum0, FwpmFreeMemory0,
    FwpmTransactionAbort0, FwpmTransactionBegin0, FwpmTransactionCommit0, FWPM_ACTION0,
    FWPM_ACTION0_0, FWPM_CONDITION_ALE_APP_ID, FWPM_DISPLAY_DATA0, FWPM_FILTER0, FWPM_FILTER0_0,
    FWPM_FILTER_CONDITION0, FWPM_FILTER_ENUM_TEMPLATE0, FWPM_FILTER_FLAG_CLEAR_ACTION_RIGHT,
    FWPM_FILTER_FLAG_INDEXED, FWPM_FILTER_FLAG_PERSISTENT, FWPM_LAYER_ALE_AUTH_CONNECT_V4,
    FWPM_LAYER_ALE_AUTH_CONNECT_V6, FWPM_LAYER_ALE_CONNECT_REDIRECT_V4,
    FWPM_LAYER_ALE_CONNECT_REDIRECT_V6, FWPM_SESSION0, FWPM_SESSION_FLAG_DYNAMIC,
    FWP_ACTION_CALLOUT_TERMINATING, FWP_BYTE_BLOB, FWP_BYTE_BLOB_TYPE, FWP_CONDITION_VALUE0,
    FWP_CONDITION_VALUE0_0, FWP_EMPTY, FWP_FILTER_ENUM_FULLY_CONTAINED, FWP_MATCH_EQUAL,
    FWP_VALUE0,
};
use windows_sys::Win32::System::Rpc::RPC_C_AUTHN_WINNT;

use crate::wfp_plan::{expected_callout_key, expected_filter_key};
use crate::{
    WfpCallout, WfpFilterLifetime, WfpFilterSpec, WfpLayer, WfpObjectKey,
    WindowsWfpFilterInventory, WindowsWfpFilterStore, MAX_VERIFIED_APP_ID_BYTES,
};

const ENUM_BATCH_SIZE: u32 = 256;
const TRANSACTION_WAIT_MILLIS: u32 = 3_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FilterClass {
    Guard,
    Redirect,
}

impl FilterClass {
    fn layers(self) -> [(WfpLayer, GUID); 2] {
        match self {
            Self::Guard => [
                (WfpLayer::AuthConnectV4, FWPM_LAYER_ALE_AUTH_CONNECT_V4),
                (WfpLayer::AuthConnectV6, FWPM_LAYER_ALE_AUTH_CONNECT_V6),
            ],
            Self::Redirect => [
                (
                    WfpLayer::ConnectRedirectV4,
                    FWPM_LAYER_ALE_CONNECT_REDIRECT_V4,
                ),
                (
                    WfpLayer::ConnectRedirectV6,
                    FWPM_LAYER_ALE_CONNECT_REDIRECT_V6,
                ),
            ],
        }
    }

    fn lifetime(self) -> WfpFilterLifetime {
        match self {
            Self::Guard => WfpFilterLifetime::Persistent,
            Self::Redirect => WfpFilterLifetime::Dynamic,
        }
    }

    fn flags(self) -> u32 {
        let common = FWPM_FILTER_FLAG_INDEXED | FWPM_FILTER_FLAG_CLEAR_ACTION_RIGHT;
        match self {
            Self::Guard => common | FWPM_FILTER_FLAG_PERSISTENT,
            Self::Redirect => common,
        }
    }

    fn accepts_layer(self, layer: WfpLayer) -> bool {
        matches!(
            (self, layer),
            (
                Self::Guard,
                WfpLayer::AuthConnectV4 | WfpLayer::AuthConnectV6
            ) | (
                Self::Redirect,
                WfpLayer::ConnectRedirectV4 | WfpLayer::ConnectRedirectV6
            )
        )
    }
}

/// Owns one persistent BFE session for fail-closed guards and one dynamic BFE
/// session for redirect filters. Construction opens the sessions but does not
/// install, remove, or otherwise mutate any WFP object.
pub struct WindowsWfpEngineStore {
    persistent: WfpEngineHandle,
    dynamic: WfpEngineHandle,
    provider_key: WfpObjectKey,
    sublayer_key: WfpObjectKey,
}

impl WindowsWfpEngineStore {
    pub fn open(provider_key: WfpObjectKey, sublayer_key: WfpObjectKey) -> Result<Self> {
        Ok(Self {
            persistent: WfpEngineHandle::open(false)
                .context("open persistent strict WFP engine session")?,
            dynamic: WfpEngineHandle::open(true)
                .context("open dynamic strict WFP engine session")?,
            provider_key,
            sublayer_key,
        })
    }

    fn replace(&mut self, class: FilterClass, filters: &[WfpFilterSpec]) -> Result<()> {
        validate_filter_specs(class, filters)?;
        let provider_key = self.provider_key;
        let sublayer_key = self.sublayer_key;
        let engine = self.engine(class);
        engine.transaction(|handle| {
            delete_owned_filters(handle, provider_key, sublayer_key, class)?;
            for filter in filters {
                add_filter(handle, provider_key, sublayer_key, class, filter)?;
            }
            Ok(())
        })
    }

    fn remove(&mut self, class: FilterClass) -> Result<()> {
        let provider_key = self.provider_key;
        let sublayer_key = self.sublayer_key;
        self.engine(class)
            .transaction(|handle| delete_owned_filters(handle, provider_key, sublayer_key, class))
    }

    fn engine(&mut self, class: FilterClass) -> &mut WfpEngineHandle {
        match class {
            FilterClass::Guard => &mut self.persistent,
            FilterClass::Redirect => &mut self.dynamic,
        }
    }

    fn enumerate(&self, class: FilterClass) -> Result<BTreeSet<WfpObjectKey>> {
        let engine = match class {
            FilterClass::Guard => &self.persistent,
            FilterClass::Redirect => &self.dynamic,
        };
        enumerate_owned_filters(
            engine.raw,
            self.provider_key,
            self.sublayer_key,
            class,
            true,
        )
    }
}

impl WindowsWfpFilterStore for WindowsWfpEngineStore {
    fn replace_guards(&mut self, filters: &[WfpFilterSpec]) -> Result<()> {
        self.replace(FilterClass::Guard, filters)
    }

    fn replace_redirects(&mut self, filters: &[WfpFilterSpec]) -> Result<()> {
        self.replace(FilterClass::Redirect, filters)
    }

    fn remove_redirects(&mut self) -> Result<()> {
        self.remove(FilterClass::Redirect)
    }

    fn remove_guards(&mut self) -> Result<()> {
        self.remove(FilterClass::Guard)
    }

    fn inventory(&mut self) -> Result<WindowsWfpFilterInventory> {
        Ok(WindowsWfpFilterInventory {
            guard_filter_keys: self.enumerate(FilterClass::Guard)?,
            redirect_filter_keys: self.enumerate(FilterClass::Redirect)?,
        })
    }
}

struct WfpEngineHandle {
    raw: HANDLE,
}

impl WfpEngineHandle {
    fn open(dynamic: bool) -> Result<Self> {
        let mut session = FWPM_SESSION0 {
            flags: if dynamic {
                FWPM_SESSION_FLAG_DYNAMIC
            } else {
                0
            },
            txnWaitTimeoutInMSec: TRANSACTION_WAIT_MILLIS,
            ..FWPM_SESSION0::default()
        };
        let name = wide(if dynamic {
            "FlClashX strict redirects"
        } else {
            "FlClashX strict guards"
        });
        session.displayData = FWPM_DISPLAY_DATA0 {
            name: name.as_ptr().cast_mut(),
            description: null_mut(),
        };
        let mut raw = null_mut();
        // SAFETY: all pointers remain valid for the synchronous call. The returned
        // handle is closed by Drop and no authentication identity is supplied for
        // the local RPC endpoint.
        let status =
            unsafe { FwpmEngineOpen0(null(), RPC_C_AUTHN_WINNT, null(), &session, &mut raw) };
        check_wfp(status, "FwpmEngineOpen0")?;
        if raw.is_null() {
            bail!("FwpmEngineOpen0 returned a null engine handle");
        }
        Ok(Self { raw })
    }

    fn transaction<T>(&mut self, operation: impl FnOnce(HANDLE) -> Result<T>) -> Result<T> {
        // SAFETY: raw is a live engine handle owned by this value.
        check_wfp(
            unsafe { FwpmTransactionBegin0(self.raw, 0) },
            "begin WFP transaction",
        )?;

        match operation(self.raw) {
            Ok(value) => {
                // SAFETY: the transaction was successfully started on this handle.
                let commit = unsafe { FwpmTransactionCommit0(self.raw) };
                if commit == 0 {
                    Ok(value)
                } else {
                    // A failed commit may leave the transaction active. Abort is a
                    // best-effort containment action and its status is included.
                    let abort = unsafe { FwpmTransactionAbort0(self.raw) };
                    bail!(
                        "commit WFP transaction failed (0x{commit:08x}); abort returned 0x{abort:08x}"
                    )
                }
            }
            Err(error) => {
                // SAFETY: the transaction was successfully started on this handle.
                let abort = unsafe { FwpmTransactionAbort0(self.raw) };
                if abort == 0 {
                    Err(error)
                } else {
                    bail!("WFP transaction failed: {error:#}; abort also failed (0x{abort:08x})")
                }
            }
        }
    }
}

impl Drop for WfpEngineHandle {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            // SAFETY: raw is owned by this value and is closed exactly once.
            unsafe { FwpmEngineClose0(self.raw) };
        }
    }
}

fn validate_filter_specs(class: FilterClass, filters: &[WfpFilterSpec]) -> Result<()> {
    let mut keys = BTreeSet::new();
    for filter in filters {
        if !class.accepts_layer(filter.layer())
            || filter.lifetime() != class.lifetime()
            || filter.callout() != callout_for_layer(filter.layer())
            || filter.callout_key() != expected_callout_key(filter.layer())
            || !filter.is_indexed()
            || !filter.clears_action_right()
            || filter.app_id().is_empty()
            || filter.app_id().len() > MAX_VERIFIED_APP_ID_BYTES
            || filter.key() != expected_filter_key(filter.layer(), filter.app_id())
            || (class == FilterClass::Redirect && filter.action() != StrictAction::Proxy)
        {
            bail!("strict WFP filter specification violates its sealed plan");
        }
        if !keys.insert(filter.key()) {
            bail!("strict WFP filter specification contains a duplicate key");
        }
    }
    Ok(())
}

fn add_filter(
    engine: HANDLE,
    provider_key: WfpObjectKey,
    sublayer_key: WfpObjectKey,
    class: FilterClass,
    spec: &WfpFilterSpec,
) -> Result<()> {
    let mut provider = object_key_to_guid(provider_key);
    let mut app_id = FWP_BYTE_BLOB {
        size: spec.app_id().len() as u32,
        data: spec.app_id().as_ptr().cast_mut(),
    };
    let mut condition = FWPM_FILTER_CONDITION0 {
        fieldKey: FWPM_CONDITION_ALE_APP_ID,
        matchType: FWP_MATCH_EQUAL,
        conditionValue: FWP_CONDITION_VALUE0 {
            r#type: FWP_BYTE_BLOB_TYPE,
            Anonymous: FWP_CONDITION_VALUE0_0 {
                byteBlob: &mut app_id,
            },
        },
    };
    let name = wide(match class {
        FilterClass::Guard => "FlClashX strict fail-closed guard",
        FilterClass::Redirect => "FlClashX strict application redirect",
    });
    let filter = FWPM_FILTER0 {
        filterKey: object_key_to_guid(spec.key()),
        displayData: FWPM_DISPLAY_DATA0 {
            name: name.as_ptr().cast_mut(),
            description: null_mut(),
        },
        flags: class.flags(),
        providerKey: &mut provider,
        layerKey: layer_guid(spec.layer()),
        subLayerKey: object_key_to_guid(sublayer_key),
        weight: FWP_VALUE0 {
            r#type: FWP_EMPTY,
            ..FWP_VALUE0::default()
        },
        numFilterConditions: 1,
        filterCondition: &mut condition,
        action: FWPM_ACTION0 {
            r#type: FWP_ACTION_CALLOUT_TERMINATING,
            Anonymous: FWPM_ACTION0_0 {
                calloutKey: object_key_to_guid(spec.callout_key()),
            },
        },
        Anonymous: FWPM_FILTER0_0 { rawContext: 0 },
        ..FWPM_FILTER0::default()
    };
    // SAFETY: the filter and every nested pointer remain valid for this
    // synchronous call. BFE copies the object on successful insertion.
    check_wfp(
        unsafe { FwpmFilterAdd0(engine, &filter, null_mut(), null_mut()) },
        "add strict WFP filter",
    )
}

fn delete_owned_filters(
    engine: HANDLE,
    provider_key: WfpObjectKey,
    sublayer_key: WfpObjectKey,
    class: FilterClass,
) -> Result<()> {
    let keys = enumerate_owned_filters(engine, provider_key, sublayer_key, class, false)?;
    for key in keys {
        let guid = object_key_to_guid(key);
        // SAFETY: engine is live and guid is valid for the call.
        check_wfp(
            unsafe { FwpmFilterDeleteByKey0(engine, &guid) },
            "delete strict WFP filter",
        )?;
    }
    Ok(())
}

fn enumerate_owned_filters(
    engine: HANDLE,
    provider_key: WfpObjectKey,
    sublayer_key: WfpObjectKey,
    class: FilterClass,
    validate_structure: bool,
) -> Result<BTreeSet<WfpObjectKey>> {
    let mut keys = BTreeSet::new();
    for (layer, layer_key) in class.layers() {
        let mut provider = object_key_to_guid(provider_key);
        let template = FWPM_FILTER_ENUM_TEMPLATE0 {
            providerKey: &mut provider,
            layerKey: layer_key,
            enumType: FWP_FILTER_ENUM_FULLY_CONTAINED,
            ..FWPM_FILTER_ENUM_TEMPLATE0::default()
        };
        let enum_handle = WfpEnumHandle::create(engine, &template)?;
        loop {
            let batch = enum_handle.next_batch()?;
            if batch.is_empty() {
                break;
            }
            for pointer in batch.entries() {
                if pointer.is_null() {
                    bail!("BFE returned a null filter entry");
                }
                // SAFETY: each pointer belongs to the live enumeration allocation.
                let filter = unsafe { &**pointer };
                let key = guid_to_object_key(filter.filterKey);
                if validate_structure {
                    validate_enumerated_filter(filter, provider_key, sublayer_key, class, layer)
                        .with_context(|| {
                            format!("validate enumerated strict WFP filter {key:?}")
                        })?;
                }
                keys.insert(key);
            }
        }
    }
    Ok(keys)
}

struct WfpEnumHandle {
    engine: HANDLE,
    raw: HANDLE,
}

impl WfpEnumHandle {
    fn create(engine: HANDLE, template: &FWPM_FILTER_ENUM_TEMPLATE0) -> Result<Self> {
        let mut raw = null_mut();
        // SAFETY: engine and template are valid for the synchronous call.
        check_wfp(
            unsafe { FwpmFilterCreateEnumHandle0(engine, template, &mut raw) },
            "create strict WFP filter enumerator",
        )?;
        if raw.is_null() {
            bail!("BFE returned a null filter enumeration handle");
        }
        Ok(Self { engine, raw })
    }

    fn next_batch(&self) -> Result<WfpFilterBatch> {
        let mut entries = null_mut();
        let mut count = 0;
        // SAFETY: the enumeration handle is live and both out pointers are valid.
        let status = unsafe {
            FwpmFilterEnum0(
                self.engine,
                self.raw,
                ENUM_BATCH_SIZE,
                &mut entries,
                &mut count,
            )
        };
        let batch = WfpFilterBatch { entries, count };
        check_wfp(status, "enumerate strict WFP filters")?;
        if count > ENUM_BATCH_SIZE || (count != 0 && entries.is_null()) {
            bail!("BFE returned an invalid filter enumeration batch");
        }
        Ok(batch)
    }
}

impl Drop for WfpEnumHandle {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            // SAFETY: raw belongs to engine and is destroyed exactly once.
            unsafe { FwpmFilterDestroyEnumHandle0(self.engine, self.raw) };
        }
    }
}

struct WfpFilterBatch {
    entries: *mut *mut FWPM_FILTER0,
    count: u32,
}

impl WfpFilterBatch {
    fn is_empty(&self) -> bool {
        self.count == 0
    }

    fn entries(&self) -> &[*mut FWPM_FILTER0] {
        if self.count == 0 {
            &[]
        } else {
            // SAFETY: construction validates the pointer/count pair before this is used.
            unsafe { slice::from_raw_parts(self.entries, self.count as usize) }
        }
    }
}

impl Drop for WfpFilterBatch {
    fn drop(&mut self) {
        if !self.entries.is_null() {
            let mut allocation = self.entries.cast::<c_void>();
            // SAFETY: BFE allocated this batch and requires FwpmFreeMemory0.
            unsafe { FwpmFreeMemory0(&mut allocation) };
        }
    }
}

fn validate_enumerated_filter(
    filter: &FWPM_FILTER0,
    provider_key: WfpObjectKey,
    sublayer_key: WfpObjectKey,
    class: FilterClass,
    layer: WfpLayer,
) -> Result<()> {
    if filter.providerKey.is_null()
        || !guid_eq(
            unsafe { &*filter.providerKey },
            &object_key_to_guid(provider_key),
        )
        || !guid_eq(&filter.layerKey, &layer_guid(layer))
        || !guid_eq(&filter.subLayerKey, &object_key_to_guid(sublayer_key))
        || filter.flags != class.flags()
        || filter.providerData.size != 0
        || !filter.providerData.data.is_null()
        || filter.weight.r#type != FWP_EMPTY
        || filter.numFilterConditions != 1
        || filter.filterCondition.is_null()
        || filter.action.r#type != FWP_ACTION_CALLOUT_TERMINATING
        || !filter.reserved.is_null()
    {
        bail!("strict WFP filter metadata is not canonical");
    }

    // SAFETY: the exact flags above exclude a provider context, so rawContext is active.
    if unsafe { filter.Anonymous.rawContext } != 0 {
        bail!("strict WFP filter raw context is not canonical");
    }

    // SAFETY: the action type above establishes the active calloutKey union member.
    let callout_key = unsafe { filter.action.Anonymous.calloutKey };
    if !guid_eq(
        &callout_key,
        &object_key_to_guid(expected_callout_key(layer)),
    ) {
        bail!("strict WFP filter references an unexpected callout");
    }

    // SAFETY: exactly one condition is present and its pointer was checked.
    let condition = unsafe { &*filter.filterCondition };
    if !guid_eq(&condition.fieldKey, &FWPM_CONDITION_ALE_APP_ID)
        || condition.matchType != FWP_MATCH_EQUAL
        || condition.conditionValue.r#type != FWP_BYTE_BLOB_TYPE
    {
        bail!("strict WFP filter App-ID condition is not canonical");
    }
    // SAFETY: the condition type above establishes the byteBlob union member.
    let blob = unsafe { condition.conditionValue.Anonymous.byteBlob };
    if blob.is_null() {
        bail!("strict WFP filter App-ID is missing");
    }
    // SAFETY: blob belongs to the live enumeration allocation.
    let blob = unsafe { &*blob };
    if blob.size == 0 || blob.size as usize > MAX_VERIFIED_APP_ID_BYTES || blob.data.is_null() {
        bail!("strict WFP filter App-ID is empty or oversized");
    }
    // SAFETY: the bounded blob remains live for the duration of validation.
    let app_id = unsafe { slice::from_raw_parts(blob.data, blob.size as usize) };
    if guid_to_object_key(filter.filterKey) != expected_filter_key(layer, app_id) {
        bail!("strict WFP filter key does not bind its App-ID condition");
    }
    Ok(())
}

fn layer_guid(layer: WfpLayer) -> GUID {
    match layer {
        WfpLayer::AuthConnectV4 => FWPM_LAYER_ALE_AUTH_CONNECT_V4,
        WfpLayer::AuthConnectV6 => FWPM_LAYER_ALE_AUTH_CONNECT_V6,
        WfpLayer::ConnectRedirectV4 => FWPM_LAYER_ALE_CONNECT_REDIRECT_V4,
        WfpLayer::ConnectRedirectV6 => FWPM_LAYER_ALE_CONNECT_REDIRECT_V6,
    }
}

fn callout_for_layer(layer: WfpLayer) -> WfpCallout {
    match layer {
        WfpLayer::AuthConnectV4 => WfpCallout::FailClosedGuardV4,
        WfpLayer::AuthConnectV6 => WfpCallout::FailClosedGuardV6,
        WfpLayer::ConnectRedirectV4 => WfpCallout::ConnectRedirectV4,
        WfpLayer::ConnectRedirectV6 => WfpCallout::ConnectRedirectV6,
    }
}

fn object_key_to_guid(key: WfpObjectKey) -> GUID {
    GUID::from_u128(u128::from_be_bytes(key.as_bytes()))
}

fn guid_to_object_key(guid: GUID) -> WfpObjectKey {
    let mut bytes = [0_u8; 16];
    bytes[..4].copy_from_slice(&guid.data1.to_be_bytes());
    bytes[4..6].copy_from_slice(&guid.data2.to_be_bytes());
    bytes[6..8].copy_from_slice(&guid.data3.to_be_bytes());
    bytes[8..].copy_from_slice(&guid.data4);
    WfpObjectKey::from_bytes(bytes)
}

fn guid_eq(left: &GUID, right: &GUID) -> bool {
    left.data1 == right.data1
        && left.data2 == right.data2
        && left.data3 == right.data3
        && left.data4 == right.data4
}

fn check_wfp(status: u32, operation: &str) -> Result<()> {
    if status == 0 {
        Ok(())
    } else {
        bail!("{operation} failed with WFP status 0x{status:08x}")
    }
}

fn wide(value: &str) -> Vec<u16> {
    value.encode_utf16().chain([0]).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn object_keys_round_trip_through_windows_guids() {
        let key = WfpObjectKey::from_bytes([
            0x8f, 0xcc, 0x2c, 0x06, 0x8e, 0xa4, 0x48, 0x9d, 0x9d, 0x7c, 0x84, 0x20, 0x67, 0x67,
            0x44, 0x01,
        ]);
        assert_eq!(guid_to_object_key(object_key_to_guid(key)), key);
    }

    #[test]
    fn filter_classes_separate_persistent_guards_from_dynamic_redirects() {
        assert_eq!(FilterClass::Guard.lifetime(), WfpFilterLifetime::Persistent);
        assert_eq!(FilterClass::Redirect.lifetime(), WfpFilterLifetime::Dynamic);
        assert_ne!(FilterClass::Guard.flags() & FWPM_FILTER_FLAG_PERSISTENT, 0);
        assert_eq!(
            FilterClass::Redirect.flags() & FWPM_FILTER_FLAG_PERSISTENT,
            0
        );
    }

    #[test]
    fn enumerated_filter_key_is_bound_to_its_app_id() {
        let provider_key = WfpObjectKey::from_bytes([1; 16]);
        let sublayer_key = WfpObjectKey::from_bytes([2; 16]);
        let layer = WfpLayer::AuthConnectV4;
        let app_id = [4_u8, 3, 2, 1];
        let mut blob = FWP_BYTE_BLOB {
            size: app_id.len() as u32,
            data: app_id.as_ptr().cast_mut(),
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
        let mut provider = object_key_to_guid(provider_key);
        let mut filter = FWPM_FILTER0 {
            filterKey: object_key_to_guid(expected_filter_key(layer, &app_id)),
            flags: FilterClass::Guard.flags(),
            providerKey: &mut provider,
            layerKey: layer_guid(layer),
            subLayerKey: object_key_to_guid(sublayer_key),
            weight: FWP_VALUE0 {
                r#type: FWP_EMPTY,
                ..FWP_VALUE0::default()
            },
            numFilterConditions: 1,
            filterCondition: &mut condition,
            action: FWPM_ACTION0 {
                r#type: FWP_ACTION_CALLOUT_TERMINATING,
                Anonymous: FWPM_ACTION0_0 {
                    calloutKey: object_key_to_guid(expected_callout_key(layer)),
                },
            },
            Anonymous: FWPM_FILTER0_0 { rawContext: 0 },
            ..FWPM_FILTER0::default()
        };

        validate_enumerated_filter(
            &filter,
            provider_key,
            sublayer_key,
            FilterClass::Guard,
            layer,
        )
        .unwrap();

        filter.filterKey = GUID::from_u128(9);
        assert!(validate_enumerated_filter(
            &filter,
            provider_key,
            sublayer_key,
            FilterClass::Guard,
            layer,
        )
        .is_err());
    }
}
