import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/security/biometric_service.dart';
import '../../../design_system/app_colors.dart';
import '../../../design_system/app_spacing.dart';

class UnlockPage extends StatefulWidget {
  const UnlockPage({
    required this.onUnlocked,
    this.faceIdEnabled = false,
    this.biometricService,
    super.key,
  });

  final VoidCallback onUnlocked;

  /// When true, require system authentication (Face ID / fingerprint / device
  /// credential via [biometricService]). No unauthenticated tap-through.
  final bool faceIdEnabled;

  /// Required for Face ID gate on non-web platforms.
  final BiometricService? biometricService;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage>
    with SingleTickerProviderStateMixin {
  bool _authenticating = false;
  String? _statusHint;
  late final AnimationController _pulseController;
  var _autoPrompted = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_autoPrompted || !widget.faceIdEnabled || kIsWeb) return;
      final biometric = widget.biometricService;
      if (biometric == null) return;
      final available = await biometric.isAvailable;
      if (!available || !mounted || _autoPrompted) return;
      _autoPrompted = true;
      await _unlock(preferBiometric: true);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _unlock({bool preferBiometric = true}) async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _statusHint = null;
    });
    HapticFeedback.mediumImpact();

    // Manual lock without Face ID gate, or web: short delay then enter.
    if (!widget.faceIdEnabled || kIsWeb) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) widget.onUnlocked();
      return;
    }

    final biometric = widget.biometricService;
    if (biometric == null) {
      if (!mounted) return;
      setState(() {
        _authenticating = false;
        _statusHint = '系统身份验证不可用 · 请稍后重试或在设置中关闭门禁';
      });
      return;
    }

    final available = await biometric.isAvailable;
    if (!available) {
      if (!mounted) return;
      setState(() {
        _authenticating = false;
        _statusHint = '本机未录入 Face ID / 指纹，或系统验证暂不可用 · 保持锁定';
      });
      return;
    }

    if (!preferBiometric) {
      // Should not happen for Face ID gate; keep locked.
      if (mounted) {
        setState(() {
          _authenticating = false;
          _statusHint = '请使用系统身份验证解锁';
        });
      }
      return;
    }

    final result = await biometric.authenticate(
      reason: '解锁 Steam Companion',
    );
    if (!mounted) return;
    switch (result) {
      case BiometricResult.authenticated:
        widget.onUnlocked();
        return;
      case BiometricResult.cancelled:
        setState(() {
          _authenticating = false;
          _statusHint = '已取消 · 可再点下方按钮重试';
        });
        return;
      case BiometricResult.unavailable:
        setState(() {
          _authenticating = false;
          _statusHint = '系统身份验证不可用 · 保持锁定';
        });
        return;
      case BiometricResult.failed:
        setState(() {
          _authenticating = false;
          _statusHint = '验证失败 · 可再试一次';
        });
        return;
    }
  }

  String get _buttonLabel {
    if (_authenticating) return '正在验证…';
    if (!widget.faceIdEnabled) return '轻点解锁';
    if (kIsWeb) return '轻点解锁';
    return '使用系统身份验证';
  }

  String get _unlockHint {
    if (_statusHint != null) return _statusHint!;
    if (!widget.faceIdEnabled) {
      return '已手动锁定 · 轻点后继续';
    }
    if (kIsWeb) {
      return '浏览器无法调用系统 Face ID · 轻点即可进入';
    }
    return '将调用系统 Face ID / 指纹 / 设备密码 · 验证失败保持锁定';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: dark
                ? const [
                    Color(0xFF07090E),
                    Color(0xFF0C1524),
                    Color(0xFF12101C),
                  ]
                : const [
                    Color(0xFFF7F9FF),
                    Color(0xFFEAF1FF),
                    Color(0xFFF3EEFF),
                  ],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -40,
              left: -30,
              child: _AmbientOrb(
                size: 220,
                color: AppColors.cyan.withValues(alpha: dark ? 0.18 : 0.12),
              ),
            ),
            Positioned(
              top: 120,
              right: -50,
              child: _AmbientOrb(
                size: 260,
                color: AppColors.violet.withValues(alpha: dark ? 0.16 : 0.1),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 40,
              child: _AmbientOrb(
                size: 180,
                color: AppColors.blue.withValues(alpha: dark ? 0.12 : 0.08),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final scale = 1 + (_pulseController.value * 0.04);
                        final glow = 0.22 + (_pulseController.value * 0.14);
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 112,
                            height: 112,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppColors.brandGradient,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.blue.withValues(alpha: glow),
                                  blurRadius: 54,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: child,
                          ),
                        );
                      },
                      child: Icon(
                        widget.faceIdEnabled && !kIsWeb
                            ? Icons.face_retouching_natural_rounded
                            : Icons.shield_rounded,
                        size: 54,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 34),
                    Text(
                      'Steam Companion',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontSize: 30,
                                letterSpacing: -1.1,
                              ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '你的令牌与确认请求，只属于你。',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                dark ? AppColors.slate : AppColors.slateLight,
                            height: 1.5,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const Spacer(flex: 4),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                        gradient:
                            _authenticating ? null : AppColors.brandGradient,
                        boxShadow: _authenticating
                            ? null
                            : [
                                BoxShadow(
                                  color: AppColors.blue.withValues(alpha: 0.28),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                      ),
                      child: FilledButton.icon(
                        key: const Key('unlock-button'),
                        onPressed: _authenticating ? null : () => _unlock(),
                        style: FilledButton.styleFrom(
                          backgroundColor: _authenticating
                              ? AppColors.elevatedHigh
                              : Colors.transparent,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: Colors.white70,
                          shadowColor: Colors.transparent,
                          surfaceTintColor: Colors.transparent,
                        ),
                        icon: _authenticating
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                widget.faceIdEnabled && !kIsWeb
                                    ? Icons.face_rounded
                                    : Icons.lock_open_rounded,
                              ),
                        label: Text(_buttonLabel),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _unlockHint,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.slate,
                            letterSpacing: 0.1,
                          ),
                    ),
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

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
