import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/app_colors.dart';
import '../../../design_system/app_spacing.dart';
import '../../confirmations/domain/steam_mobile_session.dart';
import '../models/steam_account_details.dart';

/// Bottom sheet listing account metadata + optional owner-revealed secrets.
///
/// Returns `true` if the account was deleted.
Future<bool?> showAccountDetailsSheet(
  BuildContext context, {
  required Future<SteamAccountDetails?> Function({bool includeSecrets})
      loadDetails,
  Future<void> Function()? onDelete,

  /// Opens in-app Steam login for Session (returns true if session obtained).
  Future<bool> Function(SteamAccountDetails details)? onLoginForSession,

  /// Clears Session; [clearSavedPassword] chosen by UI dialog.
  Future<bool> Function(
    SteamAccountDetails details, {
    required bool clearSavedPassword,
  })? onClearSession,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: AppColors.panelBackground(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return SafeArea(
        child: _AccountDetailsSheet(
          loadDetails: loadDetails,
          onDelete: onDelete,
          onLoginForSession: onLoginForSession,
          onClearSession: onClearSession,
        ),
      );
    },
  );
}

class _AccountDetailsSheet extends StatefulWidget {
  const _AccountDetailsSheet({
    required this.loadDetails,
    this.onDelete,
    this.onLoginForSession,
    this.onClearSession,
  });

  final Future<SteamAccountDetails?> Function({bool includeSecrets})
      loadDetails;
  final Future<void> Function()? onDelete;
  final Future<bool> Function(SteamAccountDetails details)? onLoginForSession;
  final Future<bool> Function(
    SteamAccountDetails details, {
    required bool clearSavedPassword,
  })? onClearSession;

  @override
  State<_AccountDetailsSheet> createState() => _AccountDetailsSheetState();
}

class _AccountDetailsSheetState extends State<_AccountDetailsSheet> {
  late Future<SteamAccountDetails?> _future =
      widget.loadDetails(includeSecrets: false);
  var _revealBusy = false;
  var _deleteBusy = false;

  Future<void> _revealSecrets() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('查看敏感密钥？'),
        content: const Text(
          '将显示 shared_secret、identity_secret、恢复码（若有）和已保存的密码。\n\n'
          '请确认周围无人旁窥，且本机仅你本人使用。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认查看'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _revealBusy = true);
    final next = widget.loadDetails(includeSecrets: true);
    setState(() {
      _future = next;
      _revealBusy = false;
    });
  }

  Future<void> _hideSecrets() async {
    setState(() {
      _future = widget.loadDetails(includeSecrets: false);
    });
  }

  Future<void> _confirmDelete(SteamAccountDetails details) async {
    if (widget.onDelete == null || _deleteBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除此账号？'),
        content: Text(
          '将从本机永久删除「${details.displayName}」的令牌与密钥，'
          '此操作不可撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleteBusy = true);
    try {
      await widget.onDelete!();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleteBusy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败，请重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SteamAccountDetails?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            _revealBusy ||
            _deleteBusy) {
          return const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator.adaptive()),
          );
        }
        final details = snapshot.data;
        if (details == null) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              '无法加载账号信息',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          );
        }
        return _AccountDetailsBody(
          details: details,
          onRevealSecrets: _revealSecrets,
          onHideSecrets: _hideSecrets,
          onDelete:
              widget.onDelete == null ? null : () => _confirmDelete(details),
          onLoginForSession: widget.onLoginForSession == null
              ? null
              : () async {
                  final ok = await widget.onLoginForSession!(details);
                  if (ok && mounted) {
                    setState(() {
                      _future = widget.loadDetails(
                        includeSecrets: details.secretsRevealed,
                      );
                    });
                  }
                },
          onClearSession: widget.onClearSession == null
              ? null
              : () => _clearSession(details),
        );
      },
    );
  }

  Future<void> _clearSession(SteamAccountDetails details) async {
    final clearPassword = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除登录会话？'),
        content: const Text(
          '将删除本机保存的 Steam 登录令牌（access/refresh token）。'
          '验证码仍然可用；处理确认需重新登录。\n\n'
          '是否同时清除已记住的密码？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('仅清会话'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('会话+密码'),
          ),
        ],
      ),
    );
    if (clearPassword == null || widget.onClearSession == null) return;
    final ok = await widget.onClearSession!(
      details,
      clearSavedPassword: clearPassword,
    );
    if (ok && mounted) {
      setState(() {
        _future = widget.loadDetails(includeSecrets: details.secretsRevealed);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清除登录会话')),
        );
      }
    }
  }
}

class _AccountDetailsBody extends StatelessWidget {
  const _AccountDetailsBody({
    required this.details,
    required this.onRevealSecrets,
    required this.onHideSecrets,
    this.onDelete,
    this.onLoginForSession,
    this.onClearSession,
  });

