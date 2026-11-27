import 'dart:async';

import 'package:family_groceries/analytics/flags.dart';
import 'package:family_groceries/core/environment.dart';
import 'package:family_groceries/core/legal_links.dart';
import 'package:family_groceries/core/notices.dart';
import 'package:family_groceries/design/brand_block.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/status_bar_backdrop.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/paste_invite.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/session/mail_language.dart';
import 'package:family_groceries/session/provider_buttons.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:family_groceries/session/social_sign_in.dart';
import 'package:family_groceries/shell/router.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide Session;

class const LoginScreen({
  super.key,

  /// Carried through so a magic link lands back on the invite.
  final String? invite,

  /// A consent URL or an app link's location to return to after sign-in,
  /// already vetted by the router.
  final String? next,
}) extends StatefulWidget {
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState() extends State<LoginScreen> {
  /// What the invite sheet chose; today's sign-in without one.
  var _intent = SignInIntent.signIn;

  /// The invite sheet shows once per visit, also when the flag comes on
  /// after the first frame (flags arrive after the start).
  var _askedIntent = false;

  void _askIntent() {
    _askedIntent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      final intent = await showInviteSignInSheet(context);
      if (mounted && intent != null) {
        setState(() => _intent = intent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final invite = widget.invite;
    final next = widget.next;
    final l10n = AppLocalizations.of(context);
    final jh2 = context.select<Flags?, bool>(
      (f) => f?.isOn(joinHouseholdJh2Flag) ?? false,
    );
    final joinerWhy = context.select<Flags?, bool>(
      (f) => f?.isOn(joinerDirectListFlag) ?? false,
    );
    final theme = Theme.of(context);
    if (jh2 && invite != null && !_askedIntent) {
      _askIntent();
    }
    final deleted = switch (context.watch<SessionCubit>().state) {
      SignedOut(:final deleted) => deleted,
      _ => null,
    };
    final panel = SignInPanel(
      returnPath: switch (next) {
        final next? when Uri.parse(next).path == consentPath => next,
        // Back at the root, which the apps don't claim: a claimed link
        // would open the app with a code only this browser can redeem. An
        // invite comes back the same way: /join/<code> is claimed too, and
        // on the web it is the static join page (job 169b).
        final next? => Uri(
          path: '/',
          queryParameters: {'next': next},
        ).toString(),
        // Back here, not at the root, which opens the guided start (job
        // 168b): a cancelled or failed provider sign-in says so here. An
        // invite comes back at the root: /join/<code> is claimed by the
        // apps, and on the web it is the static join page (job 169b).
        null =>
          invite == null
              ? signInReturnPath
              : Uri(path: '/', queryParameters: {'invite': invite}).toString(),
      },
      intent: _intent,
      header: joinerWhy && invite != null
          ? Column(
              children: [
                const BrandBlock(),
                const SizedBox(height: HlSpace.s3),
                Text(
                  l10n.joinerAccountWhy,
                  key: const ValueKey('joiner-account-why'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: SnacklistColors.of(theme.brightness).textMuted,
                  ),
                ),
              ],
            )
          : const BrandBlock(),
      // Job 168b: back to the guided start (resumed if under way), a link
      // along (job 486); for an invite JH2's sheet asks instead. Inside the
      // form, so it never takes the form's height (a phone turned sideways).
      footer: Column(
        children: [
          if (invite == null) ...[
            TextButton(
              key: const ValueKey('login-new'),
              onPressed: () => goToStart(context),
              child: Text(l10n.loginNew),
            ),
            const SizedBox(height: HlSpace.s2),
          ],
          // JH2 (job 271) has no Einladung einfügen; the line that an
          // invite waits stays.
          if (!jh2 || invite != null) PasteInvite(waiting: invite),
        ],
      ),
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

/// What the user wants from the sign-in: an account they have (today's
/// sign-in) or a new one (job 271: the email form open, sign-up first).
enum SignInIntent() {
  signIn,
  create,
}

/// JH2's sheet over the sign-in for an invite (job 271): „Du bist in einen
/// Haushalt eingeladen“ and whether the user has an account. Null when
/// dismissed.
Future<SignInIntent?> showInviteSignInSheet(BuildContext context) =>
    showModalBottomSheet<SignInIntent>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) {
        final l10n = AppLocalizations.of(sheet);
        final theme = Theme.of(sheet);
        return SingleChildScrollView(
          key: const ValueKey('invite-sign-in-sheet'),
          padding: const EdgeInsets.all(HlSpace.s5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.jh2InvitedToHousehold,
                  style: theme.textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: HlSpace.s2),
              Text(l10n.jh2InviteSheetBody),
              const SizedBox(height: HlSpace.s5),
              FilledButton(
                key: const ValueKey('invite-sheet-create'),
                onPressed: () => Navigator.pop(sheet, SignInIntent.create),
                child: Text(l10n.jh2InviteSheetCreate),
              ),
              const SizedBox(height: HlSpace.s2),
              OutlinedButton(
                key: const ValueKey('invite-sheet-sign-in'),
                onPressed: () => Navigator.pop(sheet, SignInIntent.signIn),
                child: Text(l10n.signIn),
              ),
            ],
          ),
        );
      },
    );

/// Every sign-in method: Google, Apple, email and password, magic link.
/// Where a build offers Google or Apple, the email form waits behind
/// „Weiter mit E-Mail“: most people sign in with an account they already
/// have. The guided start's account step embeds it too, with its own
/// [returnPath].
class const SignInPanel({
  /// Where a web redirect or magic link lands after sign-in, e.g.
  /// `/?invite=ABCD2345`. The mobile apps always return through
  /// [mobileAuthCallback].
  required final String returnPath,

  /// Shown above the methods, inside the scrolling form.
  final Widget? header,

  /// Shown below the methods, inside the scrolling form.
  final Widget? footer,

  /// [SignInIntent.create]: the email form open, sign-up the first button.
  final SignInIntent intent = SignInIntent.signIn,
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
  var _autofillEnded = false;

  /// Whether the last attempt that went out was by email and password and
  /// has not failed: only that login is worth offering to save.
  var _byPassword = false;

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
  late var _emailOpen =
      widget.intent == SignInIntent.create ||
      context.read<SocialSignIn>().flows.isEmpty;

  @override
  void didUpdateWidget(SignInPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.intent == SignInIntent.create) {
      _emailOpen = true;
    }
  }

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
    _endAutofill(save: false);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Ends the fields' autofill context. Until then the web engine keeps
  /// each field left in a hidden form, email and password filled in, on
  /// every later screen, where screen readers find them (job 226). After a
  /// sign-in it ends at once, while a login field still owns the text
  /// connection: ending it later would close the next screen's field.
  void _endAutofill({required bool save}) {
    if (!_autofillEnded) {
      _autofillEnded = true;
      TextInput.finishAutofillContext(shouldSave: save);
    }
  }

  GoTrueClient get _auth => context.read<SocialSignIn>().auth;

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
      _byPassword = false;
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
      _byPassword = needsPassword;
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

  Future<void> _signUp(Map<String, Object?> mailData) {
    final l10n = AppLocalizations.of(context);
    return _runWithForm(() async {
      final res = await _auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        emailRedirectTo: _redirectTo,
        data: mailData,
      );
      return res.session == null ? l10n.signUpCheckEmail : null;
    });
  }

  Future<void> _social(SocialProvider provider) {
    // The provider's sheet or page takes over; an open keyboard would wait
    // under it and still be there after a cancel.
    FocusManager.instance.primaryFocus?.unfocus();
    _byPassword = false;
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
    // The first mail's language (supabase/templates/).
    final mailData = mailLocaleData(Localizations.localeOf(context));
    final flows = context.read<SocialSignIn>().flows;
    final signIn = _busy ? null : () => unawaited(_signIn());
    final signUp = _busy ? null : () => unawaited(_signUp(mailData));
    return BlocListener<SessionCubit, Session>(
      listenWhen: (_, session) =>
          session is NeedsHousehold || session is InHousehold,
      listener: (_, _) => _endAutofill(save: _byPassword),
      child: ConstrainedBox(
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
                ...switch (widget.intent) {
                  SignInIntent.signIn => [
                    FilledButton(onPressed: signIn, child: Text(l10n.signIn)),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: signUp, child: Text(l10n.signUp)),
                  ],
                  SignInIntent.create => [
                    FilledButton(onPressed: signUp, child: Text(l10n.signUp)),
                    const SizedBox(height: 8),
                    OutlinedButton(onPressed: signIn, child: Text(l10n.signIn)),
                  ],
                },
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => unawaited(
                          _runWithForm(() async {
                            await _auth.signInWithOtp(
                              email: _email.text.trim(),
                              emailRedirectTo: _redirectTo,
                              // Only a new account takes it; mails to an
                              // existing one use its saved language.
                              data: mailData,
                            );
                            return l10n.magicLinkSent;
                          }, needsPassword: false),
                        ),
                  child: Text(l10n.sendMagicLink),
                ),
              ],
              if (widget.footer case final footer?) ...[
                const SizedBox(height: HlSpace.s4),
                footer,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
