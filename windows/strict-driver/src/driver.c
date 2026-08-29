#include <ntddk.h>
#include <wdf.h>
#include <fwpsk.h>
#include <wdmsec.h>

#include "../include/flclash_strict_build.h"
#include "../include/flclash_strict_wire.h"
#include "policy.h"

DRIVER_INITIALIZE DriverEntry;
EVT_WDF_DRIVER_UNLOAD FcxEvtDriverUnload;
EVT_WDF_IO_QUEUE_IO_DEVICE_CONTROL FcxEvtIoDeviceControl;

static const UNICODE_STRING FcxDeviceName =
    RTL_CONSTANT_STRING(L"\\Device\\FlClashStrict");
static const UNICODE_STRING FcxDosDeviceName =
    RTL_CONSTANT_STRING(L"\\DosDevices\\FlClashStrict");
static const UINT8 FcxDriverBuildId[16] =
    FCX_STRICT_DRIVER_BUILD_ID_BYTES;

static const GUID FcxProviderKey = {
    0x8fcc2c06, 0x8ea4, 0x489d, {0x9d, 0x7c, 0x84, 0x20, 0x67, 0x67, 0x44, 0x01}
};
static const GUID FcxGuardV4CalloutKey = {
    0x4e5d3f4c, 0x0ef1, 0x4536, {0xac, 0xf0, 0x21, 0x18, 0xce, 0x60, 0x40, 0x31}
};
static const GUID FcxGuardV6CalloutKey = {
    0x0b699f20, 0x3867, 0x44a0, {0x93, 0x4b, 0x3e, 0xf8, 0x43, 0xc6, 0xf7, 0x32}
};
static const GUID FcxRedirectV4CalloutKey = {
    0xfa8a9ba7, 0x642c, 0x43ee, {0xa6, 0xe6, 0x71, 0xd0, 0x76, 0xc9, 0x53, 0x41}
};
static const GUID FcxRedirectV6CalloutKey = {
    0x9ad04f4e, 0x3342, 0x46c0, {0xa1, 0xa2, 0xf1, 0x54, 0x4d, 0xc1, 0xaf, 0x42}
};

#define FCX_STRICT_LEASE_POOL_TAG 'LCXF'

typedef struct _FCX_STRICT_LEASE_STATE {
    PEPROCESS BrokerProcess;
    UINT64 Generation;
    UINT64 ExpiresAtInterruptTime;
    UINT64 Revision;
    UINT8 PolicyDigest[32];
    UINT8 Nonce[16];
    FCX_STRICT_ENDPOINT TcpV4;
    FCX_STRICT_ENDPOINT TcpV6;
    FCX_STRICT_ENDPOINT UdpV4;
    FCX_STRICT_ENDPOINT UdpV6;
} FCX_STRICT_LEASE_STATE;

static WDFDEVICE FcxControlDevice;
static PEX_RUNDOWN_REF_CACHE_AWARE FcxPolicyRundown;
static volatile PVOID FcxPolicySnapshot;
static volatile LONG64 FcxPolicyGeneration;
static PEX_RUNDOWN_REF_CACHE_AWARE FcxLeaseRundown;
static volatile PVOID FcxLeaseState;
static volatile LONG64 FcxLeaseGeneration;
static FAST_MUTEX FcxLeaseMutationLock;
static BOOLEAN FcxProcessNotifyRegistered;
static UINT32 FcxCalloutIds[4];
static UINT32 FcxRegisteredCallouts;
static HANDLE FcxRedirectHandle;

static
VOID NTAPI
FcxGuardClassifyV4(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_opt_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    );

static
VOID NTAPI
FcxGuardClassifyV6(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_opt_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    );

static
VOID NTAPI
FcxRedirectClassifyV4(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_opt_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    );

static
VOID NTAPI
FcxRedirectClassifyV6(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_opt_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    );

static
VOID NTAPI
FcxProcessNotify(
    _Inout_ PEPROCESS Process,
    _In_ HANDLE ProcessId,
    _Inout_opt_ PPS_CREATE_NOTIFY_INFO CreateInfo
    );

static
NTSTATUS NTAPI
FcxCalloutNotify(
    _In_ FWPS_CALLOUT_NOTIFY_TYPE NotifyType,
    _In_ const GUID *FilterKey,
    _Inout_ FWPS_FILTER1 *Filter
    )
{
    UNREFERENCED_PARAMETER(NotifyType);
    UNREFERENCED_PARAMETER(FilterKey);
    UNREFERENCED_PARAMETER(Filter);
    return STATUS_SUCCESS;
}

