import 'package:flutter/material.dart';

import '../../../app/app_controller.dart';
import '../../../app/app_services.dart';
import '../../../design_system/app_colors.dart';
import '../../../design_system/app_panel.dart';
import '../../../design_system/app_spacing.dart';
import '../../../design_system/page_header.dart';
import '../../backup/presentation/backup_flow.dart';
import '../data/theme_preferences.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.controller,
    this.services,
    this.onOpenImport,
    this.onAccountsChanged,
    super.key,
  });

  final AppController controller;
  final AppServices? services;
  final VoidCallback? onOpenImport;

  /// Called after backup restore so token list can refresh.
  final VoidCallback? onAccountsChanged;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _motion = true;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final faceId = widget.controller.faceIdEnabled;
        final autoLock = widget.controller.autoLock;
        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            const PageHeader(
              title: '设置',
              subtitle: '安全、外观与数据',
            ),
            const SizedBox(height: 12),
            _sectionLabel(context, '安全'),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pageHorizontal),
              child: AppPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _SwitchRow(
                      icon: Icons.lock_rounded,
                      iconColor: AppColors.success,
                      title: '本地加密存储',
                      subtitle: widget.controller.encryptAccountsAtRest
                          ? '账号载荷使用 AES-GCM 加密保存（默认开启）'
                          : '已关闭：账号以本地明文 JSON 存储（不推荐）',
                      value: widget.controller.encryptAccountsAtRest,
                      onChanged: widget.controller.encryptToggleBusy
                          ? null
                          : (value) async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await widget.controller
                                    .setEncryptAccountsAtRest(value);
                              } catch (_) {
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('加密设置未能完整保存，已恢复为实际存储状态'),
                                  ),
                                );
                              }
                            },
                    ),
                    const _Divider(),
                    _SwitchRow(
                      icon: Icons.face_rounded,
                      iconColor: AppColors.cyan,
                      title: '系统身份验证门禁',
                      subtitle: faceId
                          ? '已开：冷启动与自动锁后需 Face ID / 指纹 / 设备密码；验证失败保持锁定'
                          : '默认关；开启后冷启动需系统身份验证（不可用时不会无认证放行）',
                      value: faceId,
                      onChanged: (value) =>
                          widget.controller.setFaceIdEnabled(value),
                    ),
                    const _Divider(),
                    _ActionRow(
                      icon: Icons.timer_outlined,
                      iconColor: AppColors.blue,
                      title: '自动锁定',
                      subtitle: !faceId
                          ? '需先开启 Face ID；未开启时仅「立即锁定」会进入解锁页'
                          : autoLock == ThemePreferences.autoLockNever
                              ? 'Face ID 已开：冷启动要解；切后台回来永不自动锁'
                              : autoLock == ThemePreferences.autoLockImmediate
                                  ? '切到后台后，回来立刻需要解锁'
                                  : '默认较长：离开超过 $autoLock 再回来才需要解锁',
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: autoLock,
                          borderRadius: BorderRadius.circular(16),
                          items: ThemePreferences.autoLockOptions
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(value),
                                ),
                              )
                              .toList(),
                          onChanged: faceId
                              ? (value) {
                                  if (value != null) {
                                    widget.controller.setAutoLock(value);
                                  }
                                }
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            _sectionLabel(context, '外观'),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pageHorizontal),
              child: AppPanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('主题', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('系统'),
                            icon: Icon(Icons.phone_iphone_rounded, size: 16),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('深色'),
                            icon: Icon(Icons.dark_mode_rounded, size: 16),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('浅色'),
                            icon: Icon(Icons.light_mode_rounded, size: 16),
                          ),
                        ],
                        selected: {widget.controller.themeMode},
                        showSelectedIcon: false,
                        onSelectionChanged: (values) {
                          widget.controller.setThemeMode(values.first);
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary:
                          _iconBubble(Icons.contrast_rounded, AppColors.slate),
                      title: const Text('OLED 纯黑模式'),
                      subtitle: const Text('仅在深色主题下生效 · 会记住你的选择'),
                      value: widget.controller.oledMode,
                      onChanged: (value) {
                        widget.controller.setOledMode(value);
                      },
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary:
                          _iconBubble(Icons.animation_rounded, AppColors.blue),
                      title: const Text('界面动画'),
                      value: _motion,
                      onChanged: (value) => setState(() => _motion = value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            _sectionLabel(context, '数据'),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pageHorizontal),
              child: AppPanel(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    _ActionRow(
                      icon: Icons.file_download_outlined,
                      iconColor: AppColors.success,
                      title: '导入账号',
                      subtitle: 'maFile / JSON · 本地解析',
                      onTap: () {
                        if (widget.onOpenImport != null) {
                          widget.onOpenImport!();
                          return;
                        }
                        _notReady('账号导入');
                      },
                    ),
                    const _Divider(),
                    _ActionRow(
                      icon: Icons.lock_rounded,
                      iconColor: AppColors.warning,
                      title: '导出加密备份',
                      subtitle: '口令加密 .sacbak · 可换机拷贝',
                      onTap: () {
                        final services = widget.services;
                        if (services == null) {
                          _notReady('加密备份');
                          return;
                        }
                        BackupFlow.exportBackup(context, services: services);
                      },
                    ),
                    const _Divider(),
                    _ActionRow(
                      icon: Icons.settings_backup_restore_rounded,
                      iconColor: AppColors.violet,
                      title: '从备份恢复',
                      subtitle: '选择 .sacbak · 合并到本机',
                      onTap: () {
                        final services = widget.services;
                        if (services == null) {
                          _notReady('备份恢复');
                          return;
                        }
                        BackupFlow.restoreBackup(
                          context,
                          services: services,
                          onRestored: widget.onAccountsChanged,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.pageHorizontal),
              child: OutlinedButton.icon(
                key: const Key('settings-lock-button'),
                onPressed: widget.controller.lock,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  foregroundColor: AppColors.danger,
                  side: BorderSide(
                      color: AppColors.danger.withValues(alpha: 0.35)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  ),
                ),
                icon: const Icon(Icons.lock_outline_rounded),
                label: const Text('立即锁定'),
              ),
            ),
            const SizedBox(height: 24),
            _sectionLabel(context, '关于'),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.pageHorizontal,
              ),
              child: AppPanel(
                padding: EdgeInsets.zero,
                child: _ActionRow(
                  icon: Icons.code_rounded,
                  iconColor: AppColors.blue,
                  title: '开源许可',
                  subtitle: 'GNU GPL v3.0 · 第三方组件许可',
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Steam Account Companion',
                    applicationVersion: '0.1.0',
                    applicationLegalese: '© 2026 yukaroman\n'
                        'GNU General Public License v3.0\n\n'
                        '非官方第三方项目，与 Valve Corporation 或 Steam '
                        '不存在隶属、赞助或认可关系。',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Steam Account Companion 0.1.0 · GPLv3\n'
              '本地优先 · 非官方 Steam 第三方项目',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.mutedText(context),
                    height: 1.6,
                  ),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageHorizontal,
        0,
        AppSpacing.pageHorizontal,
        10,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppColors.mutedText(context),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
      ),
    );
  }

  Widget _iconBubble(IconData icon, Color color) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }

  void _notReady(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature服务暂不可用，请重启应用后重试')),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ??
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.mutedText(context),
          ),
      onTap: onTap,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 68, endIndent: 16);
  }
}
