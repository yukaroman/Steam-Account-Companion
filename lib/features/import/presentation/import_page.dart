import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_services.dart';
import '../../../design_system/app_colors.dart';
import '../../../design_system/app_panel.dart';
import '../../../design_system/app_spacing.dart';
import '../../../design_system/page_header.dart';
import '../domain/import_result.dart';

/// maFile / JSON import screen.
///
/// Paste content is shown in full (no default masking). Buffers and file_picker
/// temporary caches are still cleared after import.
class ImportPage extends StatefulWidget {
  const ImportPage({
    required this.services,
    this.onImportedAccountIds,
    super.key,
  });

  final AppServices services;

  /// Called after a successful import with the new/updated account ids.
  final ValueChanged<List<String>>? onImportedAccountIds;

  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  final _pasteController = TextEditingController();
  bool _busy = false;
  ImportResult? _lastResult;

  /// Per-account confirmation readiness notes after last successful import.
  List<String> _confirmNotes = const [];

  @override
  void dispose() {
    _wipePasteBuffer();
    _pasteController.dispose();
    super.dispose();
  }

  void _wipePasteBuffer() {
    _pasteController.value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
  }

  Future<void> _clearClipboardBestEffort() async {
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {
      // Clipboard may be unavailable on some platforms/tests.
    }
  }

  Future<void> _clearPickerTempBestEffort() async {
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {
      // Not supported on every desktop target; ignore.
    }
  }

  Future<void> _pickFiles() async {
    if (_busy) return;
    final picked = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['maFile', 'mafile', 'json', 'txt'],
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) {
      await _clearPickerTempBestEffort();
      return;
    }

    setState(() {
      _busy = true;
      _lastResult = null;
    });

