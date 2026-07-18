import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/app_services.dart';
import '../../../design_system/app_badge.dart';
import '../../../design_system/app_colors.dart';
import '../../../design_system/app_panel.dart';
import '../../../design_system/app_spacing.dart';
import '../../../design_system/page_header.dart';
import '../../auth_session/presentation/steam_login_sheet.dart';
import '../data/steam_confirmations_repository.dart';
import '../domain/steam_mobile_session.dart';
import '../models/steam_confirmation.dart';

class ConfirmationsPage extends StatefulWidget {
  const ConfirmationsPage({this.services, super.key});

  final AppServices? services;

  @override
  State<ConfirmationsPage> createState() => _ConfirmationsPageState();
}

class _ConfirmationsPageState extends State<ConfirmationsPage> {
  List<SteamConfirmation> _items = const [];
  ConfirmationsReadiness? _readiness;
  var _loading = false;
  Object? _error;
  String? _busyId;

  /// Guards against out-of-order async refresh completions.
  var _refreshGeneration = 0;

  /// Debounce login/import revision storms that would hammer Steam getlist.
  Timer? _revisionDebounce;
  DateTime? _lastSuccessfulFetchAt;

  @override
  void initState() {
    super.initState();
    widget.services?.accountsRevision.addListener(_onAccountsRevision);
    _bootstrap();
  }

