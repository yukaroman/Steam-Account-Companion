enum BiometricResult { authenticated, cancelled, unavailable, failed }

abstract interface class BiometricService {
  Future<bool> get isAvailable;
  Future<BiometricResult> authenticate({required String reason});
}
