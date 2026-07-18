/// Abstraction over wall-clock time so authenticator logic stays testable.
abstract interface class TimeProvider {
  DateTime now();
}