  final SteamAccountDetails details;
  final VoidCallback onRevealSecrets;
  final VoidCallback onHideSecrets;
  final VoidCallback? onDelete;
  final Future<void> Function()? onLoginForSession;
  final Future<void> Function()? onClearSession;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.mutedText(context);
    final maxH = MediaQuery.sizeOf(context).height * 0.85;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageHorizontal,
          4,
          AppSpacing.pageHorizontal,
          24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '账号信息',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '参考 SteamTools / SDA · 敏感密钥需确认后查看',
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _InfoRow(
                      label: '显示名',
                      value: details.displayName,
                      copyable: true,
                    ),
                    _InfoRow(
                      label: '登录名 / account_name',
                      value: details.loginName ?? '—',
                      copyable: details.loginName != null,
                    ),
                    _InfoRow(
                      label: 'SteamID64',
                      value: details.steamId64 ?? '—',
                      copyable: details.steamId64 != null,
                      hint: 'maFile Session.SteamID / steamid',
                    ),
                    _InfoRow(
                      label: '序列号 serial_number',
                      value: details.serialNumber ?? '—',
                      copyable: details.serialNumber != null,
                    ),
                    _InfoRow(
                      label: '设备 ID device_id',
                      value: details.deviceId ?? '—',
                      copyable: details.deviceId != null,
                      mono: true,
                    ),
                    _InfoRow(
                      label: '内部账号 ID',
                      value: details.accountId,
                      copyable: true,
                      mono: true,
                    ),
                    const SizedBox(height: 8),
                    _StatusChips(details: details),
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: '登录会话',
                      value: details.sessionStatusLabel,
                      hint: details.sessionHealth.detailLabel,
                    ),
                    if ((onLoginForSession != null &&
                            details.hasSharedSecret) ||
                        (onClearSession != null &&
                            details.hasStoredSession)) ...[
                      const SizedBox(height: 12),
                      if (onLoginForSession != null && details.hasSharedSecret)
                        FilledButton.tonalIcon(
                          onPressed: () => onLoginForSession!(),
                          icon: const Icon(Icons.login_rounded),
                          label: Text(
                            details.sessionHealth == SteamSessionHealth.none
                                ? '登录获取会话（处理确认）'
                                : '重新登录会话',
                          ),
                        ),
                      if (onClearSession != null &&
                          details.hasStoredSession) ...[
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: () => onClearSession!(),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('清除登录会话'),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '敏感密钥',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (!details.secretsRevealed) ...[
                      Text(
                        '默认隐藏 shared_secret / identity_secret / 恢复码 / 密码。'
                        '个人自用可点下方确认后查看与复制。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: muted,
                              height: 1.35,
                            ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: onRevealSecrets,
                          icon: const Icon(Icons.visibility_rounded),
                          label: const Text('确认后查看密钥'),
                        ),
                      ),
                    ] else ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Text(
                          '密钥已显示 · 勿截图分享 · 离开本页后需重新确认',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InfoRow(
                        label: 'shared_secret (Base64)',
                        value: details.sharedSecretBase64 ?? '—',
                        copyable: details.sharedSecretBase64 != null,
                        mono: true,
                        emphasize: true,
                      ),
                      _InfoRow(
                        label: 'identity_secret (Base64)',
                        value: details.identitySecretBase64 ?? '—',
                        copyable: details.identitySecretBase64 != null,
                        mono: true,
                        emphasize: true,
                      ),
                      _InfoRow(
                        label: '恢复码 revocation_code',
                        value: details.revocationCode ?? '—',
                        copyable: details.revocationCode != null,
                        mono: true,
                        emphasize: details.revocationCode != null,
                        hint: 'SDA 导出中的 R#####，请妥善保管',
                      ),
                      _InfoRow(
                        label: 'steam_password',
                        value: details.steamPassword ?? '—',
                        copyable: details.steamPassword != null,
                        emphasize: details.steamPassword != null,
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onHideSecrets,
                          icon: const Icon(Icons.visibility_off_rounded),
                          label: const Text('隐藏密钥'),
                        ),
                      ),
                    ],
                    if (onDelete != null) ...[
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const Key('account-delete-button'),
                          onPressed: onDelete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: BorderSide(
                              color: AppColors.danger.withValues(alpha: 0.45),
                            ),
                            minimumSize: const Size(0, 48),
                          ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: const Text('删除此账号'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChips extends StatelessWidget {
  const _StatusChips({required this.details});

  final SteamAccountDetails details;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(
          context,
          details.isDemo ? '演示账号' : '本地导入',
          details.isDemo ? AppColors.warning : AppColors.success,
        ),
        _chip(
          context,
          details.hasSharedSecret ? '已有 shared_secret' : '缺少 shared_secret',
          details.hasSharedSecret ? AppColors.cyan : AppColors.danger,
        ),
        _chip(
          context,
          details.confirmationCapabilityLabel,
          details.hasIdentitySecret ? AppColors.violet : AppColors.slate,
        ),
        _chip(
          context,
          details.hasSteamPassword ? '已导入密码' : '无密码',
          AppColors.blue,
        ),
        _chip(
          context,
          details.hasRevocationCode ? '有恢复码' : '无恢复码',
          details.hasRevocationCode ? AppColors.warning : AppColors.slate,
        ),
        _chip(
          context,
          details.sessionStatusLabel,
          switch (details.sessionHealth) {
            SteamSessionHealth.active => AppColors.success,
            SteamSessionHealth.refreshable => AppColors.cyan,
            SteamSessionHealth.expired => AppColors.danger,
            SteamSessionHealth.none => AppColors.warning,
          },
        ),
      ],
    );
  }

  Widget _chip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.25,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
    this.mono = false,
    this.emphasize = false,
    this.hint,
  });

  final String label;
  final String value;
  final bool copyable;
  final bool mono;
  final bool emphasize;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.mutedText(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontFamily: mono ? 'monospace' : null,
                          fontSize: mono ? 12 : null,
                          fontWeight:
                              emphasize ? FontWeight.w800 : FontWeight.w600,
                          height: 1.35,
                          color: emphasize ? AppColors.warning : null,
                        ),
                  ),
                  if (hint != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      hint!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontSize: 11,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            if (copyable && value != '—')
              IconButton(
                tooltip: '复制',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: value));
                  HapticFeedback.selectionClick();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('已复制$label')),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}
