import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import 'biometric_service.dart';

/// [BiometricService] backed by `local_auth` (Face ID / Touch ID / biometrics).
///
/// Web and unsupported platforms report unavailable and fail closed.
class LocalAuthBiometricService implements BiometricService {
  LocalAuthBiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> get isAvailable async {
    if (kIsWeb) return false;
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck || supported;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<BiometricResult> authenticate({required String reason}) async {
    if (kIsWeb) return BiometricResult.unavailable;
    try {
      final available = await isAvailable;
      if (!available) return BiometricResult.unavailable;

      // Allow device credential fallback (PIN/pattern) — still system auth,
      // never silent app-level unlock. UI copy says “系统身份验证”.
      final ok = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
      return ok ? BiometricResult.authenticated : BiometricResult.failed;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.timeout =>
          BiometricResult.cancelled,
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable ||
        LocalAuthExceptionCode.uiUnavailable =>
          BiometricResult.unavailable,
        _ => BiometricResult.failed,
      };
    } catch (_) {
      return BiometricResult.failed;
    }
  }
}

/// Always-unavailable biometric service for tests / web.
class UnavailableBiometricService implements BiometricService {
  const UnavailableBiometricService();

  @override
  Future<bool> get isAvailable async => false;

  @override
  Future<BiometricResult> authenticate({required String reason}) async =>
      BiometricResult.unavailable;
}

/// Test double that always succeeds.
class AlwaysSucceedBiometricService implements BiometricService {
  const AlwaysSucceedBiometricService();

  @override
  Future<bool> get isAvailable async => true;

  @override
  Future<BiometricResult> authenticate({required String reason}) async =>
      BiometricResult.authenticated;
}
