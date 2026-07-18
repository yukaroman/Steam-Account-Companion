import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../features/accounts/models/steam_account.dart';
import '../features/accounts/presentation/account_details_sheet.dart';
import '../features/auth_session/presentation/steam_login_sheet.dart';
import '../features/authenticator/presentation/token_page.dart';
import '../features/confirmations/presentation/confirmations_page.dart';
import '../features/import/presentation/import_page.dart';
import '../features/settings/presentation/settings_page.dart';
import '../design_system/app_colors.dart';
import '../design_system/soft_background.dart';
import 'app_controller.dart';
import 'app_services.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.controller,
    this.services,
    super.key,
  });

  final AppController controller;
  final AppServices? services;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  bool _loadingAccounts = true;
  Object? _accountsError;
  List<SteamAccount>? _accounts;

  /// After import, prefer selecting this account id once lists reload.
  String? _preferAccountId;

  @override
  void initState() {
    super.initState();
    widget.services?.addListener(_onServicesChanged);
    _loadAccounts();
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.services != widget.services) {
      oldWidget.services?.removeListener(_onServicesChanged);
      widget.services?.addListener(_onServicesChanged);
      _loadAccounts();
    }
  }

  @override
  void dispose() {
    widget.services?.removeListener(_onServicesChanged);
    super.dispose();
  }

  void _onServicesChanged() {
    // Time sync / encrypt flag / etc. — refresh chrome only.
    // Do NOT reload the account list here: that set _loadingAccounts and
    // replaced TokenPage with a spinner (looked like a full page refresh).
    if (mounted) setState(() {});
  }

  Future<void> _loadAccounts({bool showFullPageLoading = true}) async {
    final services = widget.services;
    if (services == null) {
      if (!mounted) return;
      setState(() {
        _loadingAccounts = false;
        _accounts = null;
        _accountsError = null;
      });
      return;
    }

    // Keep showing the current token UI while refreshing when possible.
    if (showFullPageLoading || _accounts == null) {
      setState(() {
        _loadingAccounts = true;
        _accountsError = null;
      });
    }

    try {
      final profiles = await services.accountsRepository.listProfiles();
      if (!mounted) return;
      setState(() {
        _accounts = [
          for (final profile in profiles) SteamAccount.fromProfile(profile),
        ];
        _loadingAccounts = false;
        _accountsError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _accountsError = error;
        _loadingAccounts = false;
        // Keep previous accounts on soft refresh failure.
        _accounts ??= const [];
      });
    }
  }

  String _timeSyncLabel(AppServices? services) {
    if (services == null) return '设备时间';
    if (services.timeSyncInProgress) return '同步中…';
    if (services.lastTimeSyncError != null) return '同步失败';
    if (services.hasSyncedServerTime) return '已校准';
    return '设备时间';
  }

  String? _timeSyncDetail(AppServices? services) {
    if (services == null || !services.hasSyncedServerTime) return null;
    final diffMs = services.serverTimeDiffMs;
    final absSec = (diffMs.abs() / 1000).round();
    if (absSec == 0) return '与 Steam 一致 · 点按重校';
    final sign = diffMs >= 0 ? '+' : '-';
    return '偏移 $sign${absSec}s · 点按重校';
  }

  Future<void> _openImport() async {
    final services = widget.services;
    if (services == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('导入服务不可用')),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ImportPage(
          services: services,
          onImportedAccountIds: (ids) {
            if (ids.isNotEmpty) _preferAccountId = ids.last;
          },
        ),
      ),
    );
    // App list may have changed; reload without blanking the whole page.
    await _loadAccounts(showFullPageLoading: false);
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;

    final Widget tokenChild;
    if (services != null && _loadingAccounts) {
      tokenChild = const Center(child: CircularProgressIndicator.adaptive());
    } else if (services != null && _accountsError != null) {
      tokenChild = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.danger),
              const SizedBox(height: 12),
              Text(
                '账号列表加载失败',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: _loadAccounts, child: const Text('重试')),
            ],
          ),
        ),
      );
    } else {
      final syncLabel = _timeSyncLabel(services);
      final syncDetail = _timeSyncDetail(services);
      tokenChild = TokenPage(
        authenticatorService: services?.authenticatorService,
        // Always pass an explicit list — never null (null used to fall back to demos).
        accounts: _accounts ?? const <SteamAccount>[],
        onImportRequested: _openImport,
        preferAccountId: _preferAccountId,
        timeSyncLabel: syncLabel,
        timeSyncDetail: syncDetail,
        timeSyncInProgress: services?.timeSyncInProgress ?? false,
        encryptAccountsAtRest: services?.encryptAccountsAtRest ?? true,
        onSyncServerTime: services == null
            ? null
            : () async {
                final result = await services.syncServerTime();
                return result != null;
              },
        onAccountDetails: services == null
            ? null
            : (accountId) async {
                final deleted = await showAccountDetailsSheet(
                  context,
                  loadDetails: ({bool includeSecrets = false}) =>
                      services.loadAccountDetails(
                    accountId,
                    includeSecrets: includeSecrets,
                  ),
                  onDelete: () => services.deleteAccount(accountId),
                  onLoginForSession: (details) async {
                    final ok = await showSteamLoginSheet(
                      context,
                      services: services,
                      accountId: details.accountId,
                    );
                    return ok == true;
                  },
                  onClearSession: (details, {required clearSavedPassword}) {
                    return services.clearSteamSession(
                      details.accountId,
                      clearSavedPassword: clearSavedPassword,
                    );
                  },
                );
                if (deleted == true) {
                  if (_preferAccountId == accountId) {
                    _preferAccountId = null;
                  }
                  await _loadAccounts(showFullPageLoading: false);
                }
              },
      );
    }

    return Scaffold(
      extendBody: true,
      body: SoftBackground(
        child: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: _index,
            children: [
              tokenChild,
              ConfirmationsPage(services: services),
              SettingsPage(
                controller: widget.controller,
                services: services,
                onOpenImport: _openImport,
                onAccountsChanged: () {
                  _loadAccounts(showFullPageLoading: false);
                },
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) {
          if (value == _index) return;
          HapticFeedback.selectionClick();
          setState(() => _index = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.shield_outlined),
            selectedIcon: Icon(Icons.shield_rounded),
            label: '令牌',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_rounded),
            selectedIcon: Icon(Icons.fact_check_rounded),
            label: '确认',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            selectedIcon: Icon(Icons.tune_rounded),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
