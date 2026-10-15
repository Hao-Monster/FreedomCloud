import 'package:flclashx/clash/core.dart';
import 'package:flclashx/common/node_catalog_service.dart';
import 'package:flclashx/providers/node_overview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('passive runtime and source reads cannot initialize the Core service',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(ClashCore.existingInterface, isNull);
    await expectLater(container.read(nodeRuntimeReaderProvider)(),
        throwsA(isA<CatalogBuildException>()));
    expect(
        () => container
            .read(nodeCatalogServiceFactoryProvider)()
            .readProfileConfig('synthetic'),
        throwsA(isA<CatalogBuildException>()));
    expect(ClashCore.existingInterface, isNull);
  });
}
