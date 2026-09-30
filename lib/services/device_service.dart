import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// What the server said about this device on check-in.
enum DeviceCheck { ok, revoked, needsCode, offline }

/// This install's identity and its check-ins with the server (see
/// functions/security.js).
///
/// The device id is 32 random hex characters generated on first launch and
/// kept in secure storage - not a hardware id, so no special permission. It
/// survives app updates, and a reinstall gets a new one (a new device).
class DeviceService {
  DeviceService._();

  static final DeviceService instance = DeviceService._();

  static const _storage = FlutterSecureStorage();
  static const _key = 'swapnio_device_id';
  static const Duration _minInterval = Duration(minutes: 5);

  final _functions = FirebaseFunctions.instance;
  String? _deviceId;
  DateTime? _lastCheck;
  String? _lastUid;

  /// Called when a check-in finds this device signed out remotely.
  String? lastSignOutReason;

  Future<String>? _idFuture;

  /// Shared by concurrent callers, so a first launch can't mint two ids.
  Future<String> deviceId() =>
      _idFuture ??= _loadDeviceId().catchError((Object e) {
        _idFuture = null;
        throw e;
      });

  Future<String> _loadDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    var id = await _storage.read(key: _key);
    if (id == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      final rnd = Random.secure();
      id = List.generate(
        16,
        (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await _storage.write(key: _key, value: id);
    }
    return _deviceId = id;
  }

  Future<Map<String, String>> _describe() async {
    var model = 'Unknown device';
    var os = '';
    var platform = kIsWeb ? 'web' : Platform.operatingSystem;
    try {
      final info = DeviceInfoPlugin();
      if (!kIsWeb && Platform.isAndroid) {
        final a = await info.androidInfo;
        final brand = a.brand.isEmpty
            ? ''
            : '${a.brand[0].toUpperCase()}${a.brand.substring(1)} ';
        model = '$brand${a.model}'.trim();
        os = 'Android ${a.version.release}';
      } else if (!kIsWeb && Platform.isIOS) {
        final i = await info.iosInfo;
        model = i.utsname.machine;
        os = '${i.systemName} ${i.systemVersion}';
      }
    } catch (_) {}
    var version = '';
    try {
      final p = await PackageInfo.fromPlatform();
      version = '${p.version}+${p.buildNumber}';
    } catch (_) {}
    return {
      'model': model,
      'osVersion': os,
      'appVersion': version,
      'platform': platform,
    };
  }

  /// Checks in with the server: records this device (city, last seen) and
  /// learns whether it was signed out remotely or still needs a 2FA code.
  /// At most every 5 minutes unless [force].
  Future<DeviceCheck> checkIn({bool force = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return DeviceCheck.ok;
    final recent =
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < _minInterval;
    if (!force && recent && uid == _lastUid) return DeviceCheck.ok;
    try {
      final result = await _functions.httpsCallable('registerDevice').call({
        'deviceId': await deviceId(),
        ...await _describe(),
      });
      _lastCheck = DateTime.now();
      _lastUid = uid;
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['revoked'] == true) return DeviceCheck.revoked;
      if (data['requires2fa'] == true) return DeviceCheck.needsCode;
      return DeviceCheck.ok;
    } catch (e) {
      debugPrint('DeviceService.checkIn: $e');
      return DeviceCheck.offline;
    }
  }

  static const Duration _heartbeatEvery = Duration(seconds: 60);

  /// How long after the last heartbeat a device still counts as active.
  /// Comfortably longer than [_heartbeatEvery] so one slow call doesn't
  /// flicker it to "last active".
  static const Duration activeWindow = Duration(minutes: 3);

  Timer? _heartbeat;

  /// App in the foreground: tell the server now, then keep telling it about
  /// once a minute so other devices see this one as "Active now".
  void goOnline() {
    _heartbeat?.cancel();
    _presence(true);
    _heartbeat = Timer.periodic(_heartbeatEvery, (_) => _presence(true));
  }

  /// App going to the background: stop the heartbeat and say so (best
  /// effort - if the app is killed first, the active window runs out).
  void goOffline() {
    _heartbeat?.cancel();
    _heartbeat = null;
    _presence(false);
  }

  Future<void> _presence(bool online) async {
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      await _functions.httpsCallable('devicePresence').call({
        'deviceId': await deviceId(),
        'online': online,
      });
    } catch (e) {
      debugPrint('DeviceService.presence: $e');
    }
  }

  /// Signs this device out after it was revoked from another device.
  Future<void> signOutRevoked() async {
    lastSignOutReason =
        'This device was signed out from your account settings.';
    _lastCheck = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    await FirebaseAuth.instance.signOut();
  }

  Future<void> signOutDevice(String deviceId) =>
      _functions.httpsCallable('signOutDevice').call({'deviceId': deviceId});

  Future<int> signOutOtherDevices() async {
    final r = await _functions.httpsCallable('signOutOtherDevices').call({
      'currentDeviceId': await deviceId(),
    });
    return ((r.data as Map?)?['count'] as num?)?.toInt() ?? 0;
  }

  // ------------------------------------------------------------------- 2FA

  Future<({bool enabled, int backupCodesLeft})> twoFactorStatus() async {
    final r = await _functions.httpsCallable('twoFactorStatus').call();
    final d = Map<String, dynamic>.from(r.data as Map);
    return (
      enabled: d['enabled'] == true,
      backupCodesLeft: (d['backupCodesLeft'] as num?)?.toInt() ?? 0,
    );
  }

  Future<({String secret, String otpauth})> startTwoFactorSetup() async {
    final r = await _functions.httpsCallable('startTwoFactorSetup').call();
    final d = Map<String, dynamic>.from(r.data as Map);
    return (secret: d['secret'] as String, otpauth: d['otpauth'] as String);
  }

  Future<List<String>> confirmTwoFactorSetup(String code) async {
    final r = await _functions.httpsCallable('confirmTwoFactorSetup').call({
      'code': code,
      'deviceId': await deviceId(),
    });
    return List<String>.from((r.data as Map)['backupCodes'] as List);
  }

  Future<void> verifyThisDevice(String code) async {
    await _functions.httpsCallable('verifyDeviceCode').call({
      'code': code,
      'deviceId': await deviceId(),
    });
    _lastCheck = DateTime.now();
  }

  Future<void> disableTwoFactor(String code) =>
      _functions.httpsCallable('disableTwoFactor').call({'code': code});
}
