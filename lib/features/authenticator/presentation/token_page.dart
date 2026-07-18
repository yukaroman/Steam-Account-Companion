import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/app_avatar.dart';
import '../../../design_system/app_badge.dart';
import '../../../design_system/app_colors.dart';
import '../../../design_system/app_panel.dart';
import '../../../design_system/app_spacing.dart';
import '../../../design_system/page_header.dart';
import '../../accounts/models/steam_account.dart';
import '../data/steam_guard_authenticator_service.dart';
import '../domain/authenticator_service.dart';

class TokenPage extends StatefulWidget {
  TokenPage({
    super.key,
    AuthenticatorService? authenticatorService,
    List<SteamAccount>? accounts,
    this.onImportRequested,
    this.onSyncServerTime,
    this.onAccountDetails,
    this.timeSyncLabel = '设备时间',
    this.timeSyncDetail,
    this.timeSyncInProgress = false,
    this.encryptAccountsAtRest = true,
    this.preferAccountId,
  })  : authenticatorService =
            authenticatorService ?? DemoSteamGuardSecrets.createService(),
        accounts = accounts ?? const <SteamAccount>[];

  /// Injected for tests and future DI. Defaults to real Steam Guard math
  /// over [DemoSteamGuardSecrets] (not live Steam keys).
  final AuthenticatorService authenticatorService;

  /// Account cards to display. Defaults to empty (import empty state).
  /// Tests may pass fixtures; production loads from the repository.
  final List<SteamAccount> accounts;

  /// Optional import affordance for the empty state / add button.
  final VoidCallback? onImportRequested;

  /// Optional Steam QueryTime recalibration. Returns whether sync succeeded.
  final Future<bool> Function()? onSyncServerTime;

  /// Open SteamTools-style account metadata sheet for [accountId].
  final ValueChanged<String>? onAccountDetails;

  /// Short status for the time-sync tile (e.g. 已校准 / 设备时间).
  final String timeSyncLabel;

  /// Optional subtitle under the status value (offset hint).
  final String? timeSyncDetail;

  final bool timeSyncInProgress;

  /// Reflects current at-rest encryption mode for status copy.
  final bool encryptAccountsAtRest;

  /// When set and present in [accounts], select this account after list updates.
  final String? preferAccountId;

  @override
  State<TokenPage> createState() => _TokenPageState();
}

class _TokenPageState extends State<TokenPage> {
  late Timer _timer;
  DateTime _now = DateTime.now();
  int _selectedIndex = 0;

  AuthenticatorService get _service => widget.authenticatorService;
  List<SteamAccount> get _accounts => widget.accounts;

  bool get _hasAccounts => _accounts.isNotEmpty;

  SteamAccount get _account {
    final accounts = _accounts;
    if (accounts.isEmpty) {
      throw StateError('TokenPage has no accounts selected');
    }
    return accounts[_clampedSelectedIndex];
  }

  int get _clampedSelectedIndex {
    if (_accounts.isEmpty) return 0;
    if (_selectedIndex < 0) return 0;
    if (_selectedIndex >= _accounts.length) return _accounts.length - 1;
    return _selectedIndex;
  }