  @override
  void didUpdateWidget(covariant ConfirmationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services != widget.services) {
      oldWidget.services?.accountsRevision.removeListener(_onAccountsRevision);
      widget.services?.accountsRevision.addListener(_onAccountsRevision);
      _bootstrap();
    }
  }

  @override
  void dispose() {
    _revisionDebounce?.cancel();
    widget.services?.accountsRevision.removeListener(_onAccountsRevision);
    super.dispose();
  }

  void _onAccountsRevision() {
    // Only import / delete / restore bump accountsRevision — not time sync.
    _revisionDebounce?.cancel();
    _revisionDebounce = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      // Skip automatic fetch if we just pulled successfully (login + open tab).
      final last = _lastSuccessfulFetchAt;
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 8)) {
        _reloadReadiness(fetchIfReady: false);
        return;
      }
      _reloadReadiness(fetchIfReady: true);
    });
  }

  Future<void> _bootstrap() => _reloadReadiness(fetchIfReady: true);

  Future<void> _reloadReadiness({required bool fetchIfReady}) async {
    final services = widget.services;
    if (services == null) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _readiness = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    final repo = services.steamConfirmationsRepository;
    if (repo == null) return;
    final readiness = await repo.readiness();
    if (!mounted) return;
    setState(() {
      _readiness = readiness;
      if (readiness.canFetch && _error != null) {
        _error = null;
      }
    });
    if (fetchIfReady && readiness.canFetch) {
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    final services = widget.services;
    if (services == null) return;
    final gen = ++_refreshGeneration;

    if (kIsWeb) {
      if (!mounted || gen != _refreshGeneration) return;
      setState(() {
        _error = '浏览器无法直连 Steam 社区接口。请在 iPhone / macOS 上使用确认功能。';
        _items = const [];
        _loading = false;
      });
      return;
    }

    if (!mounted || gen != _refreshGeneration) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final readiness =
          await services.steamConfirmationsRepository?.readiness();
      if (!mounted || gen != _refreshGeneration) return;
      setState(() => _readiness = readiness);

      if (readiness == null || !readiness.canFetch) {
        setState(() {
          _items = const [];
          _loading = false;
          _error = null;
        });
        return;
      }

      // mobileconf HMAC uses server-adjusted time — must finish before getlist.
      await services.syncServerTime(notify: false);
      final items = await services.confirmationsRepository.pending();
      if (!mounted || gen != _refreshGeneration) return;
      _lastSuccessfulFetchAt = DateTime.now();
      setState(() {
        _items = items;
        _readiness = readiness;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || gen != _refreshGeneration) return;
      setState(() {
        _loading = false;
        _error = error is ConfirmationsException ? error.message : '$error';
        if (error is ConfirmationsException && error.code == 'not_ready') {
          _items = const [];
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    final readiness = _readiness;
    final subtitle = services == null
        ? '服务未就绪'
        : _loading
            ? '正在同步 Steam 确认…'
            : readiness == null || readiness.accountCount == 0
                ? '导入令牌后显示验证码与确认状态'
                : readiness.canFetch
                    ? '${_items.length} 项待处理 · ${readiness.readyCount} 个账号可确认'
                    : '验证码可用 · 登录后可处理交易确认';

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        _ConfirmationsHeader(
          subtitle: subtitle,
          loading: _loading,
          onRefresh: _refresh,
        ),
        // SteamTools-style: single list, no login/market/trade filter chips.
        // getlist still returns all mobileconf types; cards show type badges.
        if (services == null)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _StatusPane(
              title: '确认服务不可用',
              body: '请重启应用后再试。',
            ),
          )
        else if (kIsWeb)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _StatusPane(
              title: '请在手机或桌面 App 使用',
              body: '浏览器无法直接连接 Steam 确认接口。'
                  '请在 iPhone / macOS / Android 上使用，并登录会话后刷新。',
            ),
          )
        else ...[
          if (readiness != null && readiness.accounts.isNotEmpty)
            SliverToBoxAdapter(
              child: _AccountReadinessSection(
                readiness: readiness,
                services: services,
                onLoggedIn: () => _reloadReadiness(fetchIfReady: true),
              ),
            ),
          if (_error != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageHorizontal,
                  4,
                  AppSpacing.pageHorizontal,
                  8,
                ),
                child: AppPanel(
                  child: Column(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.danger, size: 28),
                      const SizedBox(height: 10),
                      Text(
                        '$_error',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 10),
                      TextButton(onPressed: _refresh, child: const Text('重试')),
                    ],
                  ),
                ),
              ),
            ),
          if (readiness != null && !readiness.canFetch)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _StatusPane(
                title: readiness.accountCount == 0 ? '还没有账号' : '验证码可用，登录后可处理确认',
                body: readiness.accountCount == 0
                    ? '先在「令牌」页导入令牌文件。\n'
                        '导入后即可显示 5 位验证码；处理交易确认需登录一次 Steam。'
                    : '上方已列出每个账号状态。精简 JSON 通常只有验证码密钥——可以出码，'
                        '但还不能查询 Steam 确认。\n\n'
                        '点账号旁的「登录」输入 Steam 密码，本机会自动填验证码并保存会话。',
              ),
            )
          else if (_loading && _items.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator.adaptive()),
              ),
            )
          else if (_items.isEmpty)
            _ConfirmationsEmpty(onRefresh: _refresh)
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageHorizontal,
                8,
                AppSpacing.pageHorizontal,
                110,
              ),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index.isOdd) return const SizedBox(height: 14);
                    final item = _items[index ~/ 2];
                    final busy = _busyId == item.id;
                    return _ConfirmationCard(
                      item: item,
                      busy: busy,
                      onApprove: busy
                          ? null
                          : () => _handleAction(item, approved: true),
                      onReject: busy
                          ? null
                          : () => _handleAction(item, approved: false),
                    );
                  },
                  childCount: _items.length * 2 - 1,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Future<void> _handleAction(
    SteamConfirmation item, {
    required bool approved,
  }) async {
    final services = widget.services;
    if (services == null || _busyId != null) return;

    if (item.risk == ConfirmationRisk.high && approved) {
      final confirmed = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        backgroundColor: AppColors.panelBackground(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.gpp_maybe_rounded,
                    color: AppColors.warning,
                    size: 34,
                  ),
                ),
                const SizedBox(height: 16),
                Text('确认操作', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  '${item.title}\n${item.subtitle}\n\n'
                  '将向 Steam 发送「允许」。此操作不需要 Face ID。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.mutedText(context),
                      ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('确认并允许'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _busyId = item.id);
    try {
      if (approved) {
        await services.confirmationsRepository.approve(item);
      } else {
        await services.confirmationsRepository.reject(item);
      }
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _items = _items.where((c) => c.id != item.id).toList();
        _busyId = null;
      });
      _showMessage(approved ? '已允许' : '已拒绝');
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyId = null);
      final message =
          error is ConfirmationsException ? error.message : '操作失败，请稍后重试';
      _showMessage(message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ConfirmationsHeader extends StatelessWidget {
  const _ConfirmationsHeader({
    required this.subtitle,
    required this.loading,
    required this.onRefresh,
  });

  final String subtitle;
  final bool loading;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: PageHeader(
        // Align with SteamTools Authenticator “确认交易” framing.
        title: '交易确认',
        subtitle: subtitle,
        trailing: IconButton.filledTonal(
          tooltip: '刷新',
          onPressed: loading ? null : onRefresh,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.blue.withValues(alpha: 0.12),
            foregroundColor: AppColors.blue,
          ),
          icon: loading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ),
    );
  }
}

