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

static WDFDEVICE FcxControlDevice;
static PEX_RUNDOWN_REF_CACHE_AWARE FcxPolicyRundown;
static volatile PVOID FcxPolicySnapshot;
static volatile LONG64 FcxPolicyGeneration;
static UINT32 FcxCalloutIds[4];
static UINT32 FcxRegisteredCallouts;

static
VOID NTAPI
FcxGuardClassifyV4(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_ const FWPS_FILTER0 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    );

static
VOID NTAPI
FcxGuardClassifyV6(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_ const FWPS_FILTER0 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    );

static
VOID NTAPI
FcxRedirectClassifyV4(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_ const FWPS_FILTER0 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    );

static
VOID NTAPI
FcxRedirectClassifyV6(
    _In_ const FWPS_INCOMING_VALUES0 *IncomingValues,
    _In_ const FWPS_INCOMING_METADATA_VALUES0 *IncomingMetadata,
    _Inout_opt_ VOID *LayerData,
    _In_ const FWPS_FILTER0 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    );

static
NTSTATUS NTAPI
FcxCalloutNotify(
    _In_ FWPS_CALLOUT_NOTIFY_TYPE NotifyType,
    _In_ const GUID *FilterKey,
    _Inout_ FWPS_FILTER0 *Filter
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
    _In_ const FWPS_FILTER0 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    UNREFERENCED_PARAMETER(IncomingMetadata);
    UNREFERENCED_PARAMETER(LayerData);
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
    _In_ const FWPS_FILTER0 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    UNREFERENCED_PARAMETER(IncomingMetadata);
    UNREFERENCED_PARAMETER(LayerData);
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
    _In_ const FWPS_FILTER0 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    UNREFERENCED_PARAMETER(IncomingMetadata);
    UNREFERENCED_PARAMETER(LayerData);
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
    _In_ const FWPS_FILTER0 *Filter,
    _In_ UINT64 FlowContext,
    _Inout_ FWPS_CLASSIFY_OUT0 *ClassifyOut
    )
{
    UNREFERENCED_PARAMETER(IncomingMetadata);
    UNREFERENCED_PARAMETER(LayerData);
    UNREFERENCED_PARAMETER(Filter);
    UNREFERENCED_PARAMETER(FlowContext);
    FcxClassifySelectedApp(IncomingValues,
                           FWPS_FIELD_ALE_CONNECT_REDIRECT_V6_ALE_APP_ID,
                           ClassifyOut);
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
        FcxReleasePolicy();
        InterlockedIncrement64(&FcxPolicyGeneration);
        status = STATUS_SUCCESS;
        break;
    case IOCTL_FCX_STRICT_QUERY_POLICY:
        status = InputBufferLength == 0 ? STATUS_SUCCESS :
                                          STATUS_INVALID_BUFFER_SIZE;
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
FcxRegisterCallouts(
    _In_ PDEVICE_OBJECT DeviceObject
    )
{
    NTSTATUS status;
    FWPS_CALLOUT0 callout;
    const GUID *keys[4] = {
        &FcxGuardV4CalloutKey,
        &FcxGuardV6CalloutKey,
        &FcxRedirectV4CalloutKey,
        &FcxRedirectV6CalloutKey
    };
    FWPS_CALLOUT_CLASSIFY_FN0 classifyFunctions[4] = {
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
        status = FwpsCalloutRegister0(DeviceObject,
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
    FcxReleasePolicy();
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

    FcxPolicyRundown = ExAllocateCacheAwareRundownProtection(
        NonPagedPoolNx,
        FCX_STRICT_POOL_TAG);
    if (FcxPolicyRundown == NULL) {
        status = STATUS_INSUFFICIENT_RESOURCES;
        goto Failure;
    }

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
    FcxControlDevice = NULL;
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
#pragma alloc_text(PAGE, FcxRegisterCallouts)
#endif
