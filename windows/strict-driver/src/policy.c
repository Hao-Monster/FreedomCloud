#include "policy.h"

#include <bcrypt.h>
#include <ntintsafe.h>

static
UINT64
FcxHashAppId(
    _In_reads_bytes_(AppIdBytes) const UINT8 *AppId,
    _In_ UINT32 AppIdBytes
    )
{
    UINT64 hash = 14695981039346656037ull;
    UINT32 index;

    for (index = 0; index < AppIdBytes; ++index) {
        hash ^= AppId[index];
        hash *= 1099511628211ull;
    }
    return hash;
}

static
BOOLEAN
FcxBufferIsZero(
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
INT32
FcxCompareAppIds(
    _In_reads_bytes_(LeftBytes) const UINT8 *Left,
    _In_ UINT32 LeftBytes,
    _In_reads_bytes_(RightBytes) const UINT8 *Right,
    _In_ UINT32 RightBytes
    )
{
    UINT32 index;
    UINT32 common = min(LeftBytes, RightBytes);

    for (index = 0; index < common; ++index) {
        if (Left[index] < Right[index]) {
            return -1;
        }
        if (Left[index] > Right[index]) {
            return 1;
        }
    }
    if (LeftBytes < RightBytes) {
        return -1;
    }
    return LeftBytes > RightBytes ? 1 : 0;
}

static
NTSTATUS
FcxValidateWireHeader(
    _In_ const FCX_STRICT_POLICY_HEADER *Header,
    _In_ UINT32 InputBytes,
    _Out_ UINT32 *InternalRuleBytes,
    _Out_ UINT32 *BucketCount,
    _Out_ UINT32 *AllocationBytes
    )
{
    NTSTATUS status;
    UINT32 wireRuleBytes;
    UINT32 expectedAppIdsOffset;
    UINT32 doubledRules;
    UINT32 bucketBytes;
    UINT32 dataBytes;
    UINT32 allocation;
    UINT32 buckets = 1;

    if (Header->Magic != FCX_STRICT_WIRE_MAGIC ||
        Header->Protocol != FCX_STRICT_WIRE_PROTOCOL ||
        Header->HeaderBytes != FCX_STRICT_POLICY_HEADER_BYTES ||
        Header->TotalBytes != InputBytes ||
        InputBytes < FCX_STRICT_POLICY_HEADER_BYTES ||
        InputBytes > FCX_STRICT_MAX_POLICY_BYTES ||
        Header->RuleCount == 0 ||
        Header->RuleCount > FCX_STRICT_MAX_RULES ||
        Header->TargetGroupCount > 128 ||
        Header->Revision == 0 ||
        Header->Reserved0 != 0 ||
        Header->Reserved1 != 0 ||
        Header->RulesOffset != FCX_STRICT_POLICY_HEADER_BYTES ||
        FcxBufferIsZero(Header->PolicyDigest, sizeof(Header->PolicyDigest))) {
        return STATUS_INVALID_PARAMETER;
    }

    status = RtlUInt32Mult(Header->RuleCount,
                           FCX_STRICT_POLICY_RULE_BYTES,
                           &wireRuleBytes);
    if (!NT_SUCCESS(status)) {
        return STATUS_INTEGER_OVERFLOW;
    }
    status = RtlUInt32Add(Header->RulesOffset,
                          wireRuleBytes,
                          &expectedAppIdsOffset);
    if (!NT_SUCCESS(status) ||
        Header->AppIdsOffset != expectedAppIdsOffset ||
        Header->AppIdsOffset > InputBytes ||
        Header->AppIdsBytes != InputBytes - Header->AppIdsOffset) {
        return STATUS_INVALID_PARAMETER;
    }

    status = RtlUInt32Mult(Header->RuleCount, 2, &doubledRules);
    if (!NT_SUCCESS(status)) {
        return STATUS_INTEGER_OVERFLOW;
    }
    while (buckets < doubledRules) {
        if (buckets > (MAXULONG >> 1)) {
            return STATUS_INTEGER_OVERFLOW;
        }
        buckets <<= 1;
    }
    status = RtlUInt32Mult(Header->RuleCount,
                           (UINT32)sizeof(FCX_STRICT_RULE_RECORD),
                           InternalRuleBytes);
    if (!NT_SUCCESS(status)) {
        return STATUS_INTEGER_OVERFLOW;
    }
    status = RtlUInt32Mult(buckets, (UINT32)sizeof(UINT32), &bucketBytes);
    if (!NT_SUCCESS(status)) {
        return STATUS_INTEGER_OVERFLOW;
    }
    status = RtlUInt32Add(*InternalRuleBytes, bucketBytes, &dataBytes);
    if (!NT_SUCCESS(status)) {
        return STATUS_INTEGER_OVERFLOW;
    }
    status = RtlUInt32Add(dataBytes, Header->AppIdsBytes, &dataBytes);
    if (!NT_SUCCESS(status)) {
        return STATUS_INTEGER_OVERFLOW;
    }
    status = RtlUInt32Add(
        (UINT32)FIELD_OFFSET(FCX_STRICT_POLICY_SNAPSHOT, Data),
        dataBytes,
        &allocation);
    if (!NT_SUCCESS(status)) {
        return STATUS_INTEGER_OVERFLOW;
    }

    *BucketCount = buckets;
    *AllocationBytes = allocation;
    return STATUS_SUCCESS;
}

static
NTSTATUS
FcxValidatePayloadDigest(
    _In_reads_bytes_(InputBytes) const UINT8 *Input,
    _In_ UINT32 InputBytes,
    _In_ const FCX_STRICT_POLICY_HEADER *Header
    )
{
    NTSTATUS status;
    UINT8 digest[32];

    status = BCryptHash(BCRYPT_SHA256_ALG_HANDLE,
                        NULL,
                        0,
                        (PUCHAR)(Input + Header->RulesOffset),
                        InputBytes - Header->RulesOffset,
                        digest,
                        sizeof(digest));
    if (!NT_SUCCESS(status)) {
        return status;
    }
    if (RtlCompareMemory(digest, Header->PayloadDigest, sizeof(digest)) != sizeof(digest)) {
        RtlSecureZeroMemory(digest, sizeof(digest));
        return STATUS_DATA_ERROR;
    }
    RtlSecureZeroMemory(digest, sizeof(digest));
    return STATUS_SUCCESS;
}

_Must_inspect_result_
NTSTATUS
FcxStrictPolicyBuild(
    _In_reads_bytes_(InputBytes) const VOID *Input,
    _In_ UINT32 InputBytes,
    _Outptr_ FCX_STRICT_POLICY_SNAPSHOT **Snapshot
    )
{
    NTSTATUS status;
    FCX_STRICT_POLICY_HEADER header;
    FCX_STRICT_POLICY_SNAPSHOT *snapshot = NULL;
    UINT32 internalRuleBytes;
    UINT32 bucketCount;
    UINT32 allocationBytes;
    UINT32 index;
    UINT32 appCursor = 0;
    UINT8 pairSeen[(FCX_STRICT_MAX_RULES + 7) / 8];
    UINT8 familyAction[128];
    UINT16 familyTarget[128];
    const UINT8 *wire;
    const UINT8 *wireRules;
    const UINT8 *wireAppIds;

    if (Snapshot == NULL) {
        return STATUS_INVALID_PARAMETER;
    }
    *Snapshot = NULL;
    if (Input == NULL || InputBytes < sizeof(header)) {
        return STATUS_INVALID_PARAMETER;
    }

    wire = (const UINT8 *)Input;
    RtlCopyMemory(&header, wire, sizeof(header));
    status = FcxValidateWireHeader(&header,
                                   InputBytes,
                                   &internalRuleBytes,
                                   &bucketCount,
                                   &allocationBytes);
    if (!NT_SUCCESS(status)) {
        return status;
    }
    status = FcxValidatePayloadDigest(wire, InputBytes, &header);
    if (!NT_SUCCESS(status)) {
        return status;
    }

    snapshot = (FCX_STRICT_POLICY_SNAPSHOT *)ExAllocatePool2(
        POOL_FLAG_NON_PAGED,
        allocationBytes,
        FCX_STRICT_POOL_TAG);
    if (snapshot == NULL) {
        return STATUS_INSUFFICIENT_RESOURCES;
    }
    RtlZeroMemory(snapshot, allocationBytes);
    snapshot->AllocationBytes = allocationBytes;
    snapshot->RuleCount = header.RuleCount;
    snapshot->BucketCount = bucketCount;
    snapshot->AppIdsBytes = header.AppIdsBytes;
    snapshot->TargetGroupCount = header.TargetGroupCount;
    snapshot->Revision = header.Revision;
    RtlCopyMemory(snapshot->PolicyDigest,
                  header.PolicyDigest,
                  sizeof(snapshot->PolicyDigest));
    snapshot->Rules = (FCX_STRICT_RULE_RECORD *)snapshot->Data;
    snapshot->Buckets = (UINT32 *)(snapshot->Data + internalRuleBytes);
    snapshot->AppIds = (UINT8 *)snapshot->Buckets +
                       (bucketCount * sizeof(UINT32));
    RtlFillMemory(snapshot->Buckets,
                  bucketCount * sizeof(UINT32),
                  0xff);

    RtlZeroMemory(pairSeen, sizeof(pairSeen));
    RtlFillMemory(familyAction, sizeof(familyAction), 0xff);
    RtlFillMemory(familyTarget, sizeof(familyTarget), 0xff);
    wireRules = wire + header.RulesOffset;
    wireAppIds = wire + header.AppIdsOffset;

    for (index = 0; index < header.RuleCount; ++index) {
        FCX_STRICT_POLICY_RULE rule;
        FCX_STRICT_RULE_RECORD *record = &snapshot->Rules[index];
        UINT32 pairIndex;
        UINT32 pairByte;
        UINT8 pairMask;
        UINT32 appEnd;
        UINT32 bucket;
        const UINT8 *appId;

        RtlCopyMemory(&rule,
                      wireRules + (index * FCX_STRICT_POLICY_RULE_BYTES),
                      sizeof(rule));
        status = RtlUInt32Add(rule.AppIdOffset, rule.AppIdBytes, &appEnd);
        if (!NT_SUCCESS(status) ||
            rule.Reserved != 0 ||
            rule.FamilyIndex >= 128 ||
            rule.MemberIndex > 32 ||
            rule.AppIdOffset != appCursor ||
            rule.AppIdBytes == 0 ||
            rule.AppIdBytes > FCX_STRICT_MAX_APP_ID_BYTES ||
            appEnd > header.AppIdsBytes ||
            (rule.Action != FCX_STRICT_ACTION_PROXY &&
             rule.Action != FCX_STRICT_ACTION_BLOCK) ||
            (rule.Action == FCX_STRICT_ACTION_PROXY &&
             rule.TargetGroupIndex >= header.TargetGroupCount) ||
            (rule.Action == FCX_STRICT_ACTION_BLOCK &&
             rule.TargetGroupIndex != FCX_STRICT_NO_TARGET_GROUP)) {
            status = STATUS_INVALID_PARAMETER;
            goto Failure;
        }

        pairIndex = (rule.FamilyIndex * 33u) + rule.MemberIndex;
        pairByte = pairIndex >> 3;
        pairMask = (UINT8)(1u << (pairIndex & 7u));
        if ((pairSeen[pairByte] & pairMask) != 0) {
            status = STATUS_DUPLICATE_OBJECTID;
            goto Failure;
        }
        pairSeen[pairByte] |= pairMask;

        if (familyAction[rule.FamilyIndex] == 0xff) {
            familyAction[rule.FamilyIndex] = rule.Action;
            familyTarget[rule.FamilyIndex] = rule.TargetGroupIndex;
        } else if (familyAction[rule.FamilyIndex] != rule.Action ||
                   familyTarget[rule.FamilyIndex] != rule.TargetGroupIndex) {
            status = STATUS_INVALID_PARAMETER;
            goto Failure;
        }

        appId = wireAppIds + rule.AppIdOffset;
        if (index != 0) {
            const FCX_STRICT_RULE_RECORD *previous = &snapshot->Rules[index - 1];
            const UINT8 *previousAppId = snapshot->AppIds + previous->AppIdOffset;
            if (FcxCompareAppIds(previousAppId,
                                 previous->AppIdBytes,
                                 appId,
                                 rule.AppIdBytes) >= 0) {
                status = STATUS_DUPLICATE_OBJECTID;
                goto Failure;
            }
        }

        RtlCopyMemory(snapshot->AppIds + appCursor, appId, rule.AppIdBytes);
        record->AppIdHash = FcxHashAppId(appId, rule.AppIdBytes);
        record->AppIdOffset = appCursor;
        record->AppIdBytes = rule.AppIdBytes;
        record->FamilyIndex = rule.FamilyIndex;
        record->MemberIndex = rule.MemberIndex;
        record->Action = rule.Action;
        record->TargetGroupIndex = rule.TargetGroupIndex;
        bucket = (UINT32)(record->AppIdHash & (bucketCount - 1u));
        record->NextIndex = snapshot->Buckets[bucket];
        snapshot->Buckets[bucket] = index;
        appCursor = appEnd;
    }
    if (appCursor != header.AppIdsBytes) {
        status = STATUS_INVALID_PARAMETER;
        goto Failure;
    }

    *Snapshot = snapshot;
    return STATUS_SUCCESS;

Failure:
    FcxStrictPolicyDestroy(snapshot);
    return status;
}

VOID
FcxStrictPolicyDestroy(
    _Pre_opt_valid_ _Frees_ptr_opt_ FCX_STRICT_POLICY_SNAPSHOT *Snapshot
    )
{
    if (Snapshot != NULL) {
        const UINT32 snapshotHeaderBytes =
            (UINT32)FIELD_OFFSET(FCX_STRICT_POLICY_SNAPSHOT, Data);
        UINT32 bytes = Snapshot->AllocationBytes;
        if (bytes >= snapshotHeaderBytes &&
            bytes <= FCX_STRICT_MAX_POLICY_BYTES +
                     snapshotHeaderBytes +
                     (FCX_STRICT_MAX_RULES * sizeof(FCX_STRICT_RULE_RECORD)) +
                     (16384u * sizeof(UINT32))) {
            RtlSecureZeroMemory(Snapshot, bytes);
        }
        ExFreePoolWithTag(Snapshot, FCX_STRICT_POOL_TAG);
    }
}

_Must_inspect_result_
const FCX_STRICT_RULE_RECORD *
FcxStrictPolicyFind(
    _In_ const FCX_STRICT_POLICY_SNAPSHOT *Snapshot,
    _In_reads_bytes_(AppIdBytes) const UINT8 *AppId,
    _In_ UINT32 AppIdBytes
    )
{
    UINT64 hash;
    UINT32 index;
    UINT32 traversed = 0;

    if (Snapshot == NULL || AppId == NULL || AppIdBytes == 0 ||
        AppIdBytes > FCX_STRICT_MAX_APP_ID_BYTES ||
        Snapshot->BucketCount == 0 ||
        (Snapshot->BucketCount & (Snapshot->BucketCount - 1u)) != 0) {
        return NULL;
    }

    hash = FcxHashAppId(AppId, AppIdBytes);
    index = Snapshot->Buckets[(UINT32)(hash & (Snapshot->BucketCount - 1u))];
    while (index != FCX_STRICT_INVALID_INDEX && traversed < Snapshot->RuleCount) {
        const FCX_STRICT_RULE_RECORD *record;

        if (index >= Snapshot->RuleCount) {
            return NULL;
        }
        record = &Snapshot->Rules[index];
        if (record->AppIdHash == hash &&
            record->AppIdBytes == AppIdBytes &&
            record->AppIdOffset <= Snapshot->AppIdsBytes &&
            record->AppIdBytes <= Snapshot->AppIdsBytes - record->AppIdOffset &&
            RtlCompareMemory(Snapshot->AppIds + record->AppIdOffset,
                             AppId,
                             AppIdBytes) == AppIdBytes) {
            return record;
        }
        index = record->NextIndex;
        ++traversed;
    }
    return NULL;
}
