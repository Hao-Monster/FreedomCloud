#pragma once

#include <ntddk.h>

#include "../include/flclash_strict_wire.h"

#define FCX_STRICT_POOL_TAG 'PCXF'
#define FCX_STRICT_INVALID_INDEX MAXULONG

typedef struct _FCX_STRICT_RULE_RECORD {
    UINT64 AppIdHash;
    UINT32 NextIndex;
    UINT32 AppIdOffset;
    UINT32 AppIdBytes;
    UINT16 FamilyIndex;
    UINT16 TargetGroupIndex;
    UINT8 MemberIndex;
    UINT8 Action;
    UINT16 Reserved;
} FCX_STRICT_RULE_RECORD;

typedef struct _FCX_STRICT_POLICY_SNAPSHOT {
    UINT32 AllocationBytes;
    UINT32 RuleCount;
    UINT32 BucketCount;
    UINT32 AppIdsBytes;
    UINT32 TargetGroupCount;
    UINT32 Reserved;
    UINT64 Revision;
    UINT8 PolicyDigest[32];
    FCX_STRICT_RULE_RECORD *Rules;
    UINT32 *Buckets;
    UINT8 *AppIds;
    UINT8 Data[ANYSIZE_ARRAY];
} FCX_STRICT_POLICY_SNAPSHOT;

_Must_inspect_result_
NTSTATUS
FcxStrictPolicyBuild(
    _In_reads_bytes_(InputBytes) const VOID *Input,
    _In_ UINT32 InputBytes,
    _Outptr_ FCX_STRICT_POLICY_SNAPSHOT **Snapshot
    );

VOID
FcxStrictPolicyDestroy(
    _Pre_opt_valid_ _Frees_ptr_opt_ FCX_STRICT_POLICY_SNAPSHOT *Snapshot
    );

_Must_inspect_result_
const FCX_STRICT_RULE_RECORD *
FcxStrictPolicyFind(
    _In_ const FCX_STRICT_POLICY_SNAPSHOT *Snapshot,
    _In_reads_bytes_(AppIdBytes) const UINT8 *AppId,
    _In_ UINT32 AppIdBytes
    );
