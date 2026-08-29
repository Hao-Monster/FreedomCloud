#pragma once

// This ABI is shared by the signed callout driver and the LocalSystem Broker.
// Every multibyte field is little-endian. Structures are byte-packed so the
// kernel must copy fields into aligned locals before using 64-bit values.

#if defined(_KERNEL_MODE)
#include <ntddk.h>
#else
#include <Windows.h>
#include <winioctl.h>
#endif

#define FCX_STRICT_WIRE_MAGIC ((UINT32)0x53584346u) /* "FCXS" */
#define FCX_STRICT_WIRE_PROTOCOL ((UINT16)2u)

#define FCX_STRICT_POLICY_HEADER_BYTES ((UINT16)112u)
#define FCX_STRICT_POLICY_RULE_BYTES ((UINT16)16u)
#define FCX_STRICT_ENDPOINT_LEASE_BYTES ((UINT16)160u)
#define FCX_STRICT_ENDPOINT_BYTES ((UINT16)20u)
#define FCX_STRICT_SNAPSHOT_BYTES ((UINT16)168u)
#define FCX_STRICT_MAX_RULES ((UINT32)(128u * 33u))
#define FCX_STRICT_MAX_APP_ID_BYTES ((UINT32)4096u)
#define FCX_STRICT_MAX_POLICY_BYTES ((UINT32)(3u * 1024u * 1024u))

#define FCX_STRICT_REDIRECT_CONTEXT_MAGIC ((UINT32)0x43584346u) /* "FCXC" */
#define FCX_STRICT_REDIRECT_CONTEXT_PROTOCOL ((UINT16)1u)
#define FCX_STRICT_REDIRECT_CONTEXT_BYTES ((UINT16)112u)
#define FCX_STRICT_ADDRESS_FAMILY_V4 ((UINT8)4u)
#define FCX_STRICT_ADDRESS_FAMILY_V6 ((UINT8)6u)

#define FCX_STRICT_DATAGRAM_BATCH_MAGIC ((UINT32)0x42584346u) /* "FCXB" */
#define FCX_STRICT_DATAGRAM_PROTOCOL ((UINT16)1u)
#define FCX_STRICT_DATAGRAM_BATCH_HEADER_BYTES ((UINT16)96u)
#define FCX_STRICT_DATAGRAM_RECORD_HEADER_BYTES ((UINT16)80u)
#define FCX_STRICT_DATAGRAM_MAX_BATCH_BYTES ((UINT32)(256u * 1024u))
#define FCX_STRICT_DATAGRAM_MAX_RECORDS ((UINT32)64u)
#define FCX_STRICT_DATAGRAM_MAX_PAYLOAD_BYTES ((UINT32)(16u * 1024u))
#define FCX_STRICT_DATAGRAM_MAX_IN_FLIGHT ((UINT32)256u)
#define FCX_STRICT_DATAGRAM_KIND_CAPTURED ((UINT8)1u)
#define FCX_STRICT_DATAGRAM_KIND_REPLY ((UINT8)2u)
#define FCX_STRICT_DATAGRAM_FLAG_DNS ((UINT32)(1u << 0))
#define FCX_STRICT_DATAGRAM_FLAG_QUIC ((UINT32)(1u << 1))
#define FCX_STRICT_DATAGRAM_KNOWN_FLAGS                                      \
    (FCX_STRICT_DATAGRAM_FLAG_DNS | FCX_STRICT_DATAGRAM_FLAG_QUIC)

#define FCX_STRICT_ACTION_PROXY ((UINT8)1u)
#define FCX_STRICT_ACTION_BLOCK ((UINT8)2u)
#define FCX_STRICT_NO_TARGET_GROUP ((UINT16)0xffffu)

#define FCX_STRICT_SNAPSHOT_FLAG_LOADED ((UINT32)0x00000001u)
#define FCX_STRICT_SNAPSHOT_FLAG_LEASE_ACTIVE ((UINT32)0x00000002u)
#define FCX_STRICT_SNAPSHOT_FLAG_DATAGRAM_ACTIVE ((UINT32)0x00000004u)

#define FCX_STRICT_MIN_LEASE_MILLIS ((UINT32)1000u)
#define FCX_STRICT_MAX_LEASE_MILLIS ((UINT32)30000u)

#define FCX_STRICT_CAP_TCP4_REDIRECT (1ull << 0)
#define FCX_STRICT_CAP_TCP6_REDIRECT (1ull << 1)
#define FCX_STRICT_CAP_UDP4_REDIRECT (1ull << 2)
#define FCX_STRICT_CAP_UDP6_REDIRECT (1ull << 3)
#define FCX_STRICT_CAP_DNS_CAPTURED (1ull << 4)
#define FCX_STRICT_CAP_QUIC_CAPTURED (1ull << 5)
#define FCX_STRICT_CAP_REDIRECT_LOOP_PROTECTED (1ull << 6)
#define FCX_STRICT_CAP_PERSISTENT_FAIL_CLOSED (1ull << 7)
#define FCX_STRICT_KNOWN_CAPABILITIES                                          \
    (FCX_STRICT_CAP_TCP4_REDIRECT | FCX_STRICT_CAP_TCP6_REDIRECT |             \
     FCX_STRICT_CAP_UDP4_REDIRECT | FCX_STRICT_CAP_UDP6_REDIRECT |             \
     FCX_STRICT_CAP_DNS_CAPTURED | FCX_STRICT_CAP_QUIC_CAPTURED |              \
     FCX_STRICT_CAP_REDIRECT_LOOP_PROTECTED |                                  \
     FCX_STRICT_CAP_PERSISTENT_FAIL_CLOSED)

