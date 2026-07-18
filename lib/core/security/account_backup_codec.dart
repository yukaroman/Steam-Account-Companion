import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../features/accounts/models/steam_account_payload.dart';
import 'account_integrity_exception.dart';

/// Password-based encrypted backup format (`.sacbak`).
///
/// Outer file is JSON (UTF-8) with Base64 ciphertext fields so the container
/// is portable and versioned without a custom binary parser.
///
/// Wire JSON:
/// ```json
/// {
///   "format": "sacbak",
///   "version": 1,
///   "kdf": "pbkdf2-hmac-sha256",
///   "iterations": 210000,
///   "saltB64": "...",
///   "nonceB64": "...",
///   "macB64": "...",
///   "ciphertextB64": "...",
///   "accountCount": 2,
///   "exportedAt": "ISO-8601"
/// }
/// ```
///
/// Inner plaintext (AES-256-GCM):
/// ```json
/// {
///   "format": "sacbak-payload",
///   "version": 1,
///   "exportedAt": "ISO-8601",
///   "accounts": [ /* SteamAccountPayload JSON */ ]
/// }
/// ```
///
/// AAD: `sacbak-v1` (UTF-8). Password is independent of at-rest master key.
abstract final class AccountBackupCodec {
  static const formatId = 'sacbak';
  static const payloadFormatId = 'sacbak-payload';
  static const version = 1;
  static const kdfId = 'pbkdf2-hmac-sha256';
  static const defaultIterations = 210000;
  static const saltLength = 16;
  static const nonceLength = 12;
  static const aad = 'sacbak-v1';

  static final _aes = AesGcm.with256bits();
  static final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: defaultIterations,
    bits: 256,
  );

  /// Builds an encrypted `.sacbak` UTF-8 document from [accounts].
  static Future<Uint8List> encryptBackup({
    required List<SteamAccountPayload> accounts,
    required String password,
    DateTime? exportedAt,
    Random? random,
  }) async {
    final pwd = password.trim();
    if (pwd.length < 8) {
      throw ArgumentError.value(
        password,
        'password',
        'must be at least 8 characters',
      );
    }

    final when = (exportedAt ?? DateTime.now().toUtc()).toIso8601String();
    final plaintextMap = <String, Object?>{
      'format': payloadFormatId,
      'version': version,
      'exportedAt': when,
      'accounts': [for (final a in accounts) a.toJson()],
    };
    final plaintext = utf8.encode(jsonEncode(plaintextMap));

    final rng = random ?? Random.secure();
    final salt = Uint8List.fromList(
      List<int>.generate(saltLength, (_) => rng.nextInt(256)),
    );
    final secretKey = await _deriveKey(password: pwd, salt: salt);

    final secretBox = await _aes.encrypt(
      plaintext,
      secretKey: secretKey,
      aad: utf8.encode(aad),
    );

    final envelope = <String, Object?>{
      'format': formatId,
      'version': version,
      'kdf': kdfId,
      'iterations': defaultIterations,
      'saltB64': base64.encode(salt),
      'nonceB64': base64.encode(secretBox.nonce),
      'macB64': base64.encode(secretBox.mac.bytes),
      'ciphertextB64': base64.encode(secretBox.cipherText),
      'accountCount': accounts.length,
      'exportedAt': when,
    };

    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  /// Decrypts a `.sacbak` document and returns account payloads.
  static Future<AccountBackupContents> decryptBackup({
    required List<int> fileBytes,
    required String password,
  }) async {
    final pwd = password.trim();
    if (pwd.isEmpty) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'password required',
      );
    }

    final Object decoded;
    try {
      decoded = jsonDecode(utf8.decode(fileBytes));
    } on FormatException {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'backup is not valid JSON',
      );
    }
    if (decoded is! Map) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'backup root must be an object',
      );
    }
    final map = Map<String, Object?>.from(decoded);

    if (map['format'] != formatId) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'not a sacbak backup',
      );
    }
    final fileVersion = map['version'] as int? ?? 0;
    if (fileVersion != version) {
      throw AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'unsupported backup version $fileVersion',
      );
    }
    if (map['kdf'] != kdfId) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'unsupported KDF',
      );
    }
    final iterations = map['iterations'] as int? ?? 0;
    if (iterations < 100000) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'KDF iterations too low',
      );
    }

    final salt = _b64(map['saltB64']);
    final nonce = _b64(map['nonceB64']);
    final mac = _b64(map['macB64']);
    final cipherText = _b64(map['ciphertextB64']);

    final secretKey = await _deriveKey(
      password: pwd,
      salt: salt,
      iterations: iterations,
    );

    final SecretBox box;
    try {
      box = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    } catch (_) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'backup envelope malformed',
      );
    }

    final List<int> plainBytes;
    try {
      plainBytes = await _aes.decrypt(
        box,
        secretKey: secretKey,
        aad: utf8.encode(aad),
      );
    } catch (_) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'wrong password or corrupted backup',
      );
    }

    final Object plainJson;
    try {
      plainJson = jsonDecode(utf8.decode(plainBytes));
    } on FormatException {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'backup payload is not valid JSON',
      );
    }
    if (plainJson is! Map) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'backup payload root must be an object',
      );
    }
    final payloadMap = Map<String, Object?>.from(plainJson);
    if (payloadMap['format'] != payloadFormatId) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'invalid backup payload format',
      );
    }

    final accountsRaw = payloadMap['accounts'];
    if (accountsRaw is! List) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'accounts array missing',
      );
    }

    final accounts = <SteamAccountPayload>[];
    for (final entry in accountsRaw) {
      if (entry is! Map) {
        throw const AccountIntegrityException(
          AccountIntegrityException.swappedOrTampered,
          'account entry must be an object',
        );
      }
      accounts.add(
        SteamAccountPayload.fromJson(Map<String, Object?>.from(entry)),
      );
    }

    return AccountBackupContents(
      accounts: accounts,
      exportedAt: payloadMap['exportedAt'] as String?,
    );
  }

  static Future<SecretKey> _deriveKey({
    required String password,
    required List<int> salt,
    int iterations = defaultIterations,
  }) async {
    final kdf = iterations == defaultIterations
        ? _pbkdf2
        : Pbkdf2(
            macAlgorithm: Hmac.sha256(),
            iterations: iterations,
            bits: 256,
          );
    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
  }

  static List<int> _b64(Object? value) {
    if (value is! String || value.isEmpty) {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'missing base64 field',
      );
    }
    try {
      return base64.decode(value);
    } on FormatException {
      throw const AccountIntegrityException(
        AccountIntegrityException.swappedOrTampered,
        'invalid base64 field',
      );
    }
  }
}

class AccountBackupContents {
  const AccountBackupContents({
    required this.accounts,
    this.exportedAt,
  });

  final List<SteamAccountPayload> accounts;
  final String? exportedAt;
}
