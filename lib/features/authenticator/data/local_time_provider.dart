import '../domain/time_provider.dart';

/// Default [TimeProvider] that reads the device clock.
class LocalTimeProvider implements TimeProvider {
  const LocalTimeProvider();

  @override
  DateTime now() => DateTime.now();
}
