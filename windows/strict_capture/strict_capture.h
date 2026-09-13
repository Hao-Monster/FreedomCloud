#pragma once

#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0x0A00000Cu
#endif
#ifndef NDIS_WDM
#define NDIS_WDM 1
#endif
#ifndef NDIS60
#define NDIS60 1
#endif
#include <ntddk.h>
#include <fwpsk.h>
#include <fwpmk.h>

#define SC_DEVICE_NAME      L"\\Device\\FlClashXStrictCapture"
#define SC_DOS_DEVICE_NAME  L"\\DosDevices\\FlClashXStrictCapture"

#define SC_IOCTL_BASE 0x8337
#define IOCTL_SC_UPDATE_POLICY CTL_CODE(FILE_DEVICE_NETWORK, SC_IOCTL_BASE + 0, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_SC_CLEAR_POLICY  CTL_CODE(FILE_DEVICE_NETWORK, SC_IOCTL_BASE + 1, METHOD_BUFFERED, FILE_ANY_ACCESS)
#define IOCTL_SC_QUERY_STATUS  CTL_CODE(FILE_DEVICE_NETWORK, SC_IOCTL_BASE + 2, METHOD_BUFFERED, FILE_ANY_ACCESS)

#define SC_PROTOCOL_VERSION 1u
#define SC_MAX_POLICIES 128u
#define SC_POLICY_FLAG_REDIRECT_READY 0x00000001u

typedef struct _SC_POLICY_UPDATE {
    ULONG Version;
    ULONG Flags;
    ULONG ProcessId;
    ULONG ProxyIpv4;       // network byte order; zero means broker-owned endpoint
    USHORT ProxyPort;
    USHORT Reserved;
} SC_POLICY_UPDATE, *PSC_POLICY_UPDATE;

typedef struct _SC_POLICY_CLEAR {
    ULONG Version;
    ULONG ProcessId;
} SC_POLICY_CLEAR, *PSC_POLICY_CLEAR;

typedef struct _SC_STATUS {
    ULONG Version;
    ULONG PolicyCount;
    ULONG RegisteredCallouts;
    ULONG Generation;
} SC_STATUS, *PSC_STATUS;

extern const GUID g_ScCalloutV4;
extern const GUID g_ScCalloutV6;

DRIVER_INITIALIZE DriverEntry;
DRIVER_UNLOAD ScUnload;
DRIVER_DISPATCH ScCreateClose;
DRIVER_DISPATCH ScDeviceControl;

void NTAPI ScClassify(
    const FWPS_INCOMING_VALUES0* inFixedValues,
    const FWPS_INCOMING_METADATA_VALUES0* inMetaValues,
    void* layerData,
    const FWPS_FILTER0* filter,
    UINT64 flowContext,
    FWPS_CLASSIFY_OUT0* classifyOut);
