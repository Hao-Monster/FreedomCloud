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
static const GUID FcxFlowV4CalloutKey = {
    0x00d83eb9, 0x8749, 0x4b5d, {0xae, 0x3b, 0x55, 0x1a, 0x96, 0x2b, 0xa5, 0xf4}
};
static const GUID FcxFlowV6CalloutKey = {
    0xd88a2c87, 0x510a, 0x4f61, {0xa9, 0xb1, 0x12, 0x9f, 0x2e, 0x5f, 0xb3, 0xf0}
};
static const GUID FcxDatagramV4CalloutKey = {
    0xf17248e9, 0xfdd9, 0x4307, {0xb7, 0x6b, 0xcc, 0x8f, 0x21, 0x24, 0x62, 0xc5}
};
static const GUID FcxDatagramV6CalloutKey = {
    0xa86c2426, 0x7a29, 0x4ad4, {0xae, 0xb3, 0x8d, 0x17, 0xa8, 0x7e, 0x2c, 0x05}
};

#define FCX_STRICT_LEASE_POOL_TAG 'LCXF'
#define FCX_STRICT_REDIRECT_POOL_TAG 'RCXF'
#define FCX_STRICT_UDP_FLOW_POOL_TAG 'UCXF'
#define FCX_STRICT_MAX_UDP_FLOWS 1024

#define FCX_CALLOUT_GUARD_V4 0u
#define FCX_CALLOUT_GUARD_V6 1u
#define FCX_CALLOUT_REDIRECT_V4 2u
#define FCX_CALLOUT_REDIRECT_V6 3u
#define FCX_CALLOUT_FLOW_V4 4u
#define FCX_CALLOUT_FLOW_V6 5u
#define FCX_CALLOUT_DATAGRAM_V4 6u
#define FCX_CALLOUT_DATAGRAM_V6 7u

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

typedef struct _FCX_STRICT_UDP_FLOW_CONTEXT {
    LIST_ENTRY Link;
    volatile LONG ReferenceCount;
    UINT64 FlowId;
    UINT64 FlowToken;
    UINT64 LeaseGeneration;
    UINT64 Revision;
    UINT8 PolicyDigest[32];
    UINT8 LeaseNonce[16];
    UINT16 TargetGroupIndex;
    UINT16 LayerId;
    UINT32 CalloutId;
    UINT8 AddressFamily;
    BOOLEAN Listed;
    BOOLEAN Associated;
    BOOLEAN RemovalRequested;
} FCX_STRICT_UDP_FLOW_CONTEXT;

