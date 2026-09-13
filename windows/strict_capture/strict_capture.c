#include "strict_capture.h"

const GUID g_ScCalloutV4 = { 0x5a6f70e1, 0x6b7f, 0x4d5a, { 0x9c, 0x55, 0x42, 0x88, 0x1d, 0x62, 0x90, 0x10 } };
const GUID g_ScCalloutV6 = { 0x5a6f70e2, 0x6b7f, 0x4d5a, { 0x9c, 0x55, 0x42, 0x88, 0x1d, 0x62, 0x90, 0x10 } };

typedef struct _SC_POLICY {
    ULONG ProcessId;
    ULONG Flags;
    ULONG ProxyIpv4;
    USHORT ProxyPort;
    BOOLEAN InUse;
} SC_POLICY;

static PDEVICE_OBJECT g_Device;
static UINT32 g_CalloutIdV4;
static UINT32 g_CalloutIdV6;
static KSPIN_LOCK g_PolicyLock;
static SC_POLICY g_Policies[SC_MAX_POLICIES];
static ULONG g_Generation;

static BOOLEAN ScHasPolicy(ULONG processId)
{
    BOOLEAN found = FALSE;
    KIRQL oldIrql;
    KeAcquireSpinLock(&g_PolicyLock, &oldIrql);
    for (ULONG i = 0; i < SC_MAX_POLICIES; ++i) {
        if (g_Policies[i].InUse && g_Policies[i].ProcessId == processId) {
            found = TRUE;
            break;
        }
    }
    KeReleaseSpinLock(&g_PolicyLock, oldIrql);
    return found;
}

static NTSTATUS ScUpdatePolicy(const SC_POLICY_UPDATE* update)
{
    if (update->Version != SC_PROTOCOL_VERSION || update->ProcessId == 0 || update->ProxyPort == 0) {
        return STATUS_INVALID_PARAMETER;
    }
    KIRQL oldIrql;
    NTSTATUS status = STATUS_INSUFFICIENT_RESOURCES;
    KeAcquireSpinLock(&g_PolicyLock, &oldIrql);
    ULONG freeIndex = SC_MAX_POLICIES;
    for (ULONG i = 0; i < SC_MAX_POLICIES; ++i) {
        if (g_Policies[i].InUse && g_Policies[i].ProcessId == update->ProcessId) {
            freeIndex = i;
            break;
        }
        if (!g_Policies[i].InUse && freeIndex == SC_MAX_POLICIES) {
            freeIndex = i;
        }
    }
    if (freeIndex < SC_MAX_POLICIES) {
        g_Policies[freeIndex].ProcessId = update->ProcessId;
        g_Policies[freeIndex].Flags = update->Flags;
        g_Policies[freeIndex].ProxyIpv4 = update->ProxyIpv4;
        g_Policies[freeIndex].ProxyPort = update->ProxyPort;
        g_Policies[freeIndex].InUse = TRUE;
        ++g_Generation;
        status = STATUS_SUCCESS;
    }
    KeReleaseSpinLock(&g_PolicyLock, oldIrql);
    return status;
}

static NTSTATUS ScClearPolicy(const SC_POLICY_CLEAR* clear)
{
    if (clear->Version != SC_PROTOCOL_VERSION || clear->ProcessId == 0) {
        return STATUS_INVALID_PARAMETER;
    }
    KIRQL oldIrql;
    NTSTATUS status = STATUS_NOT_FOUND;
    KeAcquireSpinLock(&g_PolicyLock, &oldIrql);
    for (ULONG i = 0; i < SC_MAX_POLICIES; ++i) {
        if (g_Policies[i].InUse && g_Policies[i].ProcessId == clear->ProcessId) {
            RtlZeroMemory(&g_Policies[i], sizeof(g_Policies[i]));
            ++g_Generation;
            status = STATUS_SUCCESS;
            break;
        }
    }
    KeReleaseSpinLock(&g_PolicyLock, oldIrql);
    return status == STATUS_NOT_FOUND ? STATUS_SUCCESS : status;
}

static ULONG ScPolicyCount(void)
{
    ULONG count = 0;
    KIRQL oldIrql;
    KeAcquireSpinLock(&g_PolicyLock, &oldIrql);
    for (ULONG i = 0; i < SC_MAX_POLICIES; ++i) {
        count += g_Policies[i].InUse ? 1u : 0u;
    }
    KeReleaseSpinLock(&g_PolicyLock, oldIrql);
    return count;
}

void NTAPI ScClassify(
    const FWPS_INCOMING_VALUES0* inFixedValues,
    const FWPS_INCOMING_METADATA_VALUES0* inMetaValues,
    void* layerData,
    const FWPS_FILTER0* filter,
    UINT64 flowContext,
    FWPS_CLASSIFY_OUT0* classifyOut)
{
    UNREFERENCED_PARAMETER(inFixedValues);
    UNREFERENCED_PARAMETER(layerData);
    UNREFERENCED_PARAMETER(filter);
    UNREFERENCED_PARAMETER(flowContext);

    // No process identity means there is no safe way to apply a per-app
    // policy.  Permit unselected traffic; selected traffic is fail-closed.
    ULONG processId = 0;
    if (inMetaValues != NULL && (inMetaValues->currentMetadataValues & FWPS_METADATA_FIELD_PROCESS_ID) != 0) {
        processId = (ULONG)(ULONG_PTR)inMetaValues->processId;
    }
    if (ScHasPolicy(processId)) {
        classifyOut->actionType = FWP_ACTION_BLOCK;
        classifyOut->rights &= ~FWPS_RIGHT_ACTION_WRITE;
        DbgPrintEx(DPFLTR_IHVNETWORK_ID, DPFLTR_TRACE_LEVEL, "FlClashXStrictCapture: blocked pid=%lu pending redirect\\n", processId);
    } else {
        classifyOut->actionType = FWP_ACTION_PERMIT;
    }
}