#define FCX_STRICT_DEVICE_TYPE FILE_DEVICE_NETWORK
#define FCX_STRICT_IOCTL_ACCESS (FILE_READ_DATA | FILE_WRITE_DATA)
#define IOCTL_FCX_STRICT_UPLOAD_POLICY                                         \
    CTL_CODE(FCX_STRICT_DEVICE_TYPE, 0x900u, METHOD_BUFFERED,                  \
             FCX_STRICT_IOCTL_ACCESS)
#define IOCTL_FCX_STRICT_UNLOAD_POLICY                                         \
    CTL_CODE(FCX_STRICT_DEVICE_TYPE, 0x901u, METHOD_BUFFERED,                  \
             FCX_STRICT_IOCTL_ACCESS)
#define IOCTL_FCX_STRICT_QUERY_POLICY                                          \
    CTL_CODE(FCX_STRICT_DEVICE_TYPE, 0x902u, METHOD_BUFFERED,                  \
             FCX_STRICT_IOCTL_ACCESS)
#define IOCTL_FCX_STRICT_ACTIVATE_LEASE                                       \
    CTL_CODE(FCX_STRICT_DEVICE_TYPE, 0x903u, METHOD_BUFFERED,                  \
             FCX_STRICT_IOCTL_ACCESS)
#define IOCTL_FCX_STRICT_REVOKE_LEASE                                         \
    CTL_CODE(FCX_STRICT_DEVICE_TYPE, 0x904u, METHOD_BUFFERED,                  \
             FCX_STRICT_IOCTL_ACCESS)
#define IOCTL_FCX_STRICT_RECEIVE_DATAGRAM_BATCH                               \
    CTL_CODE(FCX_STRICT_DEVICE_TYPE, 0x905u, METHOD_OUT_DIRECT,                \
             FCX_STRICT_IOCTL_ACCESS)
#define IOCTL_FCX_STRICT_SUBMIT_DATAGRAM_BATCH                                \
    CTL_CODE(FCX_STRICT_DEVICE_TYPE, 0x906u, METHOD_IN_DIRECT,                 \
             FCX_STRICT_IOCTL_ACCESS)
#define IOCTL_FCX_STRICT_ACTIVATE_DATAGRAM_PATH                               \
    CTL_CODE(FCX_STRICT_DEVICE_TYPE, 0x907u, METHOD_BUFFERED,                  \
             FCX_STRICT_IOCTL_ACCESS)
#define IOCTL_FCX_STRICT_DEACTIVATE_DATAGRAM_PATH                             \
    CTL_CODE(FCX_STRICT_DEVICE_TYPE, 0x908u, METHOD_BUFFERED,                  \
             FCX_STRICT_IOCTL_ACCESS)

#pragma pack(push, 1)

typedef struct _FCX_STRICT_POLICY_HEADER {
    UINT32 Magic;
    UINT16 Protocol;
    UINT16 HeaderBytes;
    UINT32 TotalBytes;
    UINT32 RuleCount;
    UINT32 TargetGroupCount;
    UINT32 Reserved0;
    UINT64 Revision;
    UINT8 PolicyDigest[32];
    UINT8 PayloadDigest[32];
    UINT32 RulesOffset;
    UINT32 AppIdsOffset;
    UINT32 AppIdsBytes;
    UINT32 Reserved1;
} FCX_STRICT_POLICY_HEADER;

typedef struct _FCX_STRICT_POLICY_RULE {
    UINT16 FamilyIndex;
    UINT8 MemberIndex;
    UINT8 Action;
    UINT16 TargetGroupIndex;
    UINT16 Reserved;
    UINT32 AppIdOffset;
    UINT32 AppIdBytes;
} FCX_STRICT_POLICY_RULE;

// Endpoint order is fixed: TCP v4, TCP v6, UDP v4, UDP v6. Ports use host
// byte order. IPv4 uses the first four address bytes and requires the rest zero.
typedef struct _FCX_STRICT_ENDPOINT {
    UINT8 Address[16];
    UINT16 Port;
    UINT16 Reserved;
} FCX_STRICT_ENDPOINT;