static
VOID
FcxBlockClassify(
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    if ((ClassifyOut->rights & FWPS_RIGHT_ACTION_WRITE) != 0) {
        ClassifyOut->actionType = FWP_ACTION_BLOCK;
        ClassifyOut->rights &= ~FWPS_RIGHT_ACTION_WRITE;
    }
}

static
VOID
FcxClassifySelectedApp(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ UINT32 AppIdField,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    const FWP_BYTE_BLOB *appId;
    const FCX_STRICT_POLICY_SNAPSHOT *snapshot;

    if ((ClassifyOut->rights & FWPS_RIGHT_ACTION_WRITE) == 0) {
        return;
    }
    FcxBlockClassify(ClassifyOut);
    if (FcxPolicyRundown == NULL ||
        !ExAcquireRundownProtectionCacheAware(FcxPolicyRundown)) {
        return;
    }

    snapshot = (const FCX_STRICT_POLICY_SNAPSHOT *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxPolicySnapshot,
        NULL,
        NULL);
    if (snapshot != NULL && AppIdField < IncomingValues->valueCount) {
        const FWP_VALUE0 *value = &IncomingValues->incomingValue[AppIdField].value;
        appId = value->type == FWP_BYTE_BLOB_TYPE ? value->byteBlob : NULL;
        if (appId != NULL && appId->data != NULL && appId->size != 0 &&
            appId->size <= FCX_STRICT_MAX_APP_ID_BYTES) {
            // Lookup is intentionally performed even while proxy actions remain
            // blocked. It proves the immutable O(1) identity path before redirect
            // capabilities can be enabled by a later endpoint-lease milestone.
            (VOID)FcxStrictPolicyFind(snapshot, appId->data, appId->size);
        }
    }
    ExReleaseRundownProtectionCacheAware(FcxPolicyRundown);
}

static
VOID NTAPI
FcxGuardClassifyV4(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_opt_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    UNREFERENCED_PARAMETER(IncomingMetadata);
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(ClassifyContext);
    UNREFERENCED_PARAMETER(Filter);
    UNREFERENCED_PARAMETER(FlowContext);
    FcxClassifySelectedApp(IncomingValues,
                           FWPS_FIELD_ALE_AUTH_CONNECT_V4_ALE_APP_ID,
                           ClassifyOut);
}

static
VOID NTAPI
FcxGuardClassifyV6(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_opt_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    UNREFERENCED_PARAMETER(IncomingMetadata);
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(ClassifyContext);
    UNREFERENCED_PARAMETER(Filter);
    UNREFERENCED_PARAMETER(FlowContext);
    FcxClassifySelectedApp(IncomingValues,
                           FWPS_FIELD_ALE_AUTH_CONNECT_V6_ALE_APP_ID,
                           ClassifyOut);
}

static
VOID NTAPI
FcxRedirectClassifyV4(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_opt_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    UNREFERENCED_PARAMETER(IncomingMetadata);
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(ClassifyContext);
    UNREFERENCED_PARAMETER(Filter);
    UNREFERENCED_PARAMETER(FlowContext);
    FcxClassifySelectedApp(IncomingValues,
                           FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_ALE_APP_ID,
                           ClassifyOut);
}

static
VOID NTAPI
FcxRedirectClassifyV6(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_opt_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    UNREFERENCED_PARAMETER(IncomingMetadata);
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(ClassifyContext);
    UNREFERENCED_PARAMETER(Filter);
    UNREFERENCED_PARAMETER(FlowContext);
    FcxClassifySelectedApp(IncomingValues,
                           FWPS_FIELD_ALE_CONNECT_REDIRECT_V6_ALE_APP_ID,
                           ClassifyOut);
}

static
BOOLEAN
FcxBytesAreZero(
    _In_reads_bytes_(Bytes) const UINT8 *Buffer,
    _In_ UINT32 Bytes
    )
{
    UINT32 index;

    for (index = 0; index < Bytes; ++index) {
        if (Buffer[index] != 0) {
            return FALSE;
        }
    }
    return TRUE;
}

static
BOOLEAN
FcxValidateEndpoint(
    _In_ const FCX_STRICT_ENDPOINT *Endpoint,
    _In_ BOOLEAN Ipv6
    )
{
    static const UINT8 LoopbackV4[16] = {
        127, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    };
    static const UINT8 LoopbackV6[16] = {
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1
    };
    const UINT8 *expected = Ipv6 ? LoopbackV6 : LoopbackV4;

    return Endpoint->Port != 0 &&
           Endpoint->Reserved == 0 &&
           RtlCompareMemory(Endpoint->Address,
                            expected,
                            sizeof(Endpoint->Address)) == sizeof(Endpoint->Address);
}

