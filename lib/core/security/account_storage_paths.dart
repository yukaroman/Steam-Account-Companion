import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Resolves durable on-disk locations for encrypted account blobs.
abstract final class AccountStoragePaths {
  /// `…/Application Support/steam_account_companion/accounts`
  static Future<Directory> accountsRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
        p.join(support.path, 'steam_account_companion', 'accounts'));
  }
}