class _ConfirmationsEmpty extends StatelessWidget {
  const _ConfirmationsEmpty({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: _EmptyState(onRefresh: onRefresh),
    );
  }
}

class _ConfirmationCard extends StatelessWidget {
  const _ConfirmationCard({
    required this.item,
    required this.onApprove,
    required this.onReject,
    this.busy = false,
  });

  final SteamConfirmation item;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final presentation = _presentation(item.kind);
    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: presentation.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: presentation.color.withValues(alpha: 0.18),
                  ),
                ),
                child: Icon(presentation.icon, color: presentation.color),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          presentation.label,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: presentation.color,
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                  ),
                        ),
                        AppBadge(
                          label: _riskLabel(item.risk),
                          color: _riskColor(item.risk),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      softWrap: true,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            height: 1.3,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            item.subtitle,
            softWrap: true,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mutedText(context),
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_circle_outlined,
                      size: 16,
                      color: AppColors.mutedText(context),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.accountName,
                      softWrap: true,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.mutedText(context),
                            height: 1.25,
                          ),
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: AppColors.mutedText(context),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.timeLabel,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.mutedText(context),
                            height: 1.25,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: AppColors.danger,
                    side: BorderSide(
                      color: AppColors.danger.withValues(alpha: 0.4),
                    ),
                  ),
                  child: busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('拒绝'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onApprove,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                  child: const Text('允许'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _riskLabel(ConfirmationRisk risk) {
    return switch (risk) {
      ConfirmationRisk.low => '低风险',
      ConfirmationRisk.medium => '注意',
      ConfirmationRisk.high => '高风险',
    };
  }

  Color _riskColor(ConfirmationRisk risk) {
    return switch (risk) {
      ConfirmationRisk.low => AppColors.success,
      ConfirmationRisk.medium => AppColors.warning,
      ConfirmationRisk.high => AppColors.danger,
    };
  }

  _KindPresentation _presentation(ConfirmationKind kind) {
    return switch (kind) {
      ConfirmationKind.login => const _KindPresentation(
          label: '登录请求',
          icon: Icons.devices_rounded,
          color: AppColors.cyan,
        ),
      ConfirmationKind.trade => const _KindPresentation(
          label: '交易确认',
          icon: Icons.swap_horiz_rounded,
          color: AppColors.violet,
        ),
      ConfirmationKind.market => const _KindPresentation(
          label: '市场操作',
          icon: Icons.storefront_rounded,
          color: AppColors.warning,
        ),
      ConfirmationKind.other => const _KindPresentation(
          label: '其他确认',
          icon: Icons.verified_user_outlined,
          color: AppColors.blue,
        ),
    };
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.cyan.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inbox_outlined,
                color: AppColors.cyan, size: 34),
          ),
          const SizedBox(height: 18),
          Text(
            '暂无待处理确认',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '列表已同步。发起一笔交易报价或市场上架后，'
            '点右上角刷新即可处理（与 SteamTools「确认交易」一致）。',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mutedText(context),
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          TextButton(onPressed: onRefresh, child: const Text('刷新')),
        ],
      ),
    );
  }
}

class _AccountReadinessSection extends StatelessWidget {
  const _AccountReadinessSection({
    required this.readiness,
    required this.services,
    required this.onLoggedIn,
  });