typedef struct _FCX_STRICT_ENDPOINT_LEASE {
    UINT32 Magic;
    UINT16 Protocol;
    UINT16 LeaseBytes;
    UINT32 TtlMillis;
    UINT32 Reserved0;
    UINT64 Revision;
    UINT8 PolicyDigest[32];
    UINT8 Nonce[16];
    FCX_STRICT_ENDPOINT TcpV4;
    FCX_STRICT_ENDPOINT TcpV6;
    FCX_STRICT_ENDPOINT UdpV4;
    FCX_STRICT_ENDPOINT UdpV6;
    UINT8 Reserved1[8];
} FCX_STRICT_ENDPOINT_LEASE;

// The callout owns this WFP redirect context. Addresses are network-order
// bytes; RemotePort and all other multibyte fields use host little-endian.
typedef struct _FCX_STRICT_REDIRECT_CONTEXT {
    UINT32 Magic;
    UINT16 Protocol;
    UINT16 ContextBytes;
    UINT64 LeaseGeneration;
    UINT64 Revision;
    UINT8 PolicyDigest[32];
    UINT8 LeaseNonce[16];
    UINT16 TargetGroupIndex;
    UINT8 AddressFamily;
    UINT8 IpProtocol;
    UINT16 RemotePort;
    UINT16 Reserved0;
    UINT8 RemoteAddress[16];
    UINT8 Reserved1[16];
} FCX_STRICT_REDIRECT_CONTEXT;

typedef struct _FCX_STRICT_DRIVER_SNAPSHOT {
    UINT32 Magic;
    UINT16 Protocol;
    UINT16 SnapshotBytes;
    UINT32 Flags;
    UINT32 RuleCount;
    UINT64 Generation;
    UINT64 Revision;
    UINT8 PolicyDigest[32];
    UINT64 Capabilities;
    UINT8 DriverBuildId[16];
    UINT64 LeaseGeneration;
    UINT32 LeaseRemainingMillis;
    UINT32 Reserved0;
    UINT8 LeaseNonce[16];
    UINT64 DatagramInjectionAttempts;
    UINT64 DatagramInjectionSucceeded;
    UINT64 DatagramInjectionFailed;
    UINT64 DatagramPartialBatchFailures;
    UINT32 DatagramInjectionInFlight;
    UINT32 DatagramLastFailureStatus;
    UINT8 Reserved[8];
} FCX_STRICT_DRIVER_SNAPSHOT;

// Batch and record integers are little-endian. Address bytes are in network
// order. Each RecordBytes value is an 8-byte aligned span containing its fixed
// header, PayloadBytes bytes and zero padding. The batch and every record are
// bound to one live endpoint lease before any datagram may cross the device.
typedef struct _FCX_STRICT_DATAGRAM_BATCH_HEADER {
    UINT32 Magic;
    UINT16 Protocol;
    UINT16 HeaderBytes;
    UINT8 Kind;
    UINT8 Reserved0[3];
    UINT32 TotalBytes;
    UINT32 RecordCount;
    UINT32 Reserved1;
    UINT64 LeaseGeneration;
    UINT64 Revision;
    UINT8 PolicyDigest[32];
    UINT8 LeaseNonce[16];
    UINT8 Reserved2[8];
} FCX_STRICT_DATAGRAM_BATCH_HEADER;

typedef struct _FCX_STRICT_DATAGRAM_RECORD_HEADER {
    UINT32 RecordBytes;
    UINT32 PayloadBytes;
    UINT64 FlowToken;
    UINT64 Sequence;
    UINT16 TargetGroupIndex;
    UINT8 AddressFamily;
    UINT8 IpProtocol;
    UINT32 Flags;
    UINT16 LocalPort;
    UINT16 RemotePort;
    UINT8 LocalAddress[16];
    UINT8 RemoteAddress[16];
    UINT8 Reserved[12];
} FCX_STRICT_DATAGRAM_RECORD_HEADER;

#pragma pack(pop)

C_ASSERT(sizeof(FCX_STRICT_POLICY_HEADER) == FCX_STRICT_POLICY_HEADER_BYTES);
C_ASSERT(sizeof(FCX_STRICT_POLICY_RULE) == FCX_STRICT_POLICY_RULE_BYTES);
C_ASSERT(sizeof(FCX_STRICT_ENDPOINT) == FCX_STRICT_ENDPOINT_BYTES);
C_ASSERT(sizeof(FCX_STRICT_ENDPOINT_LEASE) == FCX_STRICT_ENDPOINT_LEASE_BYTES);
C_ASSERT(sizeof(FCX_STRICT_REDIRECT_CONTEXT) == FCX_STRICT_REDIRECT_CONTEXT_BYTES);
C_ASSERT(sizeof(FCX_STRICT_DRIVER_SNAPSHOT) == FCX_STRICT_SNAPSHOT_BYTES);
C_ASSERT(sizeof(FCX_STRICT_DATAGRAM_BATCH_HEADER) ==
         FCX_STRICT_DATAGRAM_BATCH_HEADER_BYTES);
C_ASSERT(sizeof(FCX_STRICT_DATAGRAM_RECORD_HEADER) ==
         FCX_STRICT_DATAGRAM_RECORD_HEADER_BYTES);
