import 'dart:async';

import 'package:family_groceries/app/environment.dart';
import 'package:family_groceries/app/legal_links.dart';
import 'package:family_groceries/app/notices.dart';
import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/design/brand_block.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/status_bar_backdrop.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/provider_buttons.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class const LoginScreen({
  super.key,

  /// Carried through so a magic link lands back on the invite.
  final String? invite,

  /// A consent URL or an app link's location to return to after sign-in,
  /// already vetted by the router.
  final String? next,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final invite = this.invite;
    final l10n = AppLocalizations.of(context);
    final deleted = switch (context.watch<SessionCubit>().state) {
      SignedOut(:final deleted) => deleted,
      _ => null,
    };
    final panel = SignInPanel(
      returnPath: switch (next) {
        final next? when Uri.parse(next).path == consentPath => next,
        // Back at the root, which the apps don't claim: a claimed link
        // would open the app with a code only this browser can redeem.
        final next? => Uri(
          path: '/',
          queryParameters: {'next': next},
        ).toString(),
        null => invite == null ? '/' : '/join/$invite',
      },
      header: const BrandBlock(),
    );
    return Scaffold(
      body: StatusBarBackdrop(
        fade: HlSpace.s7,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (deleted != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Card(
                    key: const ValueKey('account-deleted-notice'),
                    margin: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: ListTile(
                      leading: const Icon(Icons.check_circle_outline),
                      title: Text(l10n.accountDeletedNotice),
                      subtitle: deleted.removeAppleManually
                          ? Text(l10n.accountDeletedApple)
                          : null,
                    ),
                  ),
                ),
              Expanded(child: Center(child: panel)),
              // Outside the scrolling form: visible without scrolling.
              const SafeArea(top: false, child: LegalFooter()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Every sign-in method: Google, Apple, email and password, magic link.
/// Where a build offers Google or Apple, the email form waits behind
/// „Weiter mit E-Mail“: most people sign in with an account they already
/// have. The MCP consent page embeds it too, with its own [returnPath].
class const SignInPanel({
  /// Where a web redirect or magic link lands after sign-in, e.g.
  /// `/join/ABCD2345`. The mobile apps always return through
  /// [mobileAuthCallback].
  required final String returnPath,

  /// Shown above the methods, inside the scrolling form.
  final Widget? header,
  super.key,
}) extends StatefulWidget {
  @override
  State<SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState() extends State<SignInPanel> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _busy = false;
  var _passwordRequired = true;

  /// The errors the last submit showed, kept as the fields' semantics hints:
  /// an error widget, unlike `errorText`, does not set them.
  String? _emailError;
  String? _passwordError;

  String? _emailProblem(String? v) => (v ?? '').trim().contains('@')
      ? null
      : AppLocalizations.of(context).invalidEmail;

  String? _passwordProblem(String? v) =>
      !_passwordRequired || (v ?? '').length >= 6
      ? null
      : AppLocalizations.of(context).passwordTooShort;
  late var _emailOpen = context.read<SocialSignIn>().flows.isEmpty;

  @override
  void initState() {
    super.initState();
    if (context.read<SessionCubit>().state case SignedOut(:final error?)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _report(error);
        }
      });
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  GoTrueClient get _auth => Supabase.instance.client.auth;

  String get _redirectTo =>
      kIsWeb ? '$webRoot${widget.returnPath}' : mobileAuthCallback;

  void _report(Object error) {
    final l10n = AppLocalizations.of(context);
    final message = switch (error) {
      SocialSignInCanceled() ||
      AuthException(code: 'access_denied') => l10n.signInCanceled,
      AuthException(:final message) => l10n.authFailed(message),
      _ => l10n.authFailed('$error'),
    };
    Notices.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Runs an auth call; a returned message is shown to the user.
  Future<void> _run(Future<String?> Function() action) async {
    final messenger = Notices.of(context);
    setState(() => _busy = true);
    try {
      if (await action() case final message?) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } on Exception catch (e) {
      if (mounted) {
        _report(e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _runWithForm(
    Future<String?> Function() action, {
    bool needsPassword = true,
  }) async {
    _passwordRequired = needsPassword;
    final valid = _form.currentState!.validate();
    setState(() {
      _emailError = _emailProblem(_email.text);
      _passwordError = _passwordProblem(_password.text);
    });
    if (valid) {
      await _run(action);
    }
  }

  Future<void> _signIn() => _runWithForm(() async {
    await _auth.signInWithPassword(
      email: _email.text.trim(),
      password: _password.text,
    );
    return null;
  });

  Future<void> _social(SocialProvider provider) {
    // The provider's sheet or page takes over; an open keyboard would wait
    // under it and still be there after a cancel.
    FocusManager.instance.primaryFocus?.unfocus();
    return _run(() async {
      await context.read<SocialSignIn>().signIn(
        provider,
        redirectTo: _redirectTo,
      );
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final flows = context.read<SocialSignIn>().flows;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(24),
          shrinkWrap: true,
          children: [
            if (widget.header case final header?) ...[
              header,
              const SizedBox(height: HlSpace.s5),
            ],
            if (flows.containsKey(SocialProvider.google)) ...[
              GoogleSignInButton(
                key: const ValueKey('sign-in-google'),
                label: l10n.signInWithGoogle,
                onPressed: _busy
                    ? null
                    : () => unawaited(_social(SocialProvider.google)),
              ),
              const SizedBox(height: 12),
            ],
            if (flows.containsKey(SocialProvider.apple)) ...[
              AppleSignInButton(
                key: const ValueKey('sign-in-apple'),
                label: l10n.signInWithApple,
                onPressed: _busy
                    ? null
                    : () => unawaited(_social(SocialProvider.apple)),
              ),
              const SizedBox(height: 12),
            ],
            if (!_emailOpen)
              EmailSignInButton(
                key: const ValueKey('sign-in-email'),
                label: l10n.continueWithEmail,
                onPressed: _busy
                    ? null
                    : () => setState(() => _emailOpen = true),
              )
            else ...[
              if (flows.isNotEmpty) ...[
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(l10n.orWithEmail),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              LabeledField(
                label: l10n.email,
                field: Semantics(
                  hint: _emailError ?? '',
                  child: TextFormField(
                    key: const ValueKey('login-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    errorBuilder: (_, error) => FieldError(error),
                    validator: _emailProblem,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              LabeledField(
                label: l10n.password,
                field: Semantics(
                  hint: _passwordError ?? '',
                  child: TextFormField(
                    key: const ValueKey('login-password'),
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    errorBuilder: (_, error) => FieldError(error),
                    validator: _passwordProblem,
                    onFieldSubmitted: (_) => unawaited(_signIn()),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : () => unawaited(_signIn()),
                child: Text(l10n.signIn),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _runWithForm(() async {
                          final res = await _auth.signUp(
                            email: _email.text.trim(),
                            password: _password.text,
                            emailRedirectTo: _redirectTo,
                          );
                          return res.session == null
                              ? l10n.signUpCheckEmail
                              : null;
                        }),
                      ),
                child: Text(l10n.signUp),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _runWithForm(() async {
                          await _auth.signInWithOtp(
                            email: _email.text.trim(),
                            emailRedirectTo: _redirectTo,
                          );
                          return l10n.magicLinkSent;
                        }, needsPassword: false),
                      ),
                child: Text(l10n.sendMagicLink),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