static
BOOLEAN
FcxLeaseMatchesPolicy(
    _In_ const FCX_STRICT_ENDPOINT_LEASE *Lease
    )
{
    const FCX_STRICT_POLICY_SNAPSHOT *snapshot;
    BOOLEAN matches = FALSE;

    if (FcxPolicyRundown == NULL ||
        !ExAcquireRundownProtectionCacheAware(FcxPolicyRundown)) {
        return FALSE;
    }
    snapshot = (const FCX_STRICT_POLICY_SNAPSHOT *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxPolicySnapshot,
        NULL,
        NULL);
    if (snapshot != NULL &&
        snapshot->Revision == Lease->Revision &&
        RtlCompareMemory(snapshot->PolicyDigest,
                         Lease->PolicyDigest,
                         sizeof(snapshot->PolicyDigest)) == sizeof(snapshot->PolicyDigest)) {
        matches = TRUE;
    }
    ExReleaseRundownProtectionCacheAware(FcxPolicyRundown);
    return matches;
}

static
VOID
FcxDestroyLease(
    _Frees_ptr_opt_ FCX_STRICT_LEASE_STATE *Lease
    )
{
    PEPROCESS process;

    if (Lease == NULL) {
        return;
    }
    process = Lease->BrokerProcess;
    RtlSecureZeroMemory(Lease, sizeof(*Lease));
    ExFreePoolWithTag(Lease, FCX_STRICT_LEASE_POOL_TAG);
    if (process != NULL) {
        ObDereferenceObject(process);
    }
}

static
VOID
FcxReleaseLeaseLocked(
    VOID
    )
{
    FCX_STRICT_LEASE_STATE *oldLease;

    oldLease = (FCX_STRICT_LEASE_STATE *)InterlockedExchangePointer(
        (PVOID volatile *)&FcxLeaseState,
        NULL);
    if (FcxLeaseRundown != NULL) {
        ExWaitForRundownProtectionReleaseCacheAware(FcxLeaseRundown);
    }
    FcxDestroyLease(oldLease);
    if (FcxLeaseRundown != NULL) {
        ExRundownCompletedCacheAware(FcxLeaseRundown);
        ExReInitializeRundownProtectionCacheAware(FcxLeaseRundown);
    }
}

static
VOID
FcxReleaseLease(
    VOID
    )
{
    ExAcquireFastMutex(&FcxLeaseMutationLock);
    FcxReleaseLeaseLocked();
    ExReleaseFastMutex(&FcxLeaseMutationLock);
}

static
VOID
FcxReplaceLease(
    _In_ FCX_STRICT_LEASE_STATE *NewLease
    )
{
    FCX_STRICT_LEASE_STATE *oldLease;

    ExAcquireFastMutex(&FcxLeaseMutationLock);
    oldLease = (FCX_STRICT_LEASE_STATE *)InterlockedExchangePointer(
        (PVOID volatile *)&FcxLeaseState,
        NewLease);
    ExWaitForRundownProtectionReleaseCacheAware(FcxLeaseRundown);
    FcxDestroyLease(oldLease);
    ExRundownCompletedCacheAware(FcxLeaseRundown);
    ExReInitializeRundownProtectionCacheAware(FcxLeaseRundown);
    ExReleaseFastMutex(&FcxLeaseMutationLock);
}