  final ConfirmationsReadiness readiness;
  final AppServices services;
  final Future<void> Function() onLoggedIn;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.mutedText(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageHorizontal,
        4,
        AppSpacing.pageHorizontal,
        8,
      ),
      child: AppPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '账号状态 · ${readiness.readyCount}/${readiness.accountCount} 可处理确认',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              '验证码与交易确认是两套能力。出码通常已够用；'
              '处理报价等确认需要登录会话——可在本机用密码登录获取。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                    height: 1.35,
                  ),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < readiness.accounts.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              _AccountReadinessRow(
                status: readiness.accounts[i],
                services: services,
                onLoggedIn: onLoggedIn,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountReadinessRow extends StatelessWidget {
  const _AccountReadinessRow({
    required this.status,
    required this.services,
    required this.onLoggedIn,
  });

  final ConfirmationAccountStatus status;
  final AppServices services;
  final Future<void> Function() onLoggedIn;

  static String _statusSummary(ConfirmationAccountStatus status) {
    if (status.ready) {
      return switch (status.sessionHealth) {
        SteamSessionHealth.refreshable =>
          '完整 · ${status.sessionHealth.shortLabel} · 可处理确认',
        _ => '完整 · ${status.sessionHealth.shortLabel} · 可处理确认',
      };
    }
    if (status.sessionHealth == SteamSessionHealth.expired) {
      return '可出验证码 · 会话已过期，请重新登录';
    }
    final missing = status.missingLabels;
    if (missing.length == 1 &&
        (missing.single == '登录会话' || missing.single.contains('登录会话'))) {
      return '可出验证码 · 尚未登录，暂不能查询/处理 Steam 确认';
    }
    if (missing.any((e) => e.contains('登录会话')) && missing.length > 1) {
      final others = missing.where((e) => !e.contains('登录会话')).join('、');
      return '可出验证码 · 还需：$others、登录会话';
    }
    return '材料不完整 · 还需：${missing.join('、')}';
  }

  /// Login is gated inside the session service (needs local Guard material).
  /// Do not hide the button when device id / SteamID are still missing — those
  /// block mobileconf readiness, not password login.
  bool get _showLogin => true;

  bool get _showClear => status.hasStoredSession;

  Future<void> _openLogin(BuildContext context) async {
    final ok = await showSteamLoginSheet(
      context,
      services: services,
      accountId: status.accountId,
    );
    if (ok == true) {
      await onLoggedIn();
    }
  }

  Future<void> _clearSession(BuildContext context) async {
    final clearPassword = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除登录会话？'),
        content: Text(
          '将删除「${status.displayName}」本地保存的 Steam 登录令牌。'
          '验证码仍可用；之后需重新登录才能处理确认。\n\n'
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
    if (clearPassword == null) return;
    final ok = await services.clearSteamSession(
      status.accountId,
      clearSavedPassword: clearPassword,
    );
    if (ok) {
      await onLoggedIn();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清除登录会话')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = status.ready
        ? AppColors.success
        : (status.sessionHealth == SteamSessionHealth.expired
            ? AppColors.danger
            : AppColors.warning);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          status.ready
              ? Icons.check_circle_rounded
              : (status.sessionHealth == SteamSessionHealth.expired
                  ? Icons.timer_off_outlined
                  : Icons.info_outline_rounded),
          color: color,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                status.displayName,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                _statusSummary(status),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.mutedText(context),
                      height: 1.3,
                    ),
              ),
              if (_showLogin || _showClear) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  children: [
                    if (_showLogin)
                      TextButton(
                        onPressed: () => _openLogin(context),
                        child: Text(
                          status.hasStoredSession || status.hasSession
                              ? '重新登录'
                              : '登录',
                        ),
                      ),
                    if (_showClear)
                      TextButton(
                        onPressed: () => _clearSession(context),
                        child: const Text('清除会话'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusPane extends StatelessWidget {
  const _StatusPane({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.violet.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.link_off_rounded,
                color: AppColors.violet, size: 34),
          ),
          const SizedBox(height: 18),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.mutedText(context),
                  height: 1.45,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _KindPresentation {
  const _KindPresentation({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}