static NTSTATUS ScRegisterCallout(PDEVICE_OBJECT device, const GUID* key, UINT32 layerId, UINT32* id)
{
    FWPS_CALLOUT0 callout = { 0 };
    callout.calloutKey = *key;
    callout.classifyFn = ScClassify;
    NTSTATUS status = FwpsCalloutRegister0(device, &callout, id);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    UNREFERENCED_PARAMETER(layerId);
    return STATUS_SUCCESS;
}

void ScUnload(PDRIVER_OBJECT driverObject)
{
    UNREFERENCED_PARAMETER(driverObject);
    if (g_CalloutIdV4 != 0) {
        FwpsCalloutUnregisterById0(g_CalloutIdV4);
    }
    if (g_CalloutIdV6 != 0) {
        FwpsCalloutUnregisterById0(g_CalloutIdV6);
    }
    if (g_Device != NULL) {
        UNICODE_STRING link;
        RtlInitUnicodeString(&link, SC_DOS_DEVICE_NAME);
        IoDeleteSymbolicLink(&link);
        IoDeleteDevice(g_Device);
        g_Device = NULL;
    }
}

NTSTATUS ScCreateClose(PDEVICE_OBJECT deviceObject, PIRP irp)
{
    UNREFERENCED_PARAMETER(deviceObject);
    irp->IoStatus.Status = STATUS_SUCCESS;
    irp->IoStatus.Information = 0;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return STATUS_SUCCESS;
}

NTSTATUS ScDeviceControl(PDEVICE_OBJECT deviceObject, PIRP irp)
{
    UNREFERENCED_PARAMETER(deviceObject);
    PIO_STACK_LOCATION stack = IoGetCurrentIrpStackLocation(irp);
    ULONG code = stack->Parameters.DeviceIoControl.IoControlCode;
    ULONG inputLength = stack->Parameters.DeviceIoControl.InputBufferLength;
    ULONG outputLength = stack->Parameters.DeviceIoControl.OutputBufferLength;
    NTSTATUS status = STATUS_INVALID_DEVICE_REQUEST;
    ULONG_PTR information = 0;

    if (code == IOCTL_SC_UPDATE_POLICY && inputLength >= sizeof(SC_POLICY_UPDATE)) {
        status = ScUpdatePolicy((const SC_POLICY_UPDATE*)irp->AssociatedIrp.SystemBuffer);
    } else if (code == IOCTL_SC_CLEAR_POLICY && inputLength >= sizeof(SC_POLICY_CLEAR)) {
        status = ScClearPolicy((const SC_POLICY_CLEAR*)irp->AssociatedIrp.SystemBuffer);
    } else if (code == IOCTL_SC_QUERY_STATUS && outputLength >= sizeof(SC_STATUS)) {
        SC_STATUS* response = (SC_STATUS*)irp->AssociatedIrp.SystemBuffer;
        response->Version = SC_PROTOCOL_VERSION;
        response->PolicyCount = ScPolicyCount();
        response->RegisteredCallouts = (g_CalloutIdV4 != 0 ? 1u : 0u) + (g_CalloutIdV6 != 0 ? 1u : 0u);
        response->Generation = g_Generation;
        information = sizeof(*response);
        status = STATUS_SUCCESS;
    }
    irp->IoStatus.Status = status;
    irp->IoStatus.Information = information;
    IoCompleteRequest(irp, IO_NO_INCREMENT);
    return status;
}

NTSTATUS DriverEntry(PDRIVER_OBJECT driverObject, PUNICODE_STRING registryPath)
{
    UNREFERENCED_PARAMETER(registryPath);
    UNICODE_STRING deviceName;
    UNICODE_STRING linkName;
    RtlInitUnicodeString(&deviceName, SC_DEVICE_NAME);
    RtlInitUnicodeString(&linkName, SC_DOS_DEVICE_NAME);
    KeInitializeSpinLock(&g_PolicyLock);

    NTSTATUS status = IoCreateDevice(driverObject, 0, &deviceName, FILE_DEVICE_NETWORK, FILE_DEVICE_SECURE_OPEN, FALSE, &g_Device);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    status = IoCreateSymbolicLink(&linkName, &deviceName);
    if (!NT_SUCCESS(status)) {
        IoDeleteDevice(g_Device);
        g_Device = NULL;
        return status;
    }
    for (ULONG i = 0; i <= IRP_MJ_MAXIMUM_FUNCTION; ++i) {
        driverObject->MajorFunction[i] = ScCreateClose;
    }
    driverObject->MajorFunction[IRP_MJ_DEVICE_CONTROL] = ScDeviceControl;
    driverObject->DriverUnload = ScUnload;

    status = ScRegisterCallout(g_Device, &g_ScCalloutV4, FWPS_LAYER_ALE_CONNECT_REDIRECT_V4, &g_CalloutIdV4);
    if (NT_SUCCESS(status)) {
        status = ScRegisterCallout(g_Device, &g_ScCalloutV6, FWPS_LAYER_ALE_CONNECT_REDIRECT_V6, &g_CalloutIdV6);
    }
    if (!NT_SUCCESS(status)) {
        ScUnload(driverObject);
    }
    return status;
}