    try {
      final items = <({String source, String? label})>[];
      for (final file in picked.files) {
        final label = file.name;
        String? text;
        if (file.bytes != null) {
          text = utf8.decode(file.bytes!, allowMalformed: false);
        } else if (file.path != null) {
          text = await File(file.path!).readAsString();
        }
        if (text == null || text.trim().isEmpty) {
          continue;
        }
        items.add((source: text, label: label));
      }

      if (items.isEmpty) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _lastResult = const ImportResult(
            successCount: 0,
            failures: [
              ImportFailure(
                code: 'empty_files',
                message: 'No readable maFile content',
              ),
            ],
          );
        });
        return;
      }

      final result = await widget.services.importMaFileJsonBatch(items);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastResult = result;
      });
      await _toastResult(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastResult = const ImportResult(
          successCount: 0,
          failures: [
            ImportFailure(
              code: 'pick_failed',
              message: 'Could not read selected files',
            ),
          ],
        );
      });
    } finally {
      await _clearPickerTempBestEffort();
    }
  }

  Future<void> _importPasted() async {
    if (_busy) return;
    final text = _pasteController.text;
    setState(() {
      _busy = true;
      _lastResult = null;
    });
    try {
      final result = await widget.services.importMaFileJson(
        text,
        sourceLabel: 'pasted JSON',
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _lastResult = result;
      });
      // Always clear paste buffer after an attempt so secrets do not linger.
      _wipePasteBuffer();
      await _clearClipboardBestEffort();
      await _toastResult(result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _wipePasteBuffer();
      await _clearClipboardBestEffort();
    }
  }

  void _notifyImported(ImportResult result) {
    if (!result.hasSuccess) return;
    final ids = result.importedAccountIds;
    if (ids.isEmpty) return;
    widget.onImportedAccountIds?.call(ids);
  }

  Future<void> _refreshConfirmNotes(ImportResult result) async {
    if (!result.hasSuccess) {
      if (mounted) setState(() => _confirmNotes = const []);
      return;
    }
    final readiness =
        await widget.services.steamConfirmationsRepository?.readiness();
    if (!mounted) return;
    final idSet = result.importedAccountIds.toSet();
    final notes = <String>[];
    for (final status in readiness?.accounts ?? const []) {
      if (!idSet.contains(status.accountId)) continue;
      if (status.ready) {
        notes.add('${status.displayName}：验证码 + 交易确认均可');
      } else if (status.missingLabels.length == 1 &&
          status.missingLabels.single == '登录会话') {
        notes.add('${status.displayName}：可出验证码 · 未含登录会话，暂不能处理确认');
      } else {
        notes.add(
          '${status.displayName}：可出验证码 · 还需 ${status.missingLabels.join('、')}',
        );
      }
    }
    setState(() => _confirmNotes = notes);
  }

  Future<void> _toastResult(ImportResult result) async {
    _notifyImported(result);
    await _refreshConfirmNotes(result);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    if (result.hasSuccess && !result.hasFailures) {
      final names = result.importedDisplayNames;
      final label = names.isEmpty
          ? '已导入 ${result.successCount} 个账号'
          : '已导入：${names.join('、')}';
      final warn =
          _confirmNotes.any((n) => n.contains('还需') || n.contains('未含'));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            warn ? '$label（验证码可用；交易确认见下方说明）' : label,
          ),
        ),
      );
      return;
    }
    if (result.hasSuccess && result.hasFailures) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '成功 ${result.successCount} 个，失败 ${result.failures.length} 个',
          ),
        ),
      );
      return;
    }
    final first =
        result.failures.isEmpty ? '导入失败' : result.failures.first.message;
    messenger.showSnackBar(SnackBar(content: Text(first)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            PageHeader(
              title: '导入账号',
              subtitle: '支持 .maFile / JSON · 明文粘贴，导入后清理缓存',
              trailing: IconButton(
                tooltip: '关闭',
                onPressed: () {
                  _wipePasteBuffer();
                  Navigator.of(context).maybePop();
                },
                icon: const Icon(Icons.close_rounded),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
              ),
              child: AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '从文件导入',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '支持 SDA maFile、SteamTools 多账号包（accounts + uuid_key）、精简 JSON。\n'
                      '• 日常出码：有验证码密钥即可\n'
                      '• 处理登录/交易请求：导出时需带登录会话（Session）\n'
                      '多数精简包没有登录会话——导入后照常出码，确认页会说明原因。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.mutedText(context),
                            height: 1.45,
                          ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      key: const Key('import-pick-files'),
                      onPressed: _busy ? null : _pickFiles,
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.folder_open_rounded),
                      label: Text(_busy ? '处理中…' : '选择 maFile'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
              ),
              child: AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '粘贴 JSON',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '完整明文显示。导入成功或失败后都会清空输入框，并尝试清空剪贴板。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.mutedText(context),
                          ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('import-paste-field'),
                      controller: _pasteController,
                      minLines: 6,
                      maxLines: 12,
                      obscureText: false,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: InputDecoration(
                        hintText:
                            '{ "shared_secret": "...", "identity_secret": "...", "steam_username": "..." }',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('import-paste-submit'),
                      onPressed: _busy ? null : _importPasted,
                      icon: const Icon(Icons.content_paste_go_rounded),
                      label: const Text('从粘贴内容导入'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              _wipePasteBuffer();
                              await _clearClipboardBestEffort();
                            },
                      child: const Text('清空粘贴区与剪贴板'),
                    ),
                  ],
                ),
              ),
            ),
            if (_lastResult != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pageHorizontal,
                ),
                child: AppPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '最近一次结果',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text('成功：${_lastResult!.successCount}'),
                      if (_lastResult!.importedDisplayNames.isNotEmpty)
                        Text(
                          '账号：${_lastResult!.importedDisplayNames.join(', ')}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      if (_lastResult!.importedAccountIds.isNotEmpty)
                        Text(
                          '内部 ID：${_lastResult!.importedAccountIds.join(', ')}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.mutedText(context),
                                  ),
                        ),
                      if (_confirmNotes.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          '确认能力',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        for (final note in _confirmNotes)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              note,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: note.contains('均可')
                                        ? AppColors.success
                                        : AppColors.warning,
                                    height: 1.35,
                                  ),
                            ),
                          ),
                        if (_confirmNotes.any(
                          (n) => n.contains('还需') || n.contains('未含'),
                        ))
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '这不影响日常验证码。若要在本 App 里同意/拒绝 Steam 登录或报价，'
                              '请用 SDA/SteamTools 导出含登录会话的完整令牌后再导入。',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: AppColors.mutedText(context),
                                    height: 1.4,
                                  ),
                            ),
                          ),
                      ],
                      for (final failure in _lastResult!.failures)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            [
                              if (failure.sourceLabel != null)
                                '${failure.sourceLabel}: ',
                              failure.message,
                            ].join(),
                            style: const TextStyle(color: AppColors.danger),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
