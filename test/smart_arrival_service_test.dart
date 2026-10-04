import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_platform_interface/geolocator_platform_interface.dart';
import 'package:attendus/Services/smart_arrival_service.dart';
import 'package:attendus/models/check_in_policy.dart';

class _LocationPlatform extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.whileInUse;
  bool enabled = true;
  int requests = 0;
  int samples = 0;
  double accuracy = 10;
  Duration age = Duration.zero;
  bool hold = false;
  bool cancelled = false;
  Completer<LocationPermission>? permissionResult;
  bool unsupportedPermissions = false;
  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<LocationPermission> checkPermission() async {
    if (unsupportedPermissions) throw UnsupportedError('Permissions API');
    return permissionResult?.future ?? permission;
  }

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permission;
  }

  @override
  Stream<Position> getPositionStream({
    LocationSettings? locationSettings,
  }) async* {
    samples++;
    expect(locationSettings?.accuracy, LocationAccuracy.high);
    expect(locationSettings?.timeLimit, const Duration(seconds: 10));
    if (hold) {
      final controller = StreamController<Position>(
        onCancel: () => cancelled = true,
      );
      yield* controller.stream;
      return;
    }
    yield Position(
      latitude: 40,
      longitude: -74,
      timestamp: DateTime.now().subtract(age),
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  @override
  Future<Position?> getLastKnownPosition({bool forceLocationManager = false}) =>
      throw StateError('Attendance must not use cached locations');
}

void main() {
  late GeolocatorPlatform original;
  late _LocationPlatform platform;
  setUp(() {
    original = GeolocatorPlatform.instance;
    platform = _LocationPlatform();
    GeolocatorPlatform.instance = platform;
  });
  tearDown(() => GeolocatorPlatform.instance = original);

  test(
    'foreground arrival takes a fresh bounded sample without prompting again',
    () async {
      final result = await SmartArrivalService().freshPosition();
      expect(result['accuracy'], 10);
      expect(platform.samples, 1);
      expect(platform.requests, 0);
    },
  );

  test('permission prompts require an explicit attendee action', () async {
    platform.permission = LocationPermission.denied;
    await expectLater(SmartArrivalService().freshPosition(), throwsStateError);
    expect(platform.requests, 0);
    await expectLater(
      SmartArrivalService().freshPosition(requestPermission: true),
      throwsStateError,
    );
    expect(platform.requests, 1);
    expect(platform.samples, 0);
  });

  test('stale and imprecise positions cannot be submitted', () async {
    platform.age = const Duration(minutes: 1);
    await expectLater(SmartArrivalService().freshPosition(), throwsStateError);
    platform.age = Duration.zero;
    platform.accuracy = 100;
    await expectLater(SmartArrivalService().freshPosition(), throwsStateError);
    platform.accuracy = double.nan;
    await expectLater(SmartArrivalService().freshPosition(), throwsStateError);
  });

  test(
    'browser permission uses the cancellable bounded stream after consent',
    () async {
      platform.unsupportedPermissions = true;
      final service = SmartArrivalService(isWeb: true);
      await expectLater(service.freshPosition(), throwsStateError);
      expect(platform.samples, 0);
      final result = await service.freshPosition(requestPermission: true);
      expect(result['accuracy'], 10);
      expect(platform.requests, 0);
      expect(platform.samples, 1);
    },
  );

  test(
    'leaving while permission is checked never starts a location watch',
    () async {
      platform.permissionResult = Completer<LocationPermission>();
      final service = SmartArrivalService();
      final result = expectLater(
        service.freshPosition(requestPermission: true),
        throwsStateError,
      );
      await Future<void>.delayed(Duration.zero);
      service.cancel();
      platform.permissionResult!.complete(LocationPermission.denied);
      await result;
      expect(platform.requests, 0);
      expect(platform.samples, 0);
    },
  );

  test('leaving the foreground cancels the location subscription', () async {
    platform.hold = true;
    final service = SmartArrivalService();
    final result = expectLater(service.freshPosition(), throwsStateError);
    await Future<void>.delayed(Duration.zero);
    service.cancel();
    await result;
    await Future<void>.delayed(Duration.zero);
    expect(platform.cancelled, true);
  });

  test('legacy proximity cannot silently enable Smart Arrival', () {
    final old = CheckInPolicy.fromJson({'version': 2, 'proximityAssist': true});
    expect(old.smartArrivalEnabled, false);
    expect(old.openingMode, 'manual');
    final enabled = old.copyWith(
      smartArrivalEnabled: true,
      arrivalLatitude: 40,
      arrivalLongitude: -74,
      openingMode: 'scheduled',
    );
    final decoded = CheckInPolicy.fromJson(enabled.toJson());
    expect(decoded.smartArrivalEnabled, true);
    expect(decoded.arrivalRadiusMeters, 150);
    expect(decoded.arrivalLatitude, 40);
    expect(decoded.openingMode, 'scheduled');
  });
}
