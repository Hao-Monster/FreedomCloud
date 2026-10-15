// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../node_catalog.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$CatalogNodeImpl _$$CatalogNodeImplFromJson(Map<String, dynamic> json) =>
    _$CatalogNodeImpl(
      identityKey: json['identityKey'] as String,
      endpointKey: json['endpointKey'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      source: $enumDecode(_$CatalogNodeSourceEnumMap, json['source']),
      providerName: json['providerName'] as String?,
      coreIndex: (json['coreIndex'] as num?)?.toInt(),
      selectGroups: (json['selectGroups'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      unsupported: $enumDecodeNullable(
              _$CatalogUnsupportedReasonEnumMap, json['unsupported']) ??
          CatalogUnsupportedReason.none,
    );

Map<String, dynamic> _$$CatalogNodeImplToJson(_$CatalogNodeImpl instance) =>
    <String, dynamic>{
      'identityKey': instance.identityKey,
      'endpointKey': instance.endpointKey,
      'name': instance.name,
      'type': instance.type,
      'source': _$CatalogNodeSourceEnumMap[instance.source]!,
      'providerName': instance.providerName,
      'coreIndex': instance.coreIndex,
      'selectGroups': instance.selectGroups,
      'unsupported': _$CatalogUnsupportedReasonEnumMap[instance.unsupported]!,
    };

const _$CatalogNodeSourceEnumMap = {
  CatalogNodeSource.inline: 'inline',
  CatalogNodeSource.provider: 'provider',
};

const _$CatalogUnsupportedReasonEnumMap = {
  CatalogUnsupportedReason.none: 'none',
  CatalogUnsupportedReason.chainUnsupported: 'chainUnsupported',
  CatalogUnsupportedReason.typeUnsupported: 'typeUnsupported',
  CatalogUnsupportedReason.parseFailed: 'parseFailed',
  CatalogUnsupportedReason.providerNotCached: 'providerNotCached',
  CatalogUnsupportedReason.strictModeUnsupported: 'strictModeUnsupported',
};

_$ProfileCatalogImpl _$$ProfileCatalogImplFromJson(Map<String, dynamic> json) =>
    _$ProfileCatalogImpl(
      profileId: json['profileId'] as String,
      fingerprint: json['fingerprint'] as String,
      status: $enumDecode(_$ProfileCatalogStatusEnumMap, json['status']),
      nodes: (json['nodes'] as List<dynamic>?)
              ?.map((e) => CatalogNode.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <CatalogNode>[],
      providerNodeCounts:
          (json['providerNodeCounts'] as Map<String, dynamic>?)?.map(
                (k, e) => MapEntry(k, (e as num).toInt()),
              ) ??
              const <String, int>{},
      errorSummary: json['errorSummary'] as String?,
      coreCatalogId: json['coreCatalogId'] as String?,
    );

Map<String, dynamic> _$$ProfileCatalogImplToJson(
        _$ProfileCatalogImpl instance) =>
    <String, dynamic>{
      'profileId': instance.profileId,
      'fingerprint': instance.fingerprint,
      'status': _$ProfileCatalogStatusEnumMap[instance.status]!,
      'nodes': instance.nodes.map((e) => e.toJson()).toList(),
      'providerNodeCounts': instance.providerNodeCounts,
      'errorSummary': instance.errorSummary,
      'coreCatalogId': instance.coreCatalogId,
    };

const _$ProfileCatalogStatusEnumMap = {
  ProfileCatalogStatus.ready: 'ready',
  ProfileCatalogStatus.loading: 'loading',
  ProfileCatalogStatus.fileMissing: 'fileMissing',
  ProfileCatalogStatus.parseFailed: 'parseFailed',
  ProfileCatalogStatus.updating: 'updating',
};