static WDFDEVICE FcxControlDevice;
static WDFQUEUE FcxDatagramReceiveQueue;
static PEX_RUNDOWN_REF_CACHE_AWARE FcxPolicyRundown;
static volatile PVOID FcxPolicySnapshot;
static volatile LONG64 FcxPolicyGeneration;
static PEX_RUNDOWN_REF_CACHE_AWARE FcxLeaseRundown;
static volatile PVOID FcxLeaseState;
static volatile LONG64 FcxLeaseGeneration;
static FAST_MUTEX FcxLeaseMutationLock;
static BOOLEAN FcxProcessNotifyRegistered;
static UINT32 FcxCalloutIds[8];
static UINT32 FcxRegisteredCallouts;
static HANDLE FcxRedirectHandle;
static volatile LONG FcxUdpFlowCount;
static volatile LONG64 FcxUdpFlowToken;
static volatile LONG FcxUdpStopping;
static KSPIN_LOCK FcxUdpFlowLock;
static LIST_ENTRY FcxUdpFlowList;
static KEVENT FcxUdpFlowEmptyEvent;

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
FcxFlowClassifyV4(
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
FcxFlowClassifyV6(
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
FcxDatagramClassifyV4(
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
FcxDatagramClassifyV6(
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
FcxDatagramFlowDelete(
    _In_ UINT16 LayerId,
    _In_ UINT32 CalloutId,
    _In_ UINT64 FlowContext
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
    ClassifyOut->actionType = FWP_ACTION_BLOCK;
    ClassifyOut->rights &= ~FWPS_RIGHT_ACTION_WRITE;
}

static
VOID
FcxPermitClassify(
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    ClassifyOut->actionType = FWP_ACTION_PERMIT;
    ClassifyOut->rights &= ~FWPS_RIGHT_ACTION_WRITE;
}

static
VOID
FcxContinueClassify(
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    if ((ClassifyOut->rights & FWPS_RIGHT_ACTION_WRITE) != 0) {
        ClassifyOut->actionType = FWP_ACTION_CONTINUE;
    }
}

static
const FCX_STRICT_RULE_RECORD *
FcxFindSelectedRule(
    _In_ const FCX_STRICT_POLICY_SNAPSHOT *Snapshot,
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ UINT32 AppIdField
    )
{
    const FWP_BYTE_BLOB *appId;
    const FWP_VALUE0 *value;

    if (Snapshot == NULL || AppIdField >= IncomingValues->valueCount) {
        return NULL;
    }
    value = &IncomingValues->incomingValue[AppIdField].value;
    appId = value->type == FWP_BYTE_BLOB_TYPE ? value->byteBlob : NULL;
    if (appId == NULL || appId->data == NULL || appId->size == 0 ||
        appId->size > FCX_STRICT_MAX_APP_ID_BYTES) {
        return NULL;
    }
    return FcxStrictPolicyFind(Snapshot, appId->data, appId->size);
}

static
BOOLEAN
FcxLeaseMatchesSnapshot(
    _In_ const FCX_STRICT_LEASE_STATE *Lease,
    _In_ const FCX_STRICT_POLICY_SNAPSHOT *Snapshot
    )
{
    return Lease != NULL && Snapshot != NULL &&
           Lease->ExpiresAtInterruptTime > KeQueryInterruptTime() &&
           Lease->Revision == Snapshot->Revision &&
           RtlCompareMemory(Lease->PolicyDigest,
                            Snapshot->PolicyDigest,
                            sizeof(Lease->PolicyDigest)) == sizeof(Lease->PolicyDigest);
}

static
FWPS_CONNECTION_REDIRECT_STATE
FcxQueryRedirectState(
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Outptr_result_maybenull_ VOID **RedirectContext
    )
{
    *RedirectContext = NULL;
    if (FcxRedirectHandle == NULL ||
        !FWPS_IS_METADATA_FIELD_PRESENT(
            IncomingMetadata,
            FWPS_METADATA_FIELD_REDIRECT_RECORD_HANDLE)) {
        return FWPS_CONNECTION_NOT_REDIRECTED;
    }
    return FwpsQueryConnectionRedirectState0(IncomingMetadata->redirectRecords,
                                              FcxRedirectHandle,
                                              RedirectContext);
}

static
BOOLEAN
FcxRedirectContextMatchesPolicy(
    _In_opt_ const VOID *RedirectContext,
    _In_ const FCX_STRICT_POLICY_SNAPSHOT *Snapshot,
    _In_ const FCX_STRICT_RULE_RECORD *Rule
    )
{
    const FCX_STRICT_REDIRECT_CONTEXT *context =
        (const FCX_STRICT_REDIRECT_CONTEXT *)RedirectContext;

    return context != NULL &&
           context->Magic == FCX_STRICT_REDIRECT_CONTEXT_MAGIC &&
           context->Protocol == FCX_STRICT_REDIRECT_CONTEXT_PROTOCOL &&
           context->ContextBytes == FCX_STRICT_REDIRECT_CONTEXT_BYTES &&
           context->Revision == Snapshot->Revision &&
           context->TargetGroupIndex == Rule->TargetGroupIndex &&
           context->IpProtocol == IPPROTO_TCP &&
           RtlCompareMemory(context->PolicyDigest,
                            Snapshot->PolicyDigest,
                            sizeof(context->PolicyDigest)) == sizeof(context->PolicyDigest);
}

static
BOOLEAN
FcxOriginalDestinationIsSafe(
    _In_ const FCX_STRICT_REDIRECT_CONTEXT *Context
    )
{
    const UINT8 *address = Context->RemoteAddress;
    UINT32 index;
    BOOLEAN allZero = TRUE;

    if (Context->RemotePort == 0) {
        return FALSE;
    }
    if (Context->AddressFamily == FCX_STRICT_ADDRESS_FAMILY_V4) {
        if (address[0] == 127 ||
            (address[0] >= 224 && address[0] <= 239) ||
            (address[0] == 255 && address[1] == 255 &&
             address[2] == 255 && address[3] == 255)) {
            return FALSE;
        }
        for (index = 0; index < 4; ++index) {
            allZero = allZero && address[index] == 0;
        }
        for (index = 4; index < sizeof(Context->RemoteAddress); ++index) {
            if (address[index] != 0) {
                return FALSE;
            }
        }
        return !allZero;
    }
    if (Context->AddressFamily != FCX_STRICT_ADDRESS_FAMILY_V6 ||
        address[0] == 0xff) {
        return FALSE;
    }
    for (index = 0; index < sizeof(Context->RemoteAddress); ++index) {
        allZero = allZero && address[index] == 0;
    }
    if (allZero) {
        return FALSE;
    }
    for (index = 0; index < sizeof(Context->RemoteAddress) - 1; ++index) {
        if (address[index] != 0) {
            return TRUE;
        }
    }
    return address[sizeof(Context->RemoteAddress) - 1] != 1;
}

static
BOOLEAN
FcxPopulateRedirectContext(
    _In_ const FWPS_CONNECT_REQUEST0 *ConnectRequest,
    _In_ BOOLEAN Ipv6,
    _In_ const FCX_STRICT_POLICY_SNAPSHOT *Snapshot,
    _In_ const FCX_STRICT_RULE_RECORD *Rule,
    _In_ const FCX_STRICT_LEASE_STATE *Lease,
    _Out_ FCX_STRICT_REDIRECT_CONTEXT *Context
    )
{
    RtlZeroMemory(Context, sizeof(*Context));
    Context->Magic = FCX_STRICT_REDIRECT_CONTEXT_MAGIC;
    Context->Protocol = FCX_STRICT_REDIRECT_CONTEXT_PROTOCOL;
    Context->ContextBytes = FCX_STRICT_REDIRECT_CONTEXT_BYTES;
    Context->LeaseGeneration = Lease->Generation;
    Context->Revision = Snapshot->Revision;
    RtlCopyMemory(Context->PolicyDigest,
                  Snapshot->PolicyDigest,
                  sizeof(Context->PolicyDigest));
    RtlCopyMemory(Context->LeaseNonce,
                  Lease->Nonce,
                  sizeof(Context->LeaseNonce));
    Context->TargetGroupIndex = Rule->TargetGroupIndex;
    Context->IpProtocol = IPPROTO_TCP;

    if (Ipv6) {
        const SOCKADDR_IN6 *remote =
            (const SOCKADDR_IN6 *)&ConnectRequest->remoteAddressAndPort;
        if (remote->sin6_family != AF_INET6) {
            return FALSE;
        }
        Context->AddressFamily = FCX_STRICT_ADDRESS_FAMILY_V6;
        Context->RemotePort = RtlUshortByteSwap(remote->sin6_port);
        RtlCopyMemory(Context->RemoteAddress,
                      &remote->sin6_addr,
                      sizeof(remote->sin6_addr));
    } else {
        const SOCKADDR_IN *remote =
            (const SOCKADDR_IN *)&ConnectRequest->remoteAddressAndPort;
        if (remote->sin_family != AF_INET) {
            return FALSE;
        }
        Context->AddressFamily = FCX_STRICT_ADDRESS_FAMILY_V4;
        Context->RemotePort = RtlUshortByteSwap(remote->sin_port);
        RtlCopyMemory(Context->RemoteAddress,
                      &remote->sin_addr,
                      sizeof(remote->sin_addr));
    }
    return FcxOriginalDestinationIsSafe(Context);
}

static
VOID
FcxSetRedirectTarget(
    _Inout_ FWPS_CONNECT_REQUEST0 *ConnectRequest,
    _In_ BOOLEAN Ipv6,
    _In_ const FCX_STRICT_ENDPOINT *Endpoint
    )
{
    RtlZeroMemory(&ConnectRequest->remoteAddressAndPort,
                  sizeof(ConnectRequest->remoteAddressAndPort));
    if (Ipv6) {
        SOCKADDR_IN6 *remote =
            (SOCKADDR_IN6 *)&ConnectRequest->remoteAddressAndPort;
        remote->sin6_family = AF_INET6;
        remote->sin6_port = RtlUshortByteSwap(Endpoint->Port);
        RtlCopyMemory(&remote->sin6_addr,
                      Endpoint->Address,
                      sizeof(remote->sin6_addr));
    } else {
        SOCKADDR_IN *remote =
            (SOCKADDR_IN *)&ConnectRequest->remoteAddressAndPort;
        remote->sin_family = AF_INET;
        remote->sin_port = RtlUshortByteSwap(Endpoint->Port);
        RtlCopyMemory(&remote->sin_addr,
                      Endpoint->Address,
                      sizeof(remote->sin_addr));
    }
}

static
VOID
FcxClassifyRedirectedTcpGuard(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _In_ UINT32 AppIdField,
    _In_ UINT32 ProtocolField,
    _In_ UINT32 FlagsField,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    const FCX_STRICT_POLICY_SNAPSHOT *snapshot;
    const FCX_STRICT_LEASE_STATE *lease;
    const FCX_STRICT_RULE_RECORD *rule;
    BOOLEAN permit = FALSE;

    if ((ClassifyOut->rights & FWPS_RIGHT_ACTION_WRITE) == 0 ||
        FcxPolicyRundown == NULL || FcxLeaseRundown == NULL ||
        !ExAcquireRundownProtectionCacheAware(FcxPolicyRundown)) {
        FcxBlockClassify(ClassifyOut);
        return;
    }
    snapshot = (const FCX_STRICT_POLICY_SNAPSHOT *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxPolicySnapshot,
        NULL,
        NULL);
    rule = FcxFindSelectedRule(snapshot, IncomingValues, AppIdField);
    if (rule != NULL && rule->Action == FCX_STRICT_ACTION_PROXY &&
        ProtocolField < IncomingValues->valueCount &&
        FlagsField < IncomingValues->valueCount &&
        IncomingValues->incomingValue[ProtocolField].value.type == FWP_UINT8 &&
        IncomingValues->incomingValue[ProtocolField].value.uint8 == IPPROTO_TCP &&
        IncomingValues->incomingValue[FlagsField].value.type == FWP_UINT32 &&
        (IncomingValues->incomingValue[FlagsField].value.uint32 &
         FWP_CONDITION_FLAG_IS_CONNECTION_REDIRECTED) != 0 &&
        FWPS_IS_METADATA_FIELD_PRESENT(
            IncomingMetadata,
            FWPS_METADATA_FIELD_LOCAL_REDIRECT_TARGET_PID) &&
        FWPS_IS_METADATA_FIELD_PRESENT(
            IncomingMetadata,
            FWPS_METADATA_FIELD_ORIGINAL_DESTINATION) &&
        IncomingMetadata->originalDestination != NULL &&
        ExAcquireRundownProtectionCacheAware(FcxLeaseRundown)) {
        lease = (const FCX_STRICT_LEASE_STATE *)InterlockedCompareExchangePointer(
            (PVOID volatile *)&FcxLeaseState,
            NULL,
            NULL);
        if (FcxLeaseMatchesSnapshot(lease, snapshot) &&
            IncomingMetadata->localRedirectTargetPID ==
                HandleToULong(PsGetProcessId(lease->BrokerProcess))) {
            permit = TRUE;
        }
        ExReleaseRundownProtectionCacheAware(FcxLeaseRundown);
    }
    ExReleaseRundownProtectionCacheAware(FcxPolicyRundown);
    if (permit) {
        FcxPermitClassify(ClassifyOut);
    } else {
        FcxBlockClassify(ClassifyOut);
    }
}

static
VOID
FcxClassifyTcpRedirect(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _In_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT32 AppIdField,
    _In_ UINT32 ProtocolField,
    _In_ BOOLEAN Ipv6,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    const FCX_STRICT_POLICY_SNAPSHOT *snapshot;
    const FCX_STRICT_LEASE_STATE *lease;
    const FCX_STRICT_RULE_RECORD *rule;
    const FCX_STRICT_ENDPOINT *endpoint;
    FCX_STRICT_REDIRECT_CONTEXT *redirectContext = NULL;
    FWPS_CONNECT_REQUEST0 *connectRequest;
    PVOID writableRequest = NULL;
    VOID *priorRedirectContext;
    FWPS_CONNECTION_REDIRECT_STATE redirectState;
    UINT64 classifyHandle = 0;
    NTSTATUS status;
    BOOLEAN permit = FALSE;

    if ((ClassifyOut->rights & FWPS_RIGHT_ACTION_WRITE) == 0 ||
        ClassifyContext == NULL || Filter == NULL ||
        FcxPolicyRundown == NULL || FcxLeaseRundown == NULL ||
        !ExAcquireRundownProtectionCacheAware(FcxPolicyRundown)) {
        FcxBlockClassify(ClassifyOut);
        return;
    }
    snapshot = (const FCX_STRICT_POLICY_SNAPSHOT *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxPolicySnapshot,
        NULL,
        NULL);
    rule = FcxFindSelectedRule(snapshot, IncomingValues, AppIdField);
    if (rule == NULL || rule->Action != FCX_STRICT_ACTION_PROXY ||
        ProtocolField >= IncomingValues->valueCount ||
        IncomingValues->incomingValue[ProtocolField].value.type != FWP_UINT8 ||
        IncomingValues->incomingValue[ProtocolField].value.uint8 != IPPROTO_TCP ||
        !ExAcquireRundownProtectionCacheAware(FcxLeaseRundown)) {
        ExReleaseRundownProtectionCacheAware(FcxPolicyRundown);
        FcxBlockClassify(ClassifyOut);
        return;
    }
    lease = (const FCX_STRICT_LEASE_STATE *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxLeaseState,
        NULL,
        NULL);
    if (!FcxLeaseMatchesSnapshot(lease, snapshot)) {
        goto Exit;
    }

    redirectState = FcxQueryRedirectState(IncomingMetadata,
                                           &priorRedirectContext);
    if (redirectState == FWPS_CONNECTION_REDIRECTED_BY_SELF) {
        // Lease renewal changes generation and nonce. Reauthorization therefore
        // binds an existing self-redirect to the stable policy, while the guard
        // still requires the currently leased Broker PID.
        permit = FcxRedirectContextMatchesPolicy(priorRedirectContext,
                                                  snapshot,
                                                  rule);
        goto Exit;
    }
    if (redirectState == FWPS_CONNECTION_PREVIOUSLY_REDIRECTED_BY_SELF) {
        permit = TRUE;
        goto Exit;
    }
    if (redirectState != FWPS_CONNECTION_NOT_REDIRECTED) {
        goto Exit;
    }

    status = FwpsAcquireClassifyHandle0((VOID *)ClassifyContext,
                                         0,
                                         &classifyHandle);
    if (!NT_SUCCESS(status)) {
        goto Exit;
    }
    status = FwpsAcquireWritableLayerDataPointer0(classifyHandle,
                                                   Filter->filterId,
                                                   0,
                                                   &writableRequest,
                                                   ClassifyOut);
    if (!NT_SUCCESS(status)) {
        goto Exit;
    }
    connectRequest = (FWPS_CONNECT_REQUEST0 *)writableRequest;
    if (connectRequest->localRedirectHandle != NULL ||
        connectRequest->localRedirectContext != NULL) {
        goto Apply;
    }
    redirectContext = (FCX_STRICT_REDIRECT_CONTEXT *)ExAllocatePool2(POOL_FLAG_NON_PAGED,
                                                                      sizeof(*redirectContext),
                                                                      FCX_STRICT_REDIRECT_POOL_TAG);
    if (redirectContext == NULL ||
        !FcxPopulateRedirectContext(connectRequest,
                                    Ipv6,
                                    snapshot,
                                    rule,
                                    lease,
                                    redirectContext)) {
        goto Apply;
    }

    endpoint = Ipv6 ? &lease->TcpV6 : &lease->TcpV4;
    FcxSetRedirectTarget(connectRequest, Ipv6, endpoint);
    connectRequest->localRedirectTargetPID =
        HandleToULong(PsGetProcessId(lease->BrokerProcess));
    connectRequest->localRedirectHandle = FcxRedirectHandle;
    connectRequest->localRedirectContext = redirectContext;
    connectRequest->localRedirectContextSize = sizeof(*redirectContext);
    ClassifyOut->actionType = FWP_ACTION_PERMIT;
    ClassifyOut->rights |= FWPS_RIGHT_ACTION_WRITE;
    permit = TRUE;

Apply:
    FwpsApplyModifiedLayerData0(classifyHandle, writableRequest, 0);
    if (permit) {
        redirectContext = NULL;
    }

Exit:
    if (classifyHandle != 0) {
        FwpsReleaseClassifyHandle0(classifyHandle);
    }
    if (redirectContext != NULL) {
        RtlSecureZeroMemory(redirectContext, sizeof(*redirectContext));
        ExFreePoolWithTag(redirectContext, FCX_STRICT_REDIRECT_POOL_TAG);
    }
    ExReleaseRundownProtectionCacheAware(FcxLeaseRundown);
    ExReleaseRundownProtectionCacheAware(FcxPolicyRundown);
    if (permit) {
        FcxPermitClassify(ClassifyOut);
    } else {
        FcxBlockClassify(ClassifyOut);
    }
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
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(ClassifyContext);
    UNREFERENCED_PARAMETER(Filter);
    UNREFERENCED_PARAMETER(FlowContext);
    FcxClassifyRedirectedTcpGuard(
        IncomingValues,
        IncomingMetadata,
        FWPS_FIELD_ALE_AUTH_CONNECT_V4_ALE_APP_ID,
        FWPS_FIELD_ALE_AUTH_CONNECT_V4_IP_PROTOCOL,
        FWPS_FIELD_ALE_AUTH_CONNECT_V4_FLAGS,
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
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(ClassifyContext);
    UNREFERENCED_PARAMETER(Filter);
    UNREFERENCED_PARAMETER(FlowContext);
    FcxClassifyRedirectedTcpGuard(
        IncomingValues,
        IncomingMetadata,
        FWPS_FIELD_ALE_AUTH_CONNECT_V6_ALE_APP_ID,
        FWPS_FIELD_ALE_AUTH_CONNECT_V6_IP_PROTOCOL,
        FWPS_FIELD_ALE_AUTH_CONNECT_V6_FLAGS,
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
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(FlowContext);
    FcxClassifyTcpRedirect(
        IncomingValues,
        IncomingMetadata,
        ClassifyContext,
        Filter,
        FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_ALE_APP_ID,
        FWPS_FIELD_ALE_CONNECT_REDIRECT_V4_IP_PROTOCOL,
        FALSE,
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
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(FlowContext);
    FcxClassifyTcpRedirect(
        IncomingValues,
        IncomingMetadata,
        ClassifyContext,
        Filter,
        FWPS_FIELD_ALE_CONNECT_REDIRECT_V6_ALE_APP_ID,
        FWPS_FIELD_ALE_CONNECT_REDIRECT_V6_IP_PROTOCOL,
        TRUE,
        ClassifyOut);
}

static
BOOLEAN
FcxReserveUdpFlowSlot(
    VOID
    )
{
    LONG flowCount;

    if (InterlockedCompareExchange(&FcxUdpStopping, 0, 0) != 0) {
        return FALSE;
    }
    flowCount = InterlockedIncrement(&FcxUdpFlowCount);
    if (flowCount == 1) {
        KeClearEvent(&FcxUdpFlowEmptyEvent);
    }
    if (flowCount <= 0 || flowCount > FCX_STRICT_MAX_UDP_FLOWS) {
        flowCount = InterlockedDecrement(&FcxUdpFlowCount);
        if (flowCount == 0) {
            KeSetEvent(&FcxUdpFlowEmptyEvent, IO_NO_INCREMENT, FALSE);
        }
        return FALSE;
    }
    return TRUE;
}

static
VOID
FcxReleaseUdpFlowSlot(
    VOID
    )
{
    LONG flowCount = InterlockedDecrement(&FcxUdpFlowCount);

    if (flowCount == 0) {
        KeSetEvent(&FcxUdpFlowEmptyEvent, IO_NO_INCREMENT, FALSE);
    }
}

static
BOOLEAN
FcxLinkUdpFlowContext(
    _Inout_ FCX_STRICT_UDP_FLOW_CONTEXT *Context
    )
{
    KIRQL oldIrql;
    BOOLEAN linked = FALSE;

    KeAcquireSpinLock(&FcxUdpFlowLock, &oldIrql);
    if (InterlockedCompareExchange(&FcxUdpStopping, 0, 0) == 0) {
        InsertTailList(&FcxUdpFlowList, &Context->Link);
        Context->Listed = TRUE;
        linked = TRUE;
    }
    KeReleaseSpinLock(&FcxUdpFlowLock, oldIrql);
    return linked;
}

static
VOID
FcxUnlinkUdpFlowContext(
    _Inout_ FCX_STRICT_UDP_FLOW_CONTEXT *Context
    )
{
    KIRQL oldIrql;

    KeAcquireSpinLock(&FcxUdpFlowLock, &oldIrql);
    if (Context->Listed) {
        RemoveEntryList(&Context->Link);
        Context->Listed = FALSE;
    }
    KeReleaseSpinLock(&FcxUdpFlowLock, oldIrql);
}

static
VOID
FcxReferenceUdpFlowContext(
    _Inout_ FCX_STRICT_UDP_FLOW_CONTEXT *Context
    )
{
    LONG referenceCount = InterlockedIncrement(&Context->ReferenceCount);

    NT_ASSERT(referenceCount > 1);
}

static
VOID
FcxDereferenceUdpFlowContext(
    _Inout_opt_ FCX_STRICT_UDP_FLOW_CONTEXT *Context
    )
{
    LONG referenceCount;

    if (Context == NULL) {
        return;
    }
    referenceCount = InterlockedDecrement(&Context->ReferenceCount);
    NT_ASSERT(referenceCount >= 0);
    if (referenceCount == 0) {
        NT_ASSERT(!Context->Listed);
        RtlSecureZeroMemory(Context, sizeof(*Context));
        ExFreePoolWithTag(Context, FCX_STRICT_UDP_FLOW_POOL_TAG);
        FcxReleaseUdpFlowSlot();
    }
}

static
VOID
FcxDrainUdpFlowContexts(
    _In_ BOOLEAN ResumeAssociations
    )
{
    FCX_STRICT_UDP_FLOW_CONTEXT *context;
    PLIST_ENTRY entry;
    UINT64 flowId;
    UINT16 layerId;
    UINT32 calloutId;
    KIRQL oldIrql;
    BOOLEAN found;

    InterlockedExchange(&FcxUdpStopping, 1);
    for (;;) {
        found = FALSE;
        flowId = 0;
        layerId = 0;
        calloutId = 0;
        KeAcquireSpinLock(&FcxUdpFlowLock, &oldIrql);
        for (entry = FcxUdpFlowList.Flink;
             entry != &FcxUdpFlowList;
             entry = entry->Flink) {
            context = CONTAINING_RECORD(entry,
                                        FCX_STRICT_UDP_FLOW_CONTEXT,
                                        Link);
            if (context->Associated && !context->RemovalRequested) {
                context->RemovalRequested = TRUE;
                flowId = context->FlowId;
                layerId = context->LayerId;
                calloutId = context->CalloutId;
                found = TRUE;
                break;
            }
        }
        KeReleaseSpinLock(&FcxUdpFlowLock, oldIrql);
        if (!found) {
            break;
        }
        // Success invokes flowDelete synchronously; STATUS_PENDING invokes it
        // after the active classify completes. Other statuses still race with
        // a terminating flow, so the empty event remains the ownership fence.
        (VOID)FwpsFlowRemoveContext0(flowId, layerId, calloutId);
    }
    if (InterlockedCompareExchange(&FcxUdpFlowCount, 0, 0) != 0) {
        (VOID)KeWaitForSingleObject(&FcxUdpFlowEmptyEvent,
                                    Executive,
                                    KernelMode,
                                    FALSE,
                                    NULL);
    }
    if (ResumeAssociations) {
        InterlockedExchange(&FcxUdpStopping, 0);
    }
}

static
VOID
FcxClassifyUdpFlow(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _In_ UINT32 AppIdField,
    _In_ UINT32 ProtocolField,
    _In_ UINT16 DatagramLayerId,
    _In_ UINT32 DatagramCalloutId,
    _In_ BOOLEAN Ipv6,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    const FCX_STRICT_POLICY_SNAPSHOT *snapshot;
    const FCX_STRICT_LEASE_STATE *lease;
    const FCX_STRICT_RULE_RECORD *rule;
    FCX_STRICT_UDP_FLOW_CONTEXT *context = NULL;
    LONG64 flowToken;
    NTSTATUS status;
    KIRQL oldIrql;
    BOOLEAN leaseAcquired = FALSE;
    BOOLEAN associated = FALSE;
    BOOLEAN removeAfterAssociate = FALSE;

    if (DatagramCalloutId == 0 ||
        InterlockedCompareExchange(&FcxUdpStopping, 0, 0) != 0 ||
        !FWPS_IS_METADATA_FIELD_PRESENT(IncomingMetadata,
                                        FWPS_METADATA_FIELD_FLOW_HANDLE) ||
        FcxPolicyRundown == NULL || FcxLeaseRundown == NULL ||
        !ExAcquireRundownProtectionCacheAware(FcxPolicyRundown)) {
        if (FWPS_IS_METADATA_FIELD_PRESENT(IncomingMetadata,
                                           FWPS_METADATA_FIELD_FLOW_HANDLE)) {
            (VOID)FwpsFlowAbort0(IncomingMetadata->flowHandle);
        }
        FcxContinueClassify(ClassifyOut);
        return;
    }
    snapshot = (const FCX_STRICT_POLICY_SNAPSHOT *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxPolicySnapshot,
        NULL,
        NULL);
    rule = FcxFindSelectedRule(snapshot, IncomingValues, AppIdField);
    if (rule == NULL || rule->Action != FCX_STRICT_ACTION_PROXY ||
        rule->TargetGroupIndex == FCX_STRICT_NO_TARGET_GROUP ||
        rule->TargetGroupIndex >= snapshot->TargetGroupCount ||
        ProtocolField >= IncomingValues->valueCount ||
        IncomingValues->incomingValue[ProtocolField].value.type != FWP_UINT8 ||
        IncomingValues->incomingValue[ProtocolField].value.uint8 != IPPROTO_UDP ||
        !ExAcquireRundownProtectionCacheAware(FcxLeaseRundown)) {
        goto Exit;
    }
    leaseAcquired = TRUE;
    lease = (const FCX_STRICT_LEASE_STATE *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxLeaseState,
        NULL,
        NULL);
    if (!FcxLeaseMatchesSnapshot(lease, snapshot)) {
        goto Exit;
    }

    if (!FcxReserveUdpFlowSlot()) {
        goto Exit;
    }
    context = (FCX_STRICT_UDP_FLOW_CONTEXT *)ExAllocatePool2(
        POOL_FLAG_NON_PAGED,
        sizeof(*context),
        FCX_STRICT_UDP_FLOW_POOL_TAG);
    if (context == NULL) {
        FcxReleaseUdpFlowSlot();
        goto Exit;
    }
    RtlZeroMemory(context, sizeof(*context));
    context->ReferenceCount = 1;
    flowToken = InterlockedIncrement64(&FcxUdpFlowToken);
    if (flowToken == 0) {
        goto Exit;
    }
    context->FlowToken = (UINT64)flowToken;
    context->LeaseGeneration = lease->Generation;
    context->Revision = snapshot->Revision;
    RtlCopyMemory(context->PolicyDigest,
                  snapshot->PolicyDigest,
                  sizeof(context->PolicyDigest));
    RtlCopyMemory(context->LeaseNonce,
                  lease->Nonce,
                  sizeof(context->LeaseNonce));
    context->TargetGroupIndex = rule->TargetGroupIndex;
    context->FlowId = IncomingMetadata->flowHandle;
    context->LayerId = DatagramLayerId;
    context->CalloutId = DatagramCalloutId;
    context->AddressFamily = Ipv6 ? FCX_STRICT_ADDRESS_FAMILY_V6 :
                                    FCX_STRICT_ADDRESS_FAMILY_V4;
    if (!FcxLinkUdpFlowContext(context)) {
        goto Exit;
    }
    // Keep one reference for WFP before association. If WFP terminates the
    // flow concurrently with this call, flowDelete can release its reference
    // without invalidating the creator's post-association bookkeeping.
    FcxReferenceUdpFlowContext(context);
    status = FwpsFlowAssociateContext0(
        IncomingMetadata->flowHandle,
        DatagramLayerId,
        DatagramCalloutId,
        (UINT64)(ULONG_PTR)context);
    if (!NT_SUCCESS(status)) {
        FcxDereferenceUdpFlowContext(context);
        goto Exit;
    }
    associated = TRUE;
    KeAcquireSpinLock(&FcxUdpFlowLock, &oldIrql);
    if (context->Listed) {
        context->Associated = TRUE;
        if (InterlockedCompareExchange(&FcxUdpStopping, 0, 0) != 0) {
            context->RemovalRequested = TRUE;
            removeAfterAssociate = TRUE;
        }
    }
    KeReleaseSpinLock(&FcxUdpFlowLock, oldIrql);
    if (removeAfterAssociate) {
        (VOID)FwpsFlowRemoveContext0(IncomingMetadata->flowHandle,
                                     DatagramLayerId,
                                     DatagramCalloutId);
    }

Exit:
    if (context != NULL) {
        if (!associated) {
            FcxUnlinkUdpFlowContext(context);
        }
        FcxDereferenceUdpFlowContext(context);
    }
    if (leaseAcquired) {
        ExReleaseRundownProtectionCacheAware(FcxLeaseRundown);
    }
    ExReleaseRundownProtectionCacheAware(FcxPolicyRundown);
    if (!associated &&
        FWPS_IS_METADATA_FIELD_PRESENT(IncomingMetadata,
                                       FWPS_METADATA_FIELD_FLOW_HANDLE)) {
        (VOID)FwpsFlowAbort0(IncomingMetadata->flowHandle);
    }
    FcxContinueClassify(ClassifyOut);
}

static
VOID NTAPI
FcxFlowClassifyV4(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_opt_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(ClassifyContext);
    UNREFERENCED_PARAMETER(Filter);
    UNREFERENCED_PARAMETER(FlowContext);
    FcxClassifyUdpFlow(
        IncomingValues,
        IncomingMetadata,
        FWPS_FIELD_ALE_FLOW_ESTABLISHED_V4_ALE_APP_ID,
        FWPS_FIELD_ALE_FLOW_ESTABLISHED_V4_IP_PROTOCOL,
        FWPS_LAYER_DATAGRAM_DATA_V4,
        FcxCalloutIds[FCX_CALLOUT_DATAGRAM_V4],
        FALSE,
        ClassifyOut);
}

static
VOID NTAPI
FcxFlowClassifyV6(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_opt_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(ClassifyContext);
    UNREFERENCED_PARAMETER(Filter);
    UNREFERENCED_PARAMETER(FlowContext);
    FcxClassifyUdpFlow(
        IncomingValues,
        IncomingMetadata,
        FWPS_FIELD_ALE_FLOW_ESTABLISHED_V6_ALE_APP_ID,
        FWPS_FIELD_ALE_FLOW_ESTABLISHED_V6_IP_PROTOCOL,
        FWPS_LAYER_DATAGRAM_DATA_V6,
        FcxCalloutIds[FCX_CALLOUT_DATAGRAM_V6],
        TRUE,
        ClassifyOut);
}

static
VOID
FcxClassifyDatagramUnavailable(
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    NT_ASSERT(FlowContext != 0);
    UNREFERENCED_PARAMETER(FlowContext);
    if ((ClassifyOut->rights & FWPS_RIGHT_ACTION_WRITE) == 0) {
        return;
    }
    // A context proves selection, but capture and reinjection are not complete.
    // Keep selected traffic blocked instead of leaking it to the original path.
    FcxBlockClassify(ClassifyOut);
}

static
VOID NTAPI
FcxDatagramClassifyV4(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_opt_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    UNREFERENCED_PARAMETER(IncomingValues);
    UNREFERENCED_PARAMETER(IncomingMetadata);
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(ClassifyContext);
    UNREFERENCED_PARAMETER(Filter);
    FcxClassifyDatagramUnavailable(FlowContext, ClassifyOut);
}

static
VOID NTAPI
FcxDatagramClassifyV6(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_opt_ const VOID *ClassifyContext,
    _In_ const FWPS_FILTER1 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    UNREFERENCED_PARAMETER(IncomingValues);
    UNREFERENCED_PARAMETER(IncomingMetadata);
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(ClassifyContext);
    UNREFERENCED_PARAMETER(Filter);
    FcxClassifyDatagramUnavailable(FlowContext, ClassifyOut);
}

static
VOID NTAPI
FcxDatagramFlowDelete(
    _In_ UINT16 LayerId,
    _In_ UINT32 CalloutId,
    _In_ UINT64 FlowContext
    )
{
    FCX_STRICT_UDP_FLOW_CONTEXT *context =
        (FCX_STRICT_UDP_FLOW_CONTEXT *)(ULONG_PTR)FlowContext;

    UNREFERENCED_PARAMETER(LayerId);
    UNREFERENCED_PARAMETER(CalloutId);
    FcxUnlinkUdpFlowContext(context);
    FcxDereferenceUdpFlowContext(context);
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
    FcxDrainUdpFlowContexts(FALSE);
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
    FcxDrainUdpFlowContexts(FALSE);
    oldLease = (FCX_STRICT_LEASE_STATE *)InterlockedExchangePointer(
        (PVOID volatile *)&FcxLeaseState,
        NewLease);
    ExWaitForRundownProtectionReleaseCacheAware(FcxLeaseRundown);
    FcxDestroyLease(oldLease);
    ExRundownCompletedCacheAware(FcxLeaseRundown);
    ExReInitializeRundownProtectionCacheAware(FcxLeaseRundown);
    InterlockedExchange(&FcxUdpStopping, 0);
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
BOOLEAN
FcxDatagramAddressIsSafe(
    _In_reads_bytes_(16) const UINT8 *Address,
    _In_ UINT8 AddressFamily,
    _In_ BOOLEAN Remote
    )
{
    BOOLEAN ipv4Mapped;

    if (AddressFamily == FCX_STRICT_ADDRESS_FAMILY_V4) {
        if (!FcxBytesAreZero(Address + 4, 12) ||
            (Address[0] == 0 && Address[1] == 0 &&
             Address[2] == 0 && Address[3] == 0) ||
            (Address[0] >= 224 && Address[0] <= 239) ||
            (Address[0] == 255 && Address[1] == 255 &&
             Address[2] == 255 && Address[3] == 255)) {
            return FALSE;
        }
        if (Remote &&
            (Address[0] == 127 ||
             (Address[0] == 169 && Address[1] == 254))) {
            return FALSE;
        }
        return TRUE;
    }
    if (AddressFamily != FCX_STRICT_ADDRESS_FAMILY_V6 ||
        FcxBytesAreZero(Address, 16) ||
        Address[0] == 0xff) {
        return FALSE;
    }
    ipv4Mapped = FcxBytesAreZero(Address, 10) &&
                 Address[10] == 0xff && Address[11] == 0xff;
    if (ipv4Mapped) {
        return FALSE;
    }
    if (Remote &&
        ((FcxBytesAreZero(Address, 15) && Address[15] == 1) ||
         (Address[0] == 0xfe && (Address[1] & 0xc0) == 0x80))) {
        return FALSE;
    }
    return TRUE;
}

static
BOOLEAN
FcxLeaseOwnsRequest(
    _In_ WDFREQUEST Request,
    _In_opt_ const FCX_STRICT_DATAGRAM_BATCH_HEADER *Batch
    )
{
    const FCX_STRICT_LEASE_STATE *lease;
    ULONG requestorProcessId;
    UINT64 leaseGeneration = 0;
    UINT64 revision = 0;
    BOOLEAN matches = FALSE;

    requestorProcessId = WdfRequestGetRequestorProcessId(Request);
    if (requestorProcessId == 0 || FcxLeaseRundown == NULL ||
        !ExAcquireRundownProtectionCacheAware(FcxLeaseRundown)) {
        return FALSE;
    }
    if (Batch != NULL) {
        RtlCopyMemory(&leaseGeneration,
                      &Batch->LeaseGeneration,
                      sizeof(leaseGeneration));
        RtlCopyMemory(&revision, &Batch->Revision, sizeof(revision));
    }
    lease = (const FCX_STRICT_LEASE_STATE *)InterlockedCompareExchangePointer(
        (PVOID volatile *)&FcxLeaseState,
        NULL,
        NULL);
    if (lease != NULL &&
        lease->ExpiresAtInterruptTime > KeQueryInterruptTime() &&
        PsGetProcessExitStatus(lease->BrokerProcess) == STATUS_PENDING &&
        HandleToULong(PsGetProcessId(lease->BrokerProcess)) ==
            requestorProcessId &&
        (Batch == NULL ||
         (lease->Generation == leaseGeneration &&
          lease->Revision == revision &&
          RtlCompareMemory(lease->PolicyDigest,
                           Batch->PolicyDigest,
                           sizeof(lease->PolicyDigest)) == sizeof(lease->PolicyDigest) &&
          RtlCompareMemory(lease->Nonce,
                           Batch->LeaseNonce,
                           sizeof(lease->Nonce)) == sizeof(lease->Nonce)))) {
        matches = TRUE;
    }
    ExReleaseRundownProtectionCacheAware(FcxLeaseRundown);
    return matches;
}

static
NTSTATUS
FcxQueueDatagramReceive(
    _In_ WDFREQUEST Request,
    _In_ size_t OutputBufferLength,
    _In_ size_t InputBufferLength
    )
{
    NTSTATUS status;
    PVOID output;
    size_t outputBytes;
    ULONG queuedRequests = 0;
    ULONG driverRequests = 0;

    if (FcxDatagramReceiveQueue == NULL) {
        return STATUS_DEVICE_NOT_READY;
    }
    if (InputBufferLength != 0 ||
        OutputBufferLength != FCX_STRICT_DATAGRAM_MAX_BATCH_BYTES) {
        return STATUS_INVALID_BUFFER_SIZE;
    }
    if (!FcxLeaseOwnsRequest(Request, NULL)) {
        return STATUS_ACCESS_DENIED;
    }
    status = WdfRequestRetrieveOutputBuffer(
        Request,
        FCX_STRICT_DATAGRAM_MAX_BATCH_BYTES,
        &output,
        &outputBytes);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    if (output == NULL || outputBytes != OutputBufferLength) {
        return STATUS_INVALID_BUFFER_SIZE;
    }
    (VOID)WdfIoQueueGetState(FcxDatagramReceiveQueue,
                             &queuedRequests,
                             &driverRequests);
    if (queuedRequests != 0 || driverRequests != 0) {
        return STATUS_DEVICE_BUSY;
    }
    return WdfRequestForwardToIoQueue(Request, FcxDatagramReceiveQueue);
}

static
NTSTATUS
FcxValidateSubmittedDatagramRecord(
    _In_reads_bytes_(AvailableBytes) const UINT8 *Input,
    _In_ UINT32 AvailableBytes,
    _Out_ UINT32 *RecordBytes
    )
{
    FCX_STRICT_DATAGRAM_RECORD_HEADER record;
    UINT32 expectedBytes;
    UINT32 unpaddedBytes;
    UINT64 flowToken;
    UINT64 sequence;

    *RecordBytes = 0;
    if (AvailableBytes < sizeof(record)) {
        return STATUS_INVALID_BUFFER_SIZE;
    }
    RtlCopyMemory(&record, Input, sizeof(record));
    RtlCopyMemory(&flowToken, &record.FlowToken, sizeof(flowToken));
    RtlCopyMemory(&sequence, &record.Sequence, sizeof(sequence));
    if (record.PayloadBytes == 0 ||
        record.PayloadBytes > FCX_STRICT_DATAGRAM_MAX_PAYLOAD_BYTES ||
        record.PayloadBytes > MAXULONG - FCX_STRICT_DATAGRAM_RECORD_HEADER_BYTES - 7u) {
        return STATUS_INVALID_PARAMETER;
    }
    unpaddedBytes = FCX_STRICT_DATAGRAM_RECORD_HEADER_BYTES + record.PayloadBytes;
    expectedBytes = (unpaddedBytes + 7u) & ~7u;
    if (record.RecordBytes != expectedBytes ||
        record.RecordBytes > AvailableBytes ||
        flowToken == 0 || sequence == 0 ||
        record.TargetGroupIndex >= 128 ||
        record.IpProtocol != IPPROTO_UDP ||
        (record.Flags & ~FCX_STRICT_DATAGRAM_KNOWN_FLAGS) != 0 ||
        record.LocalPort == 0 || record.RemotePort == 0 ||
        !FcxDatagramAddressIsSafe(record.LocalAddress,
                                  record.AddressFamily,
                                  FALSE) ||
        !FcxDatagramAddressIsSafe(record.RemoteAddress,
                                  record.AddressFamily,
                                  TRUE) ||
        !FcxBytesAreZero(record.Reserved, sizeof(record.Reserved)) ||
        !FcxBytesAreZero(Input + unpaddedBytes,
                         record.RecordBytes - unpaddedBytes)) {
        return STATUS_INVALID_PARAMETER;
    }
    *RecordBytes = record.RecordBytes;
    return STATUS_SUCCESS;
}

static
NTSTATUS
FcxValidateSubmittedDatagramBatch(
    _In_ WDFREQUEST Request,
    _In_ size_t OutputBufferLength,
    _In_ size_t InputBufferLength
    )
{
    NTSTATUS status;
    PVOID output;
    const UINT8 *input;
    size_t inputBytes;
    FCX_STRICT_DATAGRAM_BATCH_HEADER batch;
    UINT32 recordIndex;
    UINT32 cursor;
    UINT32 recordBytes;

    if (InputBufferLength != 0 ||
        OutputBufferLength < FCX_STRICT_DATAGRAM_BATCH_HEADER_BYTES ||
        OutputBufferLength > FCX_STRICT_DATAGRAM_MAX_BATCH_BYTES) {
        return STATUS_INVALID_BUFFER_SIZE;
    }
    status = WdfRequestRetrieveOutputBuffer(
        Request,
        FCX_STRICT_DATAGRAM_BATCH_HEADER_BYTES,
        &output,
        &inputBytes);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    if (output == NULL || inputBytes != OutputBufferLength) {
        return STATUS_INVALID_BUFFER_SIZE;
    }
    input = (const UINT8 *)output;
    RtlCopyMemory(&batch, input, sizeof(batch));
    if (batch.Magic != FCX_STRICT_DATAGRAM_BATCH_MAGIC ||
        batch.Protocol != FCX_STRICT_DATAGRAM_PROTOCOL ||
        batch.HeaderBytes != FCX_STRICT_DATAGRAM_BATCH_HEADER_BYTES ||
        batch.Kind != FCX_STRICT_DATAGRAM_KIND_REPLY ||
        !FcxBytesAreZero(batch.Reserved0, sizeof(batch.Reserved0)) ||
        batch.TotalBytes != (UINT32)inputBytes ||
        batch.RecordCount == 0 ||
        batch.RecordCount > FCX_STRICT_DATAGRAM_MAX_RECORDS ||
        batch.Reserved1 != 0 ||
        !FcxBytesAreZero(batch.Reserved2, sizeof(batch.Reserved2))) {
        return STATUS_INVALID_PARAMETER;
    }
    if (!FcxLeaseOwnsRequest(Request, &batch)) {
        return STATUS_ACCESS_DENIED;
    }
    cursor = FCX_STRICT_DATAGRAM_BATCH_HEADER_BYTES;
    for (recordIndex = 0; recordIndex < batch.RecordCount; ++recordIndex) {
        status = FcxValidateSubmittedDatagramRecord(
            input + cursor,
            batch.TotalBytes - cursor,
            &recordBytes);
        if (!NT_SUCCESS(status)) {
            return status;
        }
        cursor += recordBytes;
    }
    if (cursor != batch.TotalBytes) {
        return STATUS_INVALID_PARAMETER;
    }

    // Reply injection is deliberately unavailable until the WFP injection
    // handles and per-flow provenance path are implemented and VM-qualified.
    return STATUS_NOT_SUPPORTED;
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

    if (IoControlCode == IOCTL_FCX_STRICT_RECEIVE_DATAGRAM_BATCH) {
        status = FcxQueueDatagramReceive(Request,
                                         OutputBufferLength,
                                         InputBufferLength);
        if (!NT_SUCCESS(status)) {
            WdfRequestComplete(Request, status);
        }
        return;
    }
    if (IoControlCode == IOCTL_FCX_STRICT_SUBMIT_DATAGRAM_BATCH) {
        status = FcxValidateSubmittedDatagramBatch(Request,
                                                   OutputBufferLength,
                                                   InputBufferLength);
        WdfRequestComplete(Request, status);
        return;
    }

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
    const GUID *keys[8] = {
        &FcxGuardV4CalloutKey,
        &FcxGuardV6CalloutKey,
        &FcxRedirectV4CalloutKey,
        &FcxRedirectV6CalloutKey,
        &FcxFlowV4CalloutKey,
        &FcxFlowV6CalloutKey,
        &FcxDatagramV4CalloutKey,
        &FcxDatagramV6CalloutKey
    };
    FWPS_CALLOUT_CLASSIFY_FN1 classifyFunctions[8] = {
        FcxGuardClassifyV4,
        FcxGuardClassifyV6,
        FcxRedirectClassifyV4,
        FcxRedirectClassifyV6,
        FcxFlowClassifyV4,
        FcxFlowClassifyV6,
        FcxDatagramClassifyV4,
        FcxDatagramClassifyV6
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
        if (index == FCX_CALLOUT_DATAGRAM_V4 ||
            index == FCX_CALLOUT_DATAGRAM_V6) {
            callout.flags = FWP_CALLOUT_FLAG_CONDITIONAL_ON_FLOW;
            callout.flowDeleteFn = FcxDatagramFlowDelete;
        }
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

    if (FcxProcessNotifyRegistered) {
        (VOID)PsSetCreateProcessNotifyRoutineEx(FcxProcessNotify, TRUE);
        FcxProcessNotifyRegistered = FALSE;
    }
    FcxReleaseLease();
    FcxUnregisterCallouts();
    FcxDestroyRedirectHandle();
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
    FcxDatagramReceiveQueue = NULL;
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
    KeInitializeSpinLock(&FcxUdpFlowLock);
    InitializeListHead(&FcxUdpFlowList);
    KeInitializeEvent(&FcxUdpFlowEmptyEvent, NotificationEvent, TRUE);

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

    WDF_IO_QUEUE_CONFIG_INIT(&queueConfig, WdfIoQueueDispatchManual);
    queueConfig.PowerManaged = WdfFalse;
    WDF_OBJECT_ATTRIBUTES_INIT(&attributes);
    WDF_OBJECT_ATTRIBUTES_SET_EXECUTION_LEVEL(&attributes,
                                               WdfExecutionLevelPassive);
    status = WdfIoQueueCreate(FcxControlDevice,
                              &queueConfig,
                              &attributes,
                              &FcxDatagramReceiveQueue);
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
    FcxDatagramReceiveQueue = NULL;
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
