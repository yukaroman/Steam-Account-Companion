import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/app_services.dart';
import '../../../core/security/account_integrity_exception.dart';
import '../../../design_system/app_colors.dart';

/// Settings entry-points for encrypted backup export / restore.
abstract final class BackupFlow {
  static Future<void> exportBackup(
    BuildContext context, {
    required AppServices services,
  }) async {
    final password = await _askPassword(
      context,
      title: '导出加密备份',
      subtitle: '设置备份口令（至少 8 位）。口令与 Face ID、本地加密开关无关；'
          '没有口令无法打开备份文件。',
      requireConfirm: true,
    );
    if (password == null || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator.adaptive()),
    );

    try {
      final bytes = await services.exportEncryptedBackup(password: password);
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // loading

      final saved = await _saveBackupFile(bytes);
      if (!context.mounted) return;
      if (saved) {
        _snack(context, '备份已导出（.sacbak）');
      } else {
        _snack(context, '已取消保存');
      }
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _snack(context, '导出失败：$error');
      }
    }
  }

  static Future<void> restoreBackup(
    BuildContext context, {
    required AppServices services,
    VoidCallback? onRestored,
  }) async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['sacbak', 'json'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      try {
        await FilePicker.clearTemporaryFiles();
      } catch (_) {}
      return;
    }

    final file = picked.files.single;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    }
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {}

    if (bytes == null || bytes.isEmpty) {
      if (context.mounted) _snack(context, '无法读取备份文件');
      return;
    }
    if (!context.mounted) return;

    final password = await _askPassword(
      context,
      title: '从备份恢复',
      subtitle: '输入导出时设置的备份口令。将合并写入本机账号；'
          '同 ID 账号会被覆盖。不会修改「本地加密存储」开关。',
      requireConfirm: false,
    );
    if (password == null || !context.mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator.adaptive()),
    );

    try {
      final result = await services.restoreEncryptedBackup(
        fileBytes: bytes,
        password: password,
      );
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      onRestored?.call();
      _snack(context, '已恢复 ${result.restoredCount} 个账号');
    } on AccountIntegrityException catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        final detail = error.message ?? '';
        final wrong = detail.contains('wrong password');
        _snack(
          context,
          wrong ? '口令错误或备份已损坏' : '恢复失败：${detail.isEmpty ? error.code : detail}',
        );
      }
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _snack(context, '恢复失败：$error');
      }
    }
  }

  static Future<bool> _saveBackupFile(Uint8List bytes) async {
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final fileName = 'steam-companion-$stamp.sacbak';

    // Preferred: system save dialog (desktop + modern mobile).
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: '保存加密备份',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['sacbak'],
        bytes: bytes,
      );
      if (path == null) return false; // cancelled
      // Some platforms write [bytes] themselves; others only return a path.
      if (!kIsWeb) {
        final file = File(path);
        if (!await file.exists() || await file.length() == 0) {
          await file.writeAsBytes(bytes, flush: true);
        }
      }
      return true;
    } catch (_) {
      // Fall through to documents-directory write.
    }

    if (kIsWeb) {
      // Last resort on web: nothing else to do without download helpers.
      return false;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _askPassword(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool requireConfirm,
  }) async {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    var obscure = true;
    String? error;

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocal) {
            return AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.mutedText(context),
                            height: 1.4,
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: passwordController,
                      obscureText: obscure,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: '备份口令',
                        suffixIcon: IconButton(
                          tooltip: obscure ? '显示' : '隐藏',
                          onPressed: () => setLocal(() => obscure = !obscure),
                          icon: Icon(
                            obscure
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                          ),
                        ),
                      ),
                      onChanged: (_) {
                        if (error != null) setLocal(() => error = null);
                      },
                    ),
                    if (requireConfirm) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: confirmController,
                        obscureText: obscure,
                        decoration: const InputDecoration(
                          labelText: '再次输入口令',
                        ),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        error!,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final pwd = passwordController.text;
                    if (pwd.trim().length < 8) {
                      setLocal(() => error = '口令至少 8 个字符');
                      return;
                    }
                    if (requireConfirm && pwd != confirmController.text) {
                      setLocal(() => error = '两次输入不一致');
                      return;
                    }
                    Navigator.pop(context, pwd);
                  },
                  child: Text(requireConfirm ? '导出' : '恢复'),
                ),
              ],
            );
          },
        );
      },
    );

    passwordController.clear();
    confirmController.clear();
    passwordController.dispose();
    confirmController.dispose();
    return result;
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
    HapticFeedback.selectionClick();
  }
}