  String get _code => _service.codeFor(accountId: _account.id, now: _now);
  int get _remaining => _service.secondsRemaining(_now);
  String get _displayCode {
    final code = _code;
    if (code.length != 5) return code;
    return '${code[0]}${code[1]}${code[2]} ${code[3]}${code[4]}';
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = _clampedSelectedIndex;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void didUpdateWidget(covariant TokenPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final preferred = widget.preferAccountId;
    if (preferred != null && preferred.isNotEmpty) {
      final index = _accounts.indexWhere((a) => a.id == preferred);
      if (index >= 0) {
        final ids = widget.accounts.map((a) => a.id).join('|');
        final oldIds = oldWidget.accounts.map((a) => a.id).join('|');
        final preferenceChanged = preferred != oldWidget.preferAccountId;
        final listChanged = ids != oldIds;
        // After import, jump to the newly added account.
        if (preferenceChanged || listChanged) {
          _selectedIndex = index;
          return;
        }
      }
    }
    final next = _clampedSelectedIndex;
    if (next != _selectedIndex) {
      _selectedIndex = next;
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _requestImport() {
    if (widget.onImportRequested != null) {
      widget.onImportRequested!();
      return;
    }
    _showMessage('导入服务暂不可用，请重启应用后重试');
  }

  Future<void> _copyCode() async {
    if (!_hasAccounts) return;
    await Clipboard.setData(ClipboardData(text: _code));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: AppColors.success),
              SizedBox(width: 10),
              Text('验证码已复制'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasAccounts) {
      return _EmptyAccountsView(onImport: _requestImport);
    }

    final urgent = _remaining <= 7;
    final accent = urgent ? AppColors.warning : AppColors.cyan;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            title: '令牌',
            subtitle: '${_accounts.length} 个账号 · 本地保护',
            trailing: IconButton.filledTonal(
              tooltip: '添加账号',
              onPressed: _requestImport,
              style: IconButton.styleFrom(
                backgroundColor: AppColors.cyan.withValues(alpha: 0.12),
                foregroundColor: AppColors.cyan,
              ),
              icon: const Icon(Icons.add_rounded),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 96,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageHorizontal,
                12,
                AppSpacing.pageHorizontal,
                8,
              ),
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: _accounts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final account = _accounts[index];
                final selected = index == _selectedIndex;
                return _AccountCard(
                  account: account,
                  selected: selected,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _selectedIndex = index);
                  },
                );
              },
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageHorizontal,
            8,
            AppSpacing.pageHorizontal,
            110,
          ),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              AppPanel(
                emphasized: true,
                onTap: _copyCode,
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 24),
                child: Column(
                  children: [
                    Row(
                      children: [
                        AppAvatar(account: _account, size: 46, showRing: true),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _account.nickname,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _account.loginNameHint,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppColors.mutedText(context),
                                    ),
                              ),
                            ],
                          ),
                        ),
                        AppBadge(
                          label: _isDemoAccount(_account) ? '演示' : '本地',
                          color: _isDemoAccount(_account)
                              ? AppColors.warning
                              : AppColors.success,
                        ),
                        if (widget.onAccountDetails != null) ...[
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: '账号信息',
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              widget.onAccountDetails!(_account.id);
                            },
                            icon: const Icon(Icons.info_outline_rounded),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 34),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 360),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: Tween<double>(begin: 0.96, end: 1).animate(
                              CurvedAnimation(
                                parent: animation,
                                curve: Curves.easeOutBack,
                              ),
                            ),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        _displayCode,
                        key: ValueKey(_code),
                        style:
                            Theme.of(context).textTheme.displaySmall?.copyWith(
                          fontSize: 48,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '点击卡片复制验证码',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.mutedText(context),
                          ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: 86,
                      height: 86,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox.expand(
                            child: CircularProgressIndicator(
                              value: _remaining / 30,
                              strokeWidth: 5,
                              strokeCap: StrokeCap.round,
                              backgroundColor:
                                  AppColors.line.withValues(alpha: 0.35),
                              color: accent,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$_remaining',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                  color: accent,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              Text(
                                '秒',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color: AppColors.mutedText(context),
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatusTile(
                      icon: widget.encryptAccountsAtRest
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      label: '本地保护',
                      value: widget.encryptAccountsAtRest ? 'AES 加密' : '明文存储',
                      color: widget.encryptAccountsAtRest
                          ? AppColors.success
                          : AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatusTile(
                      icon: Icons.schedule_rounded,
                      label: '时间同步',
                      value: widget.timeSyncInProgress
                          ? '同步中…'
                          : widget.timeSyncLabel,
                      detail: widget.timeSyncDetail,
                      color: widget.timeSyncLabel == '同步失败'
                          ? AppColors.warning
                          : AppColors.blue,
                      onTap: widget.onSyncServerTime == null
                          ? null
                          : () async {
                              HapticFeedback.selectionClick();
                              final messenger = ScaffoldMessenger.of(context);
                              final ok = await widget.onSyncServerTime!();
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok ? '已与 Steam 服务器时间校准' : '时间同步失败，仍使用设备时间',
                                  ),
                                ),
                              );
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppPanel(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradientSoft,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                        border: Border.all(
                          color: AppColors.cyan.withValues(alpha: 0.2),
                        ),
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: AppColors.cyan,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        _isDemoAccount(_account)
                            ? '当前为演示密钥，不能登录 Steam。'
                            : '本地导入账号 · 验证码在设备本地生成。',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool _isDemoAccount(SteamAccount account) => account.id.startsWith('mock-');
}

class _EmptyAccountsView extends StatelessWidget {
  const _EmptyAccountsView({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(
          child: PageHeader(
            title: '令牌',
            subtitle: '还没有本地账号',
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageHorizontal,
              8,
              AppSpacing.pageHorizontal,
              120,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: AppColors.cyan,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '暂无账号',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  '导入 maFile 或从 SteamTools 导出后，验证码会出现在这里。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.mutedText(context),
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  key: const Key('token-empty-import'),
                  onPressed: onImport,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('导入账号'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final SteamAccount account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              color: selected
                  ? AppColors.cyan.withValues(alpha: dark ? 0.12 : 0.1)
                  : AppColors.panelBackground(context),
              border: Border.all(
                color: selected
                    ? AppColors.cyan.withValues(alpha: 0.55)
                    : AppColors.border(context),
                width: selected ? 1.4 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.cyan.withValues(alpha: 0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppAvatar(account: account, size: 36, showRing: selected),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    // Wide enough for full Steam account names without masking.
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account.nickname,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.fade,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: selected ? AppColors.cyan : null,
                                  ),
                        ),
                        if (account.loginNameHint != account.nickname) ...[
                          const SizedBox(height: 2),
                          Text(
                            account.loginNameHint,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.fade,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: AppColors.mutedText(context),
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.detail,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final Color color;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      onTap: onTap == null ? null : () => onTap!(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColors.mutedText(context),
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (detail != null) ...[
            const SizedBox(height: 2),
            Text(
              detail!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.mutedText(context),
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
