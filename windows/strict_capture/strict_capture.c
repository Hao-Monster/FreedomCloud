#include "strict_capture.h"

const GUID g_ScCalloutV4 = { 0x5a6f70e1, 0x6b7f, 0x4d5a, { 0x9c, 0x55, 0x42, 0x88, 0x1d, 0x62, 0x90, 0x10 } };
const GUID g_ScCalloutV6 = { 0x5a6f70e2, 0x6b7f, 0x4d5a, { 0x9c, 0x55, 0x42, 0x88, 0x1d, 0x62, 0x90, 0x10 } };
const GUID g_ScProvider = { 0x5a6f70e0, 0x6b7f, 0x4d5a, { 0x9c, 0x55, 0x42, 0x88, 0x1d, 0x62, 0x90, 0x10 } };

typedef struct _SC_POLICY {
    ULONG ProcessId;
    ULONG BrokerProcessId;
    ULONG Flags;
    ULONG ProxyIpv4;
    USHORT ProxyPort;
    UCHAR ProxyIpv6[16];
    BOOLEAN InUse;
} SC_POLICY;

static PDEVICE_OBJECT g_Device;
static UINT32 g_CalloutIdV4;
static UINT32 g_CalloutIdV6;
static HANDLE g_RedirectHandle;
static KSPIN_LOCK g_PolicyLock;
static SC_POLICY g_Policies[SC_MAX_POLICIES];
static ULONG g_Generation;

static BOOLEAN ScGetPolicy(ULONG processId, SC_POLICY* result)
{
    BOOLEAN found = FALSE;
    KIRQL oldIrql;
    KeAcquireSpinLock(&g_PolicyLock, &oldIrql);
    for (ULONG i = 0; i < SC_MAX_POLICIES; ++i) {
        if (g_Policies[i].InUse && g_Policies[i].ProcessId == processId) {
            *result = g_Policies[i];
            found = TRUE;
            break;
        }
    }
    KeReleaseSpinLock(&g_PolicyLock, oldIrql);
    return found;
}

