import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/providers/settings.dart';
import 'package:geolocator/geolocator.dart';
import 'package:homemaps/providers/location.dart';

import 'helpers/fake_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer container(FakeSource source) {
    final c = ProviderContainer(
      overrides: [locationSourceProvider.overrideWithBuild((_, _) => source)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'permission: waits for the first fix and remembers that it is on',
    () async {
      final source = FakeSource(PermissionAnswer.yes);
      final c = container(source);
      final wait = c.read(locationProvider.notifier).turnOn();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(locationProvider).status, LocationStatus.searching);
      source.fixes.add(fix(52.1));
      expect((await wait)?.point.latitude, 52.1);
      expect(c.read(locationProvider).status, LocationStatus.enabled);
      expect(c.read(settingsProvider).locationEnabled, isTrue);
      // A second tap doesn't ask again.
      await c.read(locationProvider.notifier).turnOn();
      expect(source.requested, 1);
    },
  );

  test('denied and never: no fix, and the reason in the state', () async {
    final source = FakeSource(PermissionAnswer.no);
    final c = container(source);
    expect(await c.read(locationProvider.notifier).turnOn(), isNull);
    expect(c.read(locationProvider).status, LocationStatus.denied);
    source.response = PermissionAnswer.never;
    expect(await c.read(locationProvider.notifier).turnOn(), isNull);
    expect(c.read(locationProvider).status, LocationStatus.permanentlyDenied);
    expect(c.read(settingsProvider).locationEnabled, isFalse);
  });

  test('turning off clears the fix and the setting', () async {
    final source = FakeSource(PermissionAnswer.yes);
    final c = container(source);
    final wait = c.read(locationProvider.notifier).turnOn();
    await Future<void>.delayed(Duration.zero);
    source.fixes.add(fix(52.1));
    await wait;
    c.read(locationProvider.notifier).turnOff();
    expect(c.read(locationProvider).fix, isNull);
    expect(c.read(settingsProvider).locationEnabled, isFalse);
  });

  test(
    'navigation restarts the stream, accurate and with a notification',
    () async {
      final source = FakeSource(PermissionAnswer.yes);
      final c = container(source);
      final wait = c.read(locationProvider.notifier).turnOn();
      await Future<void>.delayed(Duration.zero);
      source.fixes.add(fix(52.1));
      await wait;
      expect(source.lastAccurate, isFalse);
      c.read(locationProvider.notifier).navigation((
        title: 'Navigation',
        text: 'x',
      ));
      expect(source.lastAccurate, isTrue);
      expect(source.lastNotification?.title, 'Navigation');
    },
  );

  test(
    'no position fix: "not found", keep searching, and later simply on',
    () async {
      final source = FakeSource(PermissionAnswer.yes);
      final c = container(source);
      final wait = c.read(locationProvider.notifier).turnOn();
      await Future<void>.delayed(Duration.zero);
      source.fixes.addError(const PositionUpdateException('indoors'));
      expect(await wait, isNull);
      expect(c.read(locationProvider).status, LocationStatus.notFound);
      // The stream is still running: a fix simply turns it on.
      source.fixes.add(fix(52.1));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(locationProvider).status, LocationStatus.enabled);
    },
  );

  test('permission revoked en route: denied, and the stream stops', () async {
    final source = FakeSource(PermissionAnswer.yes);
    final c = container(source);
    final wait = c.read(locationProvider.notifier).turnOn();
    await Future<void>.delayed(Duration.zero);
    source.fixes.add(fix(52.1));
    await wait;
    source.fixes.addError(const PermissionDeniedException('gone'));
    await Future<void>.delayed(Duration.zero);
    expect(c.read(locationProvider).status, LocationStatus.denied);
    expect(source.fixes.hasListener, isFalse);
  });
}
