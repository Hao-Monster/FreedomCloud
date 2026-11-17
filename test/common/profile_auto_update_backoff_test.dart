import 'package:flclashx/controller.dart';
import 'package:flclashx/models/models.dart';
import 'package:flclashx/providers/providers.dart';
import 'package:flclashx/state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingAutoUpdateController extends AppController {
  _RecordingAutoUpdateController(super.context, super.ref);

  final List<String> updatedProfileIds = <String>[];
  final Set<String> failingProfileIds = <String>{};
  DateTime simulatedNow = DateTime.utc(2026, 11, 11, 10, 0, 0);

  @override
  Future<void> updateProfile(Profile profile) async {
    updatedProfileIds.add(profile.id);
    if (failingProfileIds.contains(profile.id)) {
      throw StateError('HTTP 403 Forbidden for ${profile.id}');
    }
    final container = ProviderScope.containerOf(context, listen: false);
    final latest = container.read(profilesProvider).getProfile(profile.id);
    if (latest != null) {
      container.read(profilesProvider.notifier).setProfile(
            latest.copyWith(
              lastUpdateDate: simulatedNow,
              isUpdating: false,
            ),
          );
    }
  }
}

void main() {
  group('ProfileAutoUpdateBackoff', () {
    test(
      'escalates 40m -> 2h -> 6h -> 12h and invalidates on URL edit, lastUpdateDate advance, or clear',
      () {
        final backoff = ProfileAutoUpdateBackoff();
        final t0 = DateTime.utc(2026, 11, 11, 10, 0, 0);
        final profile = Profile(
          id: 'dead-1',
          url: 'https://sub.example.com/expired',
          autoUpdate: true,
          autoUpdateDuration: const Duration(hours: 6),
          lastUpdateDate: t0.subtract(const Duration(hours: 12)),
        );

        expect(backoff.canAttempt(profile, now: t0), isTrue);

        // Failure 1 -> 40 minutes
        expect(
          backoff.recordFailure(profile, now: t0),
          equals(const Duration(minutes: 40)),
        );
        expect(
          backoff.canAttempt(profile, now: t0.add(const Duration(minutes: 20))),
          isFalse,
        );
        expect(
          backoff.canAttempt(profile, now: t0.add(const Duration(minutes: 40))),
          isTrue,
        );

        // Failure 2 -> 2 hours
        final t1 = t0.add(const Duration(minutes: 40));
        expect(
          backoff.recordFailure(profile, now: t1),
          equals(const Duration(hours: 2)),
        );
        expect(
          backoff.canAttempt(profile, now: t1.add(const Duration(minutes: 119))),
          isFalse,
        );
        expect(
          backoff.canAttempt(profile, now: t1.add(const Duration(hours: 2))),
          isTrue,
        );

        // Failure 3 -> 6 hours
        final t2 = t1.add(const Duration(hours: 2));
        expect(
          backoff.recordFailure(profile, now: t2),
          equals(const Duration(hours: 6)),
        );

        // Failure 4 & 5 -> capped at 12 hours
        final t3 = t2.add(const Duration(hours: 6));
        expect(
          backoff.recordFailure(profile, now: t3),
          equals(const Duration(hours: 12)),
        );
        final t4 = t3.add(const Duration(hours: 12));
        expect(
          backoff.recordFailure(profile, now: t4),
          equals(const Duration(hours: 12)),
        );

        // Advancing lastUpdateDate (e.g. gift-card redemption sync on same URL) invalidates immediately.
        final renewedSameUrl = profile.copyWith(
          lastUpdateDate: t4.add(const Duration(minutes: 5)),
        );
        expect(
          backoff.canAttempt(
            renewedSameUrl,
            now: t4.add(const Duration(minutes: 10)),
          ),
          isTrue,
        );

        // Re-record failure, then verify URL rotation invalidates immediately and resets schedule to 40m.
        backoff.recordFailure(profile, now: t4);
        final rotatedUrl = profile.copyWith(url: 'https://sub.example.com/new');
        expect(
          backoff.canAttempt(
            rotatedUrl,
            now: t4.add(const Duration(minutes: 1)),
          ),
          isTrue,
        );
        expect(
          backoff.recordFailure(
            rotatedUrl,
            now: t4.add(const Duration(minutes: 1)),
          ),
          equals(const Duration(minutes: 40)),
        );

        // Explicit clear removes backoff entry immediately.
        backoff.clear(rotatedUrl.id);
        expect(
          backoff.canAttempt(
            rotatedUrl,
            now: t4.add(const Duration(minutes: 2)),
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'AppController.autoUpdateProfiles backs off failing background profiles without blocking healthy profiles, URL edits, or manual updates',
      (tester) async {
        final baseTime = DateTime.utc(2026, 11, 11, 10, 0, 0);
        final deadSecondary = Profile(
          id: 'dead-403',
          label: 'Dead Secondary',
          url: 'https://sub.example.com/expired',
          autoUpdate: true,
          autoUpdateDuration: const Duration(hours: 6),
          lastUpdateDate: baseTime.subtract(const Duration(hours: 12)),
        );
        final healthyCurrent = Profile(
          id: 'healthy-current',
          label: 'Healthy Current',
          url: 'https://sub.example.com/healthy',
          autoUpdate: true,
          autoUpdateDuration: const Duration(hours: 6),
          lastUpdateDate: baseTime.subtract(const Duration(hours: 12)),
        );

        globalState.config = Config(
          themeProps: defaultThemeProps,
          profiles: [deadSecondary, healthyCurrent],
          currentProfileId: healthyCurrent.id,
        );

        _RecordingAutoUpdateController? controller;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  controller ??= _RecordingAutoUpdateController(context, ref);
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        );

        controller!
          ..simulatedNow = baseTime
          ..failingProfileIds.add('dead-403');

        // Tick 1 (t0): both due profiles are attempted; dead-403 fails and preserves its original lastUpdateDate.
        await controller!.autoUpdateProfiles(now: baseTime);
        expect(
          controller!.updatedProfileIds,
          equals(['healthy-current', 'dead-403']),
        );
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SizedBox)),
        );
        expect(
          container
              .read(profilesProvider)
              .getProfile('dead-403')!
              .lastUpdateDate,
          equals(deadSecondary.lastUpdateDate),
          reason: 'Failed auto-update must never fabricate lastUpdateDate',
        );

        // Tick 2 (t0 + 20m, within initial 40m backoff): dead-403 must be skipped.
        controller!.updatedProfileIds.clear();
        await controller!.autoUpdateProfiles(
          now: baseTime.add(const Duration(minutes: 20)),
        );
        expect(
          controller!.updatedProfileIds,
          isEmpty,
          reason:
              'Failing background profile must be backed off on +20m timer tick',
        );

        // Tick 3 (t0 + 40m, initial backoff elapsed): dead-403 retries once and escalates to 2h backoff.
        await controller!.autoUpdateProfiles(
          now: baseTime.add(const Duration(minutes: 40)),
        );
        expect(controller!.updatedProfileIds, equals(['dead-403']));

        // Tick 4 (t0 + 60m, within 2h backoff): skipped again.
        controller!.updatedProfileIds.clear();
        await controller!.autoUpdateProfiles(
          now: baseTime.add(const Duration(minutes: 60)),
        );
        expect(controller!.updatedProfileIds, isEmpty);

        // Manual updateProfile is never blocked by auto-update backoff.
        await expectLater(
          controller!.updateProfile(deadSecondary),
          throwsA(isA<StateError>()),
        );
        expect(controller!.updatedProfileIds, equals(['dead-403']));

        // Editing the profile URL immediately invalidates stale backoff on the next autoUpdateProfiles tick.
        controller!.updatedProfileIds.clear();
        controller!.failingProfileIds.clear();
        controller!.simulatedNow = baseTime.add(const Duration(minutes: 61));
        container.read(profilesProvider.notifier).setProfile(
              deadSecondary.copyWith(url: 'https://sub.example.com/renewed'),
            );
        await controller!.autoUpdateProfiles(
          now: baseTime.add(const Duration(minutes: 61)),
        );
        expect(controller!.updatedProfileIds, equals(['dead-403']));
      },
    );
  });
}
