import 'dart:convert';

import 'package:http/http.dart' as http;

import 'steam_time_client.dart';

/// POST `ITwoFactorService/QueryTime/v0001` (same endpoint as WinAuth / SteamTools).
class HttpSteamTimeClient implements SteamTimeClient {
  HttpSteamTimeClient(
      {http.Client? httpClient, this.timeout = const Duration(seconds: 8)})
      : _http = httpClient ?? http.Client();

  static final Uri queryTimeUri = Uri.parse(
    'https://api.steampowered.com/ITwoFactorService/QueryTime/v0001',
  );

  final http.Client _http;
  final Duration timeout;

  @override
  Future<int> queryServerTimeSeconds() async {
    final response = await _http.post(
      queryTimeUri,
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
    ).timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SteamTimeSyncException(
        'http_${response.statusCode}',
        'QueryTime failed with HTTP ${response.statusCode}',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const SteamTimeSyncException(
        'invalid_json',
        'QueryTime response was not JSON',
      );
    }

    if (decoded is! Map) {
      throw const SteamTimeSyncException(
        'invalid_root',
        'QueryTime response root must be an object',
      );
    }

    final responseNode = decoded['response'];
    if (responseNode is! Map) {
      throw const SteamTimeSyncException(
        'missing_response',
        'QueryTime response missing response object',
      );
    }

    final serverTime = responseNode['server_time'];
    final seconds = _parseUnixSeconds(serverTime);
    if (seconds == null) {
      throw const SteamTimeSyncException(
        'missing_server_time',
        'QueryTime response missing server_time',
      );
    }
    return seconds;
  }

  static int? _parseUnixSeconds(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }
}

class SteamTimeSyncException implements Exception {
  const SteamTimeSyncException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'SteamTimeSyncException($code): $message';
}
