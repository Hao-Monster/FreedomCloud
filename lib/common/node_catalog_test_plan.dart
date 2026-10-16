import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/models/node_catalog.dart';

/// Only fixed reason codes and safe source names belong in a batch summary.
class CatalogProviderIssue {
  const CatalogProviderIssue(
      {required this.reason, this.providerName, this.count = 0});

  final String reason;
  final String? providerName;
  final int count;
}

/// A short-lived plan. The preparation closure privately owns raw credentials;
/// callers see projections only and must dispose the plan in their finally path.
class CatalogTestPlan {
  CatalogTestPlan({
    required List<CatalogNode> nodes,
    required List<CatalogProviderIssue> providerIssues,
    required this.chunkCount,
    required Future<ProfileCatalog> Function(int) prepare,
    required void Function() onDispose,
  })  : nodes = List.unmodifiable(nodes),
        providerIssues = List.unmodifiable(providerIssues),
        _prepare = prepare,
        _onDispose = onDispose;

  final List<CatalogNode> nodes;
  final List<CatalogProviderIssue> providerIssues;
  final int chunkCount;
  final Future<ProfileCatalog> Function(int) _prepare;
  final void Function() _onDispose;
  bool _disposed = false;

  Future<ProfileCatalog> prepareChunk(int index) {
    if (_disposed)
      return Future.error(const CatalogBuildException('cancelled'));
    if (index < 0 || index >= chunkCount) {
      return Future.error(const CatalogBuildException('invalidParameters'));
    }
    return _prepare(index);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _onDispose();
  }
}