static
NTSTATUS
FcxBuildLease(
    _In_ WDFREQUEST Request,
    _In_reads_bytes_(InputBytes) const VOID *Input,
    _In_ size_t InputBytes,
    _Outptr_ FCX_STRICT_LEASE_STATE **LeaseState
    )
{
    NTSTATUS status;
    FCX_STRICT_ENDPOINT_LEASE lease;
    FCX_STRICT_LEASE_STATE *state;
    PEPROCESS process;
    ULONG processId;
    LONG64 generation;
    UINT64 now;
    UINT64 duration;

    *LeaseState = NULL;
    if (InputBytes != sizeof(lease)) {
        return STATUS_INVALID_BUFFER_SIZE;
    }
    RtlCopyMemory(&lease, Input, sizeof(lease));
    if (lease.Magic != FCX_STRICT_WIRE_MAGIC ||
        lease.Protocol != FCX_STRICT_WIRE_PROTOCOL ||
        lease.LeaseBytes != FCX_STRICT_ENDPOINT_LEASE_BYTES ||
        lease.TtlMillis < FCX_STRICT_MIN_LEASE_MILLIS ||
        lease.TtlMillis > FCX_STRICT_MAX_LEASE_MILLIS ||
        lease.Reserved0 != 0 ||
        lease.Revision == 0 ||
        FcxBytesAreZero(lease.PolicyDigest, sizeof(lease.PolicyDigest)) ||
        FcxBytesAreZero(lease.Nonce, sizeof(lease.Nonce)) ||
        !FcxValidateEndpoint(&lease.TcpV4, FALSE) ||
        !FcxValidateEndpoint(&lease.TcpV6, TRUE) ||
        !FcxValidateEndpoint(&lease.UdpV4, FALSE) ||
        !FcxValidateEndpoint(&lease.UdpV6, TRUE) ||
        !FcxBytesAreZero(lease.Reserved1, sizeof(lease.Reserved1)) ||
        !FcxLeaseMatchesPolicy(&lease)) {
        return STATUS_INVALID_PARAMETER;
    }

    processId = WdfRequestGetRequestorProcessId(Request);
    if (processId == 0) {
        return STATUS_ACCESS_DENIED;
    }
    process = NULL;
    status = PsLookupProcessByProcessId(ULongToHandle(processId), &process);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    if (PsGetProcessExitStatus(process) != STATUS_PENDING) {
        ObDereferenceObject(process);
        return STATUS_PROCESS_IS_TERMINATING;
    }

    state = (FCX_STRICT_LEASE_STATE *)ExAllocatePool2(
        POOL_FLAG_NON_PAGED,
        sizeof(*state),
        FCX_STRICT_LEASE_POOL_TAG);
    if (state == NULL) {
        ObDereferenceObject(process);
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    RtlZeroMemory(state, sizeof(*state));
    state->BrokerProcess = process;
    generation = InterlockedIncrement64(&FcxLeaseGeneration);
    if (generation <= 0) {
        InterlockedDecrement64(&FcxLeaseGeneration);
        FcxDestroyLease(state);
        return STATUS_INTEGER_OVERFLOW;
    }
    now = KeQueryInterruptTime();
    duration = (UINT64)lease.TtlMillis * 10000ull;
    if (now > MAXULONGLONG - duration) {
        InterlockedDecrement64(&FcxLeaseGeneration);
        FcxDestroyLease(state);
        return STATUS_INTEGER_OVERFLOW;
    }
    state->Generation = (UINT64)generation;
    state->ExpiresAtInterruptTime = now + duration;
    state->Revision = lease.Revision;
    RtlCopyMemory(state->PolicyDigest,
                  lease.PolicyDigest,
                  sizeof(state->PolicyDigest));
    RtlCopyMemory(state->Nonce, lease.Nonce, sizeof(state->Nonce));
    state->TcpV4 = lease.TcpV4;
    state->TcpV6 = lease.TcpV6;
    state->UdpV4 = lease.UdpV4;
    state->UdpV6 = lease.UdpV6;
    *LeaseState = state;
    return STATUS_SUCCESS;
}

static
VOID
FcxExpireLeaseIfNeeded(
    VOID
    )
{
    FCX_STRICT_LEASE_STATE *lease;

    ExAcquireFastMutex(&FcxLeaseMutationLock);
    lease = (FCX_STRICT_LEASE_STATE *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxLeaseState,
        NULL,
        NULL);
    if (lease != NULL &&
        (lease->ExpiresAtInterruptTime <= KeQueryInterruptTime() ||
         PsGetProcessExitStatus(lease->BrokerProcess) != STATUS_PENDING)) {
        FcxReleaseLeaseLocked();
    }
    ExReleaseFastMutex(&FcxLeaseMutationLock);
}

static
VOID NTAPI
FcxProcessNotify(
    _Inout_ PEPROCESS Process,
    _In_ HANDLE ProcessId,
    _Inout_opt_ PPS_CREATE_NOTIFY_INFO CreateInfo
    )
{
    FCX_STRICT_LEASE_STATE *lease;

    UNREFERENCED_PARAMETER(ProcessId);
    if (CreateInfo != NULL) {
        return;
    }
    lease = (FCX_STRICT_LEASE_STATE *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxLeaseState,
        NULL,
        NULL);
    if (lease == NULL) {
        return;
    }
    ExAcquireFastMutex(&FcxLeaseMutationLock);
    lease = (FCX_STRICT_LEASE_STATE *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxLeaseState,
        NULL,
        NULL);
    if (lease != NULL && lease->BrokerProcess == Process) {
        FcxReleaseLeaseLocked();
    }
    ExReleaseFastMutex(&FcxLeaseMutationLock);
}

static
VOID
FcxReleasePolicy(
    VOID
    )
{
    FCX_STRICT_POLICY_SNAPSHOT *oldSnapshot;

    oldSnapshot = (FCX_STRICT_POLICY_SNAPSHOT *)InterlockedExchangePointer(
        (PVOID volatile *)&FcxPolicySnapshot,
        NULL);
    if (FcxPolicyRundown != NULL) {
        ExWaitForRundownProtectionReleaseCacheAware(FcxPolicyRundown);
    }
    FcxStrictPolicyDestroy(oldSnapshot);
    if (FcxPolicyRundown != NULL) {
        ExRundownCompletedCacheAware(FcxPolicyRundown);
        ExReInitializeRundownProtectionCacheAware(FcxPolicyRundown);
    }
}

static
VOID
FcxReplacePolicy(
    _In_ FCX_STRICT_POLICY_SNAPSHOT *NewSnapshot
    )
{
    FCX_STRICT_POLICY_SNAPSHOT *oldSnapshot;

    oldSnapshot = (FCX_STRICT_POLICY_SNAPSHOT *)InterlockedExchangePointer(
        (PVOID volatile *)&FcxPolicySnapshot,
        NewSnapshot);
    ExWaitForRundownProtectionReleaseCacheAware(FcxPolicyRundown);
    FcxStrictPolicyDestroy(oldSnapshot);
    ExRundownCompletedCacheAware(FcxPolicyRundown);
    ExReInitializeRundownProtectionCacheAware(FcxPolicyRundown);
}

static
VOID
FcxFillDriverSnapshot(
    _Out_ FCX_STRICT_DRIVER_SNAPSHOT *Output
    )
{
    const FCX_STRICT_POLICY_SNAPSHOT *snapshot;
    const FCX_STRICT_LEASE_STATE *lease;
    UINT64 now;
    UINT64 remaining;

    RtlZeroMemory(Output, sizeof(*Output));
    Output->Magic = FCX_STRICT_WIRE_MAGIC;
    Output->Protocol = FCX_STRICT_WIRE_PROTOCOL;
    Output->SnapshotBytes = FCX_STRICT_SNAPSHOT_BYTES;
    Output->Generation = (UINT64)InterlockedCompareExchange64(
        &FcxPolicyGeneration,
        0,
        0);
    RtlCopyMemory(Output->DriverBuildId,
                  FcxDriverBuildId,
                  sizeof(Output->DriverBuildId));

    if (!ExAcquireRundownProtectionCacheAware(FcxPolicyRundown)) {
        return;
    }
    snapshot = (const FCX_STRICT_POLICY_SNAPSHOT *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxPolicySnapshot,
        NULL,
        NULL);
    if (snapshot != NULL) {
        Output->Flags = FCX_STRICT_SNAPSHOT_FLAG_LOADED;
        Output->RuleCount = snapshot->RuleCount;
        Output->Revision = snapshot->Revision;
        RtlCopyMemory(Output->PolicyDigest,
                      snapshot->PolicyDigest,
                      sizeof(Output->PolicyDigest));
        if (FcxRegisteredCallouts >= 2) {
            Output->Capabilities = FCX_STRICT_CAP_PERSISTENT_FAIL_CLOSED;
        }
    }
    ExReleaseRundownProtectionCacheAware(FcxPolicyRundown);

    FcxExpireLeaseIfNeeded();
    if ((Output->Flags & FCX_STRICT_SNAPSHOT_FLAG_LOADED) == 0 ||
        !ExAcquireRundownProtectionCacheAware(FcxLeaseRundown)) {
        return;
    }
    lease = (const FCX_STRICT_LEASE_STATE *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxLeaseState,
        NULL,
        NULL);
    now = KeQueryInterruptTime();
    if (lease != NULL &&
        lease->ExpiresAtInterruptTime > now &&
        lease->Revision == Output->Revision &&
        RtlCompareMemory(lease->PolicyDigest,
                         Output->PolicyDigest,
                         sizeof(Output->PolicyDigest)) == sizeof(Output->PolicyDigest)) {
        remaining = lease->ExpiresAtInterruptTime - now;
        Output->Flags |= FCX_STRICT_SNAPSHOT_FLAG_LEASE_ACTIVE;
        Output->LeaseGeneration = lease->Generation;
        Output->LeaseRemainingMillis = (UINT32)((remaining + 9999ull) / 10000ull);
        RtlCopyMemory(Output->LeaseNonce,
                      lease->Nonce,
                      sizeof(Output->LeaseNonce));
    }
    ExReleaseRundownProtectionCacheAware(FcxLeaseRundown);
}

VOID
FcxEvtIoDeviceControl(
    _In_ WDFQUEUE Queue,
    _In_ WDFREQUEST Request,
    _In_ size_t OutputBufferLength,
    _In_ size_t InputBufferLength,
    _In_ ULONG IoControlCode
    )
{
    NTSTATUS status;
    FCX_STRICT_DRIVER_SNAPSHOT *output;
    size_t outputBytes;
    size_t information = 0;

    UNREFERENCED_PARAMETER(Queue);
    PAGED_CODE();

    if (OutputBufferLength < sizeof(*output)) {
        WdfRequestComplete(Request, STATUS_BUFFER_TOO_SMALL);
        return;
    }
    status = WdfRequestRetrieveOutputBuffer(Request,
                                             sizeof(*output),
                                             (PVOID *)&output,
                                             &outputBytes);
    if (!NT_SUCCESS(status)) {
        WdfRequestComplete(Request, status);
        return;
    }

    switch (IoControlCode) {
    case IOCTL_FCX_STRICT_UPLOAD_POLICY:
    {
        const VOID *input;
        size_t inputBytes;
        FCX_STRICT_POLICY_SNAPSHOT *newSnapshot = NULL;

        if (InputBufferLength < sizeof(FCX_STRICT_POLICY_HEADER) ||
            InputBufferLength > FCX_STRICT_MAX_POLICY_BYTES) {
            status = STATUS_INVALID_BUFFER_SIZE;
            break;
        }
        status = WdfRequestRetrieveInputBuffer(Request,
                                                sizeof(FCX_STRICT_POLICY_HEADER),
                                                (PVOID *)&input,
                                                &inputBytes);
        if (!NT_SUCCESS(status) || inputBytes != InputBufferLength) {
            break;
        }
        status = FcxStrictPolicyBuild(input,
                                      (UINT32)inputBytes,
                                      &newSnapshot);
        if (!NT_SUCCESS(status)) {
            break;
        }
        FcxReleaseLease();
        FcxReplacePolicy(newSnapshot);
        InterlockedIncrement64(&FcxPolicyGeneration);
        status = STATUS_SUCCESS;
        break;
    }
    case IOCTL_FCX_STRICT_UNLOAD_POLICY:
        if (InputBufferLength != 0) {
            status = STATUS_INVALID_BUFFER_SIZE;
            break;
        }
        FcxReleaseLease();
        FcxReleasePolicy();
        InterlockedIncrement64(&FcxPolicyGeneration);
        status = STATUS_SUCCESS;
        break;
    case IOCTL_FCX_STRICT_QUERY_POLICY:
        status = InputBufferLength == 0 ? STATUS_SUCCESS :
                                          STATUS_INVALID_BUFFER_SIZE;
        break;
    case IOCTL_FCX_STRICT_ACTIVATE_LEASE:
    {
        const VOID *input;
        size_t inputBytes;
        FCX_STRICT_LEASE_STATE *newLease = NULL;

        if (InputBufferLength != sizeof(FCX_STRICT_ENDPOINT_LEASE)) {
            status = STATUS_INVALID_BUFFER_SIZE;
            break;
        }
        status = WdfRequestRetrieveInputBuffer(Request,
                                                sizeof(FCX_STRICT_ENDPOINT_LEASE),
                                                (PVOID *)&input,
                                                &inputBytes);
        if (!NT_SUCCESS(status) || inputBytes != InputBufferLength) {
            break;
        }
        status = FcxBuildLease(Request, input, inputBytes, &newLease);
        if (!NT_SUCCESS(status)) {
            break;
        }
        FcxReplaceLease(newLease);
        status = STATUS_SUCCESS;
        break;
    }
    case IOCTL_FCX_STRICT_REVOKE_LEASE:
        if (InputBufferLength != 0) {
            status = STATUS_INVALID_BUFFER_SIZE;
            break;
        }
        FcxReleaseLease();
        status = STATUS_SUCCESS;
        break;
    default:
        status = STATUS_INVALID_DEVICE_REQUEST;
        break;
    }

    if (NT_SUCCESS(status)) {
        FcxFillDriverSnapshot(output);
        information = sizeof(*output);
    }
    WdfRequestCompleteWithInformation(Request, status, information);
}

static
NTSTATUS
FcxCreateRedirectHandle(
    VOID
    )
{
    PAGED_CODE();
    if (FcxRedirectHandle != NULL) {
        return STATUS_INVALID_DEVICE_STATE;
    }
    return FwpsRedirectHandleCreate0(&FcxProviderKey,
                                     0,
                                     &FcxRedirectHandle);
}

static
VOID
FcxDestroyRedirectHandle(
    VOID
    )
{
    PAGED_CODE();
    if (FcxRedirectHandle != NULL) {
        FwpsRedirectHandleDestroy0(FcxRedirectHandle);
        FcxRedirectHandle = NULL;
    }
}

static
NTSTATUS
FcxRegisterCallouts(
    _In_ PDEVICE_OBJECT DeviceObject
    )
{
    NTSTATUS status;
    FWPS_CALLOUT1 callout;
    const GUID *keys[4] = {
        &FcxGuardV4CalloutKey,
        &FcxGuardV6CalloutKey,
        &FcxRedirectV4CalloutKey,
        &FcxRedirectV6CalloutKey
    };
    FWPS_CALLOUT_CLASSIFY_FN1 classifyFunctions[4] = {
        FcxGuardClassifyV4,
        FcxGuardClassifyV6,
        FcxRedirectClassifyV4,
        FcxRedirectClassifyV6
    };
    UINT32 index;

    PAGED_CODE();
    RtlZeroMemory(FcxCalloutIds, sizeof(FcxCalloutIds));
    FcxRegisteredCallouts = 0;
    for (index = 0; index < RTL_NUMBER_OF(keys); ++index) {
        RtlZeroMemory(&callout, sizeof(callout));
        callout.calloutKey = *keys[index];
        callout.classifyFn = classifyFunctions[index];
        callout.notifyFn = FcxCalloutNotify;
        status = FwpsCalloutRegister1(DeviceObject,
                                      &callout,
                                      &FcxCalloutIds[index]);
        if (!NT_SUCCESS(status)) {
            return status;
        }
        ++FcxRegisteredCallouts;
    }
    return STATUS_SUCCESS;
}

static
VOID
FcxUnregisterCallouts(
    VOID
    )
{
    while (FcxRegisteredCallouts != 0) {
        UINT32 index = --FcxRegisteredCallouts;
        (VOID)FwpsCalloutUnregisterById0(FcxCalloutIds[index]);
        FcxCalloutIds[index] = 0;
    }
}

VOID
FcxEvtDriverUnload(
    _In_ WDFDRIVER Driver
    )
{
    UNREFERENCED_PARAMETER(Driver);
    PAGED_CODE();

    FcxUnregisterCallouts();
    FcxDestroyRedirectHandle();
    if (FcxProcessNotifyRegistered) {
        (VOID)PsSetCreateProcessNotifyRoutineEx(FcxProcessNotify, TRUE);
        FcxProcessNotifyRegistered = FALSE;
    }
    FcxReleaseLease();
    FcxReleasePolicy();
    if (FcxLeaseRundown != NULL) {
        ExFreeCacheAwareRundownProtection(FcxLeaseRundown);
        FcxLeaseRundown = NULL;
    }
    if (FcxPolicyRundown != NULL) {
        ExFreeCacheAwareRundownProtection(FcxPolicyRundown);
        FcxPolicyRundown = NULL;
    }
    FcxControlDevice = NULL;
}

_Use_decl_annotations_
NTSTATUS
DriverEntry(
    PDRIVER_OBJECT DriverObject,
    PUNICODE_STRING RegistryPath
    )
{
    NTSTATUS status;
    WDF_DRIVER_CONFIG driverConfig;
    WDFDRIVER driver;
    PWDFDEVICE_INIT deviceInit = NULL;
    WDF_IO_QUEUE_CONFIG queueConfig;
    WDF_OBJECT_ATTRIBUTES attributes;
    DECLARE_CONST_UNICODE_STRING(deviceSddl, L"D:P(A;;GA;;;SY)");

    PAGED_CODE();
    WDF_DRIVER_CONFIG_INIT(&driverConfig, WDF_NO_EVENT_CALLBACK);
    driverConfig.DriverInitFlags |= WdfDriverInitNonPnpDriver;
    driverConfig.EvtDriverUnload = FcxEvtDriverUnload;
    WDF_OBJECT_ATTRIBUTES_INIT(&attributes);
    status = WdfDriverCreate(DriverObject,
                             RegistryPath,
                             &attributes,
                             &driverConfig,
                             &driver);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    ExInitializeFastMutex(&FcxLeaseMutationLock);

    FcxPolicyRundown = ExAllocateCacheAwareRundownProtection(
        NonPagedPoolNx,
        FCX_STRICT_POOL_TAG);
    if (FcxPolicyRundown == NULL) {
        status = STATUS_INSUFFICIENT_RESOURCES;
        goto Failure;
    }
    FcxLeaseRundown = ExAllocateCacheAwareRundownProtection(
        NonPagedPoolNx,
        FCX_STRICT_LEASE_POOL_TAG);
    if (FcxLeaseRundown == NULL) {
        status = STATUS_INSUFFICIENT_RESOURCES;
        goto Failure;
    }
    status = PsSetCreateProcessNotifyRoutineEx(FcxProcessNotify, FALSE);
    if (!NT_SUCCESS(status)) {
        goto Failure;
    }
    FcxProcessNotifyRegistered = TRUE;

    deviceInit = WdfControlDeviceInitAllocate(driver, &deviceSddl);
    if (deviceInit == NULL) {
        status = STATUS_INSUFFICIENT_RESOURCES;
        goto Failure;
    }
    WdfDeviceInitSetExclusive(deviceInit, TRUE);
    WdfDeviceInitSetIoType(deviceInit, WdfDeviceIoBuffered);
    status = WdfDeviceInitAssignName(deviceInit, &FcxDeviceName);
    if (!NT_SUCCESS(status)) {
        goto Failure;
    }
    WDF_OBJECT_ATTRIBUTES_INIT(&attributes);
    status = WdfDeviceCreate(&deviceInit, &attributes, &FcxControlDevice);
    if (!NT_SUCCESS(status)) {
        goto Failure;
    }
    status = WdfDeviceCreateSymbolicLink(FcxControlDevice, &FcxDosDeviceName);
    if (!NT_SUCCESS(status)) {
        goto Failure;
    }

    WDF_IO_QUEUE_CONFIG_INIT_DEFAULT_QUEUE(&queueConfig,
                                            WdfIoQueueDispatchSequential);
    queueConfig.PowerManaged = WdfFalse;
    queueConfig.EvtIoDeviceControl = FcxEvtIoDeviceControl;
    WDF_OBJECT_ATTRIBUTES_INIT(&attributes);
    WDF_OBJECT_ATTRIBUTES_SET_EXECUTION_LEVEL(&attributes,
                                               WdfExecutionLevelPassive);
    status = WdfIoQueueCreate(FcxControlDevice,
                              &queueConfig,
                              &attributes,
                              WDF_NO_HANDLE);
    if (!NT_SUCCESS(status)) {
        goto Failure;
    }
    status = FcxCreateRedirectHandle();
    if (!NT_SUCCESS(status)) {
        goto Failure;
    }
    status = FcxRegisterCallouts(WdfDeviceWdmGetDeviceObject(FcxControlDevice));
    if (!NT_SUCCESS(status)) {
        goto Failure;
    }
    WdfControlFinishInitializing(FcxControlDevice);
    return STATUS_SUCCESS;

Failure:
    if (deviceInit != NULL) {
        WdfDeviceInitFree(deviceInit);
    }
    FcxUnregisterCallouts();
    FcxDestroyRedirectHandle();
    if (FcxProcessNotifyRegistered) {
        (VOID)PsSetCreateProcessNotifyRoutineEx(FcxProcessNotify, TRUE);
        FcxProcessNotifyRegistered = FALSE;
    }
    FcxReleaseLease();
    FcxControlDevice = NULL;
    if (FcxLeaseRundown != NULL) {
        ExFreeCacheAwareRundownProtection(FcxLeaseRundown);
        FcxLeaseRundown = NULL;
    }
    if (FcxPolicyRundown != NULL) {
        ExFreeCacheAwareRundownProtection(FcxPolicyRundown);
        FcxPolicyRundown = NULL;
    }
    return status;
}

#ifdef ALLOC_PRAGMA
#pragma alloc_text(INIT, DriverEntry)
#pragma alloc_text(PAGE, FcxEvtDriverUnload)
#pragma alloc_text(PAGE, FcxEvtIoDeviceControl)
#pragma alloc_text(PAGE, FcxCreateRedirectHandle)
#pragma alloc_text(PAGE, FcxDestroyRedirectHandle)
#pragma alloc_text(PAGE, FcxRegisterCallouts)
#endif
