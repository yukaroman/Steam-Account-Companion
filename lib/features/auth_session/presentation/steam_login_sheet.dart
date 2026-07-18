import 'package:flutter/services.dart';
import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../design_system/app_colors.dart';
import '../../../design_system/app_spacing.dart';
import '../data/steam_login_client.dart';
import '../domain/steam_login_result.dart';

/// Bottom sheet: Steam username + password → Session tokens for confirmations.
///
/// Uses [AppServices] only — does not import secret model types.
Future<bool?> showSteamLoginSheet(
  BuildContext context, {
  required AppServices services,
  required String accountId,
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
        child: _SteamLoginSheet(
          services: services,
          accountId: accountId,
        ),
      );
    },
  );
}

class _SteamLoginSheet extends StatefulWidget {
  const _SteamLoginSheet({
    required this.services,
    required this.accountId,
  });

  final AppServices services;
  final String accountId;

  @override
  State<_SteamLoginSheet> createState() => _SteamLoginSheetState();
}

class _SteamLoginSheetState extends State<_SteamLoginSheet> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailCodeController = TextEditingController();

  SteamLoginPrefill? _prefill;
  var _loading = true;
  var _submitting = false;
  var _rememberPassword = false;
  var _obscure = true;
  String? _error;

  /// Pending email-code challenge.
  SteamSessionLoginNeedEmailCode? _emailChallenge;

  @override
  void initState() {
    super.initState();
    _loadPrefill();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _emailCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefill() async {
    try {
      final prefill = await widget.services.steamLoginPrefill(widget.accountId);
      if (!mounted) return;
      // Always write the sanitized form so the first tap matches what we send.
      _usernameController.text =
          SteamLoginClient.sanitizeSteamAccountName(prefill.username);
      if (prefill.savedPassword != null) {
        _passwordController.text =
            SteamLoginClient.sanitizeSteamPassword(prefill.savedPassword!);
        _rememberPassword = true;
      }
      setState(() {
        _prefill = prefill;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法加载账号信息';
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    // Let iOS password autofill flush into controllers after button unfocus.
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final username = SteamLoginClient.sanitizeSteamAccountName(
      _usernameController.text,
    );
    final password = SteamLoginClient.sanitizeSteamPassword(
      _passwordController.text,
    );

    // Keep the text fields in sync with what will be sent to Steam.
    if (_usernameController.text != username) {
      _usernameController.value = TextEditingValue(
        text: username,
        selection: TextSelection.collapsed(offset: username.length),
      );
    }

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = '请填写完整的 Steam 登录名和密码（不要使用昵称）');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final SteamSessionLoginOutcome outcome;
      final challenge = _emailChallenge;
      if (challenge != null) {
        outcome = await widget.services.continueSteamSessionEmailCode(
          accountId: widget.accountId,
          clientId: challenge.clientId,
          requestId: challenge.requestId,
          steamId: challenge.steamId,
          emailCode: _emailCodeController.text.trim(),
          username: username,
          password: password,
          rememberPassword: _rememberPassword,
        );
      } else {
        outcome = await widget.services.loginSteamSession(
          accountId: widget.accountId,
          username: username,
          password: password,
          rememberPassword: _rememberPassword,
        );
      }

      if (!mounted) return;

      switch (outcome) {
        case SteamSessionLoginOk():
          Navigator.of(context).pop(true);
          return;
        case SteamSessionLoginNeedEmailCode(
            :final clientId,
            :final requestId,
            :final steamId,
            :final emailHint,
          ):
          setState(() {
            _emailChallenge = SteamSessionLoginNeedEmailCode(
              clientId: clientId,
              requestId: requestId,
              steamId: steamId,
              emailHint: emailHint,
            );
            _submitting = false;
            _error = null;
          });
        case SteamSessionLoginError(:final message):
          setState(() {
            _error = message;
            _submitting = false;
          });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '登录失败，请稍后重试';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    final title = _prefill?.displayName ?? 'Steam 登录';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.pageHorizontal,
        8,
        AppSpacing.pageHorizontal,
        16 + bottom,
      ),
      child: _loading
          ? const SizedBox(
              height: 180,
              child: Center(child: CircularProgressIndicator.adaptive()),
            )
          : AutofillGroup(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '登录以启用确认',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '账号「$title」。使用 Steam 密码登录；本机会自动填写手机令牌验证码，'
                      '成功后即可查询/处理交易确认。密码默认不保存。',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AppColors.mutedText(context),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _usernameController,
                      enabled: !_submitting && _emailChallenge == null,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      inputFormatters: [
                        FilteringTextInputFormatter.deny(
                          RegExp(r'[\u200B-\u200D\u2060\uFEFF\u00A0]'),
                        ),
                      ],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Steam 用户名',
                        helperText: _usernameController.text.isEmpty
                            ? '必须是完整登录名（account_name），不是展示昵称'
                            : '提交前会自动去空格并转小写',
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) {
                        if (mounted) setState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passwordController,
                      enabled: !_submitting && _emailChallenge == null,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: _emailChallenge == null
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onSubmitted: (_) {
                        if (_emailChallenge == null) _submit();
                      },
                      decoration: InputDecoration(
                        labelText: '密码',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                    if (_emailChallenge != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _emailChallenge!.emailHint == null
                            ? 'Steam 要求邮箱验证码'
                            : '请输入发送到 ${_emailChallenge!.emailHint} 的验证码',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _emailCodeController,
                        enabled: !_submitting,
                        keyboardType: TextInputType.text,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: '邮箱验证码',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _rememberPassword,
                      onChanged: _submitting
                          ? null
                          : (v) =>
                              setState(() => _rememberPassword = v ?? false),
                      title: Text(
                        widget.services.encryptAccountsAtRest
                            ? '记住密码（加密保存在本机；取消勾选会删除已保存密码）'
                            : '记住密码（当前未开启本地加密，可能以可读形式保存；取消勾选会删除已保存密码）',
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _error!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator.adaptive(
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _emailChallenge == null ? '登录' : '提交邮箱验证码',
                            ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
