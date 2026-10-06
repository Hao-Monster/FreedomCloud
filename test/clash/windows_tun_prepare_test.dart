import 'package:flclashx/common/tun_runtime.dart';
import 'package:flclashx/common/windows_tun_prepare.dart';
import 'package:flutter_test/flutter_test.dart';

TunStatus status(String privilege) => TunStatus(
    instanceId: 'core',
    revision: 1,
    state: 'off',
    listenerActive: false,
    interfaceState: 'missing',
    privilege: privilege,
    requestedEnabled: false);

void main() {
  test('legacy Agent rejects before authorization or stopping old backend',
      () async {
    var effects = 0;
    await expectLater(
        prepareWindowsTunBackend(
          observe: () async => status('unprivileged'),
          componentsMatch: () async => false,
          canMigrate: () => false,
          authorize: () async {
            effects++;
            return true;
          },
          ensureBackend: () async {
            effects++;
            return true;
          },
          initialize: () async {
            effects++;
          },
          isCurrent: () => true,
        ),
        throwsA(
            isA<TunFailure>().having((e) => e.code, 'code', 'legacyAgent')));
    expect(effects, 0);
  });
  test('healthy Helper with local Core still migrates before enabling',
      () async {
    final calls = <String>[];
    var elevated = false;
    final changed = await prepareWindowsTunBackend(
      observe: () async => status(elevated ? 'elevated' : 'unprivileged'),
      componentsMatch: () async => true,
      canMigrate: () => true,
      authorize: () async {
        calls.add('authorize-none');
        return true;
      },
      ensureBackend: () async {
        calls.add('migrate');
        elevated = true;
        return true;
      },
      initialize: () async {
        calls.add('initialize');
      },
      isCurrent: () => true,
    );
    expect(changed, isTrue);
    expect(calls, ['authorize-none', 'migrate', 'initialize']);
  });
  test('matching elevated Core needs no authorization or restart', () async {
    var effects = 0;
    expect(
        await prepareWindowsTunBackend(
          observe: () async => status('elevated'),
          componentsMatch: () async => true,
          canMigrate: () => true,
          authorize: () async {
            effects++;
            return true;
          },
          ensureBackend: () async {
            effects++;
            return true;
          },
          initialize: () async {
            effects++;
          },
          isCurrent: () => true,
        ),
        isFalse);
    expect(effects, 0);
  });
  test('authorization denied never migrates or initializes', () async {
    var effects = 0;
    await expectLater(
        prepareWindowsTunBackend(
          observe: () async => status('unprivileged'),
          componentsMatch: () async => true,
          canMigrate: () => true,
          authorize: () async => false,
          ensureBackend: () async {
            effects++;
            return true;
          },
          initialize: () async {
            effects++;
          },
          isCurrent: () => true,
        ),
        throwsA(isA<TunFailure>()));
    expect(effects, 0);
  });
  test('superseded user request never starts backend migration', () async {
    var current = true;
    var effects = 0;
    await prepareWindowsTunBackend(
      observe: () async => status('unprivileged'),
      componentsMatch: () async => true,
      canMigrate: () => true,
      authorize: () async {
        current = false;
        return true;
      },
      ensureBackend: () async {
        effects++;
        return true;
      },
      initialize: () async {
        effects++;
      },
      isCurrent: () => current,
    );
    expect(effects, 0);
  });
  test('successful authorization without elevated Core is failure', () async {
    await expectLater(
        prepareWindowsTunBackend(
          observe: () async => status('unprivileged'),
          componentsMatch: () async => true,
          canMigrate: () => true,
          authorize: () async => true,
          ensureBackend: () async => false,
          initialize: () async {},
          isCurrent: () => true,
        ),
        throwsA(isA<TunFailure>()));
  });
}