static NTSTATUS ScUpdatePolicy(const SC_POLICY_UPDATE* update)
{
    if (update->Version != SC_PROTOCOL_VERSION || update->ProcessId == 0 ||
        update->BrokerProcessId == 0 || update->ProxyPort == 0) {
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
        g_Policies[freeIndex].BrokerProcessId = update->BrokerProcessId;
        g_Policies[freeIndex].Flags = update->Flags;
        g_Policies[freeIndex].ProxyIpv4 = update->ProxyIpv4;
        g_Policies[freeIndex].ProxyPort = update->ProxyPort;
        RtlCopyMemory(g_Policies[freeIndex].ProxyIpv6, update->ProxyIpv6, sizeof(update->ProxyIpv6));
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
    const void* classifyContext,
    const FWPS_FILTER2* filter,
    UINT64 flowContext,
    FWPS_CLASSIFY_OUT0* classifyOut)
{
    UNREFERENCED_PARAMETER(inFixedValues);
    UNREFERENCED_PARAMETER(flowContext);

    // No process identity means there is no safe way to apply a per-app
    // policy.  Permit unselected traffic; selected traffic is fail-closed.
    ULONG processId = 0;
    if (inMetaValues != NULL && (inMetaValues->currentMetadataValues & FWPS_METADATA_FIELD_PROCESS_ID) != 0) {
        processId = (ULONG)(ULONG_PTR)inMetaValues->processId;
    }
    SC_POLICY policy = { 0 };
    if (!ScGetPolicy(processId, &policy)) {
        classifyOut->actionType = FWP_ACTION_PERMIT;
        return;
    }

    // A selected flow is blocked until the broker has supplied a concrete
    // endpoint and accepting PID. This preserves strict fail-closed behavior.
    if ((policy.Flags & SC_POLICY_FLAG_REDIRECT_READY) == 0 ||
        policy.BrokerProcessId == 0 || g_RedirectHandle == NULL ||
        classifyContext == NULL ||
        filter == NULL || layerData == NULL) {
        classifyOut->actionType = FWP_ACTION_BLOCK;
        classifyOut->rights &= ~FWPS_RIGHT_ACTION_WRITE;
        DbgPrintEx(DPFLTR_IHVNETWORK_ID, DPFLTR_TRACE_LEVEL,
            "FlClashXStrictCapture: blocked pid=%lu (redirect unavailable)\\n", processId);
        return;
    }

    if (inMetaValues->redirectRecords != NULL) {
        void* redirectContext = NULL;
        FWPS_CONNECTION_REDIRECT_STATE redirectState = FwpsQueryConnectionRedirectState0(
            inMetaValues->redirectRecords, g_RedirectHandle, &redirectContext);
        if (redirectState == FWPS_CONNECTION_REDIRECTED_BY_SELF ||
            redirectState == FWPS_CONNECTION_PREVIOUSLY_REDIRECTED_BY_SELF) {
            classifyOut->actionType = FWP_ACTION_PERMIT;
            return;
        }
        if (redirectState == FWPS_CONNECTION_REDIRECTED_BY_OTHER) {
            classifyOut->actionType = FWP_ACTION_BLOCK;
            classifyOut->rights &= ~FWPS_RIGHT_ACTION_WRITE;
            return;
        }
    }

    UINT64 classifyHandle = 0;
    NTSTATUS status = FwpsAcquireClassifyHandle0((PVOID)classifyContext, 0, &classifyHandle);
    if (!NT_SUCCESS(status)) {
        classifyOut->actionType = FWP_ACTION_BLOCK;
        classifyOut->rights &= ~FWPS_RIGHT_ACTION_WRITE;
        return;
    }
    PVOID writableLayerData = NULL;
    status = FwpsAcquireWritableLayerDataPointer0(
        classifyHandle, filter->filterId, 0, &writableLayerData, classifyOut);
    if (!NT_SUCCESS(status) || writableLayerData == NULL) {
        classifyOut->actionType = FWP_ACTION_BLOCK;
        classifyOut->rights &= ~FWPS_RIGHT_ACTION_WRITE;
        DbgPrintEx(DPFLTR_IHVNETWORK_ID, DPFLTR_ERROR_LEVEL,
            "FlClashXStrictCapture: writable connect request failed pid=%lu status=0x%08x\\n",
            processId, status);
        FwpsReleaseClassifyHandle0(classifyHandle);
        return;
    }

    FWPS_CONNECT_REQUEST0* request = (FWPS_CONNECT_REQUEST0*)writableLayerData;
    USHORT family = ((PSOCKADDR)&request->remoteAddressAndPort)->sa_family;
    if (family == AF_INET) {
        PSOCKADDR_IN endpoint = (PSOCKADDR_IN)&request->localAddressAndPort;
        RtlZeroMemory(endpoint, sizeof(*endpoint));
        endpoint->sin_family = AF_INET;
        endpoint->sin_port = RtlUshortByteSwap(policy.ProxyPort);
        endpoint->sin_addr.S_un.S_addr = policy.ProxyIpv4;
    } else if (family == AF_INET6) {
        PSOCKADDR_IN6 endpoint = (PSOCKADDR_IN6)&request->localAddressAndPort;
        RtlZeroMemory(endpoint, sizeof(*endpoint));
        endpoint->sin6_family = AF_INET6;
        endpoint->sin6_port = RtlUshortByteSwap(policy.ProxyPort);
        UCHAR zeroAddress[16] = { 0 };
        if (RtlCompareMemory(policy.ProxyIpv6, zeroAddress, sizeof(zeroAddress)) == sizeof(zeroAddress)) {
            endpoint->sin6_addr.u.Byte[10] = 0xff;
            endpoint->sin6_addr.u.Byte[11] = 0xff;
            *(ULONG*)&endpoint->sin6_addr.u.Byte[12] = policy.ProxyIpv4;
        } else {
            RtlCopyMemory(endpoint->sin6_addr.u.Byte, policy.ProxyIpv6, sizeof(policy.ProxyIpv6));
        }
    } else {
        classifyOut->actionType = FWP_ACTION_BLOCK;
        classifyOut->rights &= ~FWPS_RIGHT_ACTION_WRITE;
        FwpsReleaseClassifyHandle0(classifyHandle);
        return;
    }

    request->localRedirectHandle = g_RedirectHandle;
    request->localRedirectTargetPID = policy.BrokerProcessId;
    classifyOut->actionType = FWP_ACTION_PERMIT;
    FwpsApplyModifiedLayerData0(classifyHandle, writableLayerData, 0);
    DbgPrintEx(DPFLTR_IHVNETWORK_ID, DPFLTR_TRACE_LEVEL,
        "FlClashXStrictCapture: redirected pid=%lu broker=%lu port=%hu family=%hu\\n",
        processId, policy.BrokerProcessId, policy.ProxyPort, family);
    FwpsReleaseClassifyHandle0(classifyHandle);
}

static NTSTATUS ScRegisterCallout(PDEVICE_OBJECT device, const GUID* key, UINT32 layerId, UINT32* id)
{
    FWPS_CALLOUT2 callout = { 0 };
    callout.calloutKey = *key;
    callout.classifyFn = ScClassify;
    NTSTATUS status = FwpsCalloutRegister2(device, &callout, id);
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
    if (g_RedirectHandle != NULL) {
        FwpsRedirectHandleDestroy0(g_RedirectHandle);
        g_RedirectHandle = NULL;
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
        return status;
    }
    status = FwpsRedirectHandleCreate0(&g_ScProvider, 0, &g_RedirectHandle);
    if (!NT_SUCCESS(status)) {
        ScUnload(driverObject);
    }
    return status;
}
