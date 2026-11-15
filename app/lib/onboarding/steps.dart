import 'dart:async';

import 'package:family_groceries/analytics/consent_screen.dart';
import 'package:family_groceries/app/legal_links.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/household_kind.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/household/popular_stores.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_name_field.dart';
import 'package:family_groceries/onboarding/draft.dart';
import 'package:family_groceries/onboarding/invite_step.dart';
import 'package:family_groceries/onboarding/onboarding_cubit.dart';
import 'package:family_groceries/onboarding/onboarding_frame.dart';
import 'package:family_groceries/session/login_screen.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The longest household name, in characters (code points, as Postgres'
/// char_length counts them).
const maxHouseholdName = 80;

/// Whether [name] is a household name the server takes: 1 to 80
/// characters once trimmed.
bool validHouseholdName(String name) {
  final length = name.trim().runes.length;
  return length >= 1 && length <= maxHouseholdName;
}

/// The screen of the guided start's [step].
Widget onboardingStepScreen(OnboardingStep step) => _SignedInBackStays(
  child: switch (step) {
    OnboardingStep.usage => const _UsageStep(),
    OnboardingStep.who => const _WhoStep(),
    OnboardingStep.name => const _NameStep(),
    OnboardingStep.stores => const _StoresStep(),
    OnboardingStep.need => const _NeedStep(),
    OnboardingStep.account => const _AccountStep(),
    OnboardingStep.setup => const _SetupStep(),
    OnboardingStep.invite => const InviteStep(),
  },
);

/// Android's back on a step without Zurück: signed out to the first
/// screen, the route under every step. Signed in, that screen („Schon ein
/// Konto? Anmelden“) is not theirs, and a pop runs no redirect, so back
/// stays on the step.
class const _SignedInBackStays({required final Widget child})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: context.watch<SessionCubit>().state is SignedOut,
    child: child,
  );
}

/// The words of [kind] on its chip.
String kindLabel(AppLocalizations l10n, HouseholdKind kind) => switch (kind) {
  HouseholdKind.partner => l10n.kindPartner,
  HouseholdKind.family => l10n.kindFamily,
  HouseholdKind.flat => l10n.kindFlat,
  HouseholdKind.club => l10n.kindClub,
  HouseholdKind.solo => l10n.kindSolo,
  HouseholdKind.other => l10n.kindOther,
};

/// The household name the answers suggest: one per kind, „Andere“ its own
/// words.
String suggestedHouseholdName(AppLocalizations l10n, OnboardingDraft draft) =>
    switch (draft.kind) {
      HouseholdKind.family => l10n.householdNameFamily,
      HouseholdKind.flat => l10n.householdNameFlat,
      HouseholdKind.club => l10n.householdNameClub,
      HouseholdKind.solo => l10n.householdNameSolo,
      HouseholdKind.other when validHouseholdName(draft.otherKind) =>
        draft.otherKind.trim(),
      HouseholdKind.partner ||
      HouseholdKind.other ||
      null => l10n.householdNameDefault,
    };

/// The draft under way; the router shows no step without one.
OnboardingDraft _draft(BuildContext context) =>
    context.watch<OnboardingCubit>().state ?? const OnboardingDraft();

/// „Weiter“ and, below it, „Überspringen“ as an equal button, not a grey
/// link (good friction: skipping is a real choice).
class const _NextAndSkip({
  required final String nextLabel,
  required final VoidCallback? onNext,
  final VoidCallback? onSkip,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: HlSpace.s2,
    children: [
      FilledButton(
        key: const ValueKey('onboarding-next'),
        onPressed: onNext,
        child: Text(nextLabel),
      ),
      if (onSkip != null)
        OutlinedButton(
          key: const ValueKey('onboarding-skip'),
          onPressed: onSkip,
          child: Text(AppLocalizations.of(context).onboardingSkip),
        ),
    ],
  );
}

/// The usage-data question, with the consent screen's exact words. The
/// router moves on to „Mit wem“ once the answer is stored.
class const _UsageStep() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const OnboardingStepPage(
    step: OnboardingStep.usage,
    children: [ConsentQuestion()],
  );
}

/// „Mit wem kaufst du ein?“: any number of kinds, „Andere“ with a field.
/// The first pick becomes the household; the others are kept for when a
/// user can have several (job 169).
class const _WhoStep() extends StatefulWidget {
  @override
  State<_WhoStep> createState() => _WhoStepState();
}

class _WhoStepState() extends State<_WhoStep> {
  late final TextEditingController _other;

  @override
  void initState() {
    super.initState();
    _other = TextEditingController(
      text: context.read<OnboardingCubit>().state?.otherKind ?? '',
    );
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  void _toggle(HouseholdKind kind) => context.read<OnboardingCubit>().update(
    (d) => d.copyWith(
      kinds: d.kinds.contains(kind)
          ? [...d.kinds.where((k) => k != kind)]
          : [...d.kinds, kind],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final draft = _draft(context);
    final onboarding = context.read<OnboardingCubit>();
    return OnboardingStepPage(
      step: OnboardingStep.who,
      title: l10n.whoTitle,
      children: [
        Text(l10n.whoBody),
        const SizedBox(height: HlSpace.s4),
        Wrap(
          key: const ValueKey('onboarding-kinds'),
          spacing: HlSpace.s2,
          runSpacing: HlSpace.s2,
          children: [
            for (final kind in HouseholdKind.values)
              FilterChip(
                key: ValueKey('onboarding-kind-${kind.name}'),
                label: Text(kindLabel(l10n, kind)),
                labelStyle: theme.chipTheme.labelStyle?.copyWith(
                  color: draft.kinds.contains(kind) ? t.onHoney : t.text,
                ),
                selected: draft.kinds.contains(kind),
                onSelected: (_) => _toggle(kind),
              ),
          ],
        ),
        if (draft.kinds.contains(HouseholdKind.other)) ...[
          const SizedBox(height: HlSpace.s4),
          LabeledField(
            label: l10n.whoOtherLabel,
            field: TextField(
              autofillHints: null,
              key: const ValueKey('onboarding-kind-other-text'),
              controller: _other,
              maxLength: maxHouseholdName,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: l10n.whoOtherHint),
              onChanged: (text) =>
                  onboarding.update((d) => d.copyWith(otherKind: text)),
            ),
          ),
        ],
        if (draft.kinds.length > 1) ...[
          const SizedBox(height: HlSpace.s3),
          Text(
            l10n.whoSeveral(kindLabel(l10n, draft.kinds.first)),
            key: const ValueKey('onboarding-kinds-several'),
            style: theme.textTheme.bodySmall?.copyWith(color: t.textMuted),
          ),
        ],
        const SizedBox(height: HlSpace.s5),
        _NextAndSkip(
          nextLabel: l10n.onboardingNext,
          onNext: draft.kinds.isEmpty
              ? null
              : () => onboarding.at(OnboardingStep.name),
          onSkip: () => onboarding.update(
            (d) => d.copyWith(
              kinds: const [],
              otherKind: '',
              step: OnboardingStep.name,
            ),
          ),
        ),
      ],
    );
  }
}

/// The household name, prefilled from „Mit wem“.
class const _NameStep() extends StatefulWidget {
  @override
  State<_NameStep> createState() => _NameStepState();
}

class _NameStepState() extends State<_NameStep> {
  late final TextEditingController _name;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Once: the suggestion needs the localizations, which initState can't
    // read.
    if (!_named) {
      _named = true;
      _name = TextEditingController(
        text: switch (context.read<OnboardingCubit>().state) {
          final draft? =>
            draft.name ??
                suggestedHouseholdName(AppLocalizations.of(context), draft),
          null => '',
        },
      );
    }
  }

  var _named = false;
  var _invalid = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _next() {
    if (!validHouseholdName(_name.text)) {
      setState(() => _invalid = true);
      return;
    }
    context.read<OnboardingCubit>().update(
      (d) => d.copyWith(
        name: () => _name.text.trim(),
        step: OnboardingStep.stores,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return OnboardingStepPage(
      step: OnboardingStep.name,
      title: l10n.nameTitle,
      back: OnboardingStep.who,
      children: [
        Text(l10n.nameBody),
        const SizedBox(height: HlSpace.s4),
        LabeledField(
          label: l10n.householdName,
          // The error as the field's hint too: on the web a merged label
          // would read it into the name (job 154b's pattern).
          field: Semantics(
            hint: _invalid ? l10n.householdNameInvalid : '',
            child: TextField(
              autofillHints: null,
              key: const ValueKey('household-name'),
              controller: _name,
              maxLength: maxHouseholdName,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                error: _invalid ? FieldError(l10n.householdNameInvalid) : null,
              ),
              onChanged: (text) {
                if (_invalid) {
                  setState(() => _invalid = false);
                }
                context.read<OnboardingCubit>().update(
                  (d) => d.copyWith(name: () => text),
                );
              },
              onSubmitted: (_) => _next(),
            ),
          ),
        ),
        const SizedBox(height: HlSpace.s5),
        _NextAndSkip(nextLabel: l10n.onboardingNext, onNext: _next),
      ],
    );
  }
}

/// The stores: [popularStores] to pick, nothing picked, plus own ones typed
/// in place. „Überspringen“ starts without stores.
class const _StoresStep() extends StatefulWidget {
  @override
  State<_StoresStep> createState() => _StoresStepState();
}

class _StoresStepState() extends State<_StoresStep> {
  /// The own store being typed.
  var _naming = false;

  void _toggle(String store) {
    final key = nameKey(store);
    context.read<OnboardingCubit>().update(
      (d) => d.copyWith(
        stores: d.stores.any((s) => nameKey(s) == key)
            ? [...d.stores.where((s) => nameKey(s) != key)]
            : [...d.stores, store],
      ),
    );
  }

  /// A typed name of an offered chain ticks its chip; one already picked
  /// stays picked.
  Future<bool> _addOwn(String name) async {
    final key = nameKey(name);
    final offered = popularStores(AppLocalizations.of(context))
        .where((p) => nameKey(p) == key);
    context.read<OnboardingCubit>().update(
      (d) => d.stores.any((s) => nameKey(s) == key)
          ? d
          : d.copyWith(
              stores: [
                ...d.stores,
                offered.firstOrNull ??
                    name.trim().replaceAll(RegExp(r'\s+'), ' '),
              ],
            ),
    );
    setState(() => _naming = false);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final stores = _draft(context).stores;
    final onboarding = context.read<OnboardingCubit>();
    final own = [
      for (final s in stores)
        if (!popularStores(l10n).contains(s)) s,
    ];
    return OnboardingStepPage(
      step: OnboardingStep.stores,
      title: l10n.storesStepTitle,
      back: OnboardingStep.name,
      children: [
        Text(l10n.onboardingStoresHint),
        const SizedBox(height: HlSpace.s3),
        Wrap(
          key: const ValueKey('onboarding-stores'),
          spacing: HlSpace.s2,
          runSpacing: HlSpace.s2,
          children: [
            for (final store in [...popularStores(l10n), ...own])
              FilterChip(
                key: ValueKey('onboarding-store-$store'),
                label: Text(store),
                // The theme's label colour is white in dark; on honey the
                // text is navy.
                labelStyle: theme.chipTheme.labelStyle?.copyWith(
                  color: stores.contains(store) ? t.onHoney : t.text,
                ),
                selected: stores.contains(store),
                onSelected: (_) => _toggle(store),
              ),
            if (!_naming)
              // A button, not an ActionChip: Flutter web names a chip a
              // check box.
              TextButton.icon(
                key: const ValueKey('onboarding-store-own'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, HlSize.target),
                ),
                icon: const Icon(Icons.add),
                label: Text(l10n.storeAddOwn),
                onPressed: () => setState(() => _naming = true),
              ),
          ],
        ),
        if (_naming) ...[
          const SizedBox(height: HlSpace.s2),
          StoreNameField(
            confirmLabel: l10n.storeAddOwn,
            onConfirm: _addOwn,
            onCancel: () => setState(() => _naming = false),
          ),
        ],
        const SizedBox(height: HlSpace.s3),
        Text(
          l10n.storesDisclaimer,
          key: const ValueKey('stores-disclaimer'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: HlSpace.s5),
        _NextAndSkip(
          nextLabel: l10n.onboardingNext,
          onNext: () => onboarding.at(OnboardingStep.need),
          onSkip: () => onboarding.update(
            (d) => d.copyWith(stores: const [], step: OnboardingStep.need),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: HlSpace.s2),
          child: Text(
            l10n.skipStoresHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// „Was fehlt gerade?“: staple chips and a field for anything else. All of
/// it goes on the real list once the household exists.
class const _NeedStep() extends StatefulWidget {
  @override
  State<_NeedStep> createState() => _NeedStepState();
}

class _NeedStepState() extends State<_NeedStep> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  Timer? _refocus;

  @override
  void dispose() {
    _refocus?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Adds what was typed and keeps the field ready for the next item. On
  /// web the add button's tap and Enter (the "done" action) both blur the
  /// field's input while Flutter keeps the field focused, so requestFocus
  /// alone does nothing, and since Flutter 3.50 the input then stopped
  /// reaching the app (job 201). A fresh focus gives it back after the
  /// engine's blur, as ListScreen does after a tap outside its field.
  void _add() {
    context.read<OnboardingCubit>().addItem(_field.text);
    _field.clear();
    if (!kIsWeb) {
      _focus.requestFocus();
      return;
    }
    _focus.unfocus();
    _refocus?.cancel();
    _refocus = Timer(const Duration(milliseconds: 50), () {
      if (mounted) {
        _focus.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = SnacklistColors.of(theme.brightness);
    final items = _draft(context).items;
    final onboarding = context.read<OnboardingCubit>();
    final signedIn = context.watch<SessionCubit>().state is! SignedOut;
    final staples = [
      for (final s in l10n.needStaples.split(','))
        if (s.trim().isNotEmpty) s.trim(),
    ];
    return OnboardingStepPage(
      step: OnboardingStep.need,
      title: l10n.needTitle,
      back: OnboardingStep.stores,
      children: [
        Text(l10n.needBody),
        const SizedBox(height: HlSpace.s4),
        Wrap(
          key: const ValueKey('onboarding-staples'),
          spacing: HlSpace.s2,
          runSpacing: HlSpace.s2,
          children: [
            for (final staple in staples)
              FilterChip(
                key: ValueKey('onboarding-staple-$staple'),
                label: Text(staple),
                labelStyle: theme.chipTheme.labelStyle?.copyWith(
                  color: onboarding.hasItem(staple) ? t.onHoney : t.text,
                ),
                selected: onboarding.hasItem(staple),
                onSelected: (on) => on
                    ? onboarding.addItem(staple)
                    : onboarding.removeItem(staple),
              ),
          ],
        ),
        const SizedBox(height: HlSpace.s4),
        LabeledField(
          label: l10n.needFieldLabel,
          field: TextField(
            autofillHints: null,
            key: const ValueKey('onboarding-need-field'),
            controller: _field,
            focusNode: _focus,
            // An item's name takes 120 characters (`items.name`); no counter.
            inputFormatters: [LengthLimitingTextInputFormatter(120)],
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: l10n.needFieldHint,
              suffixIcon: IconButton(
                key: const ValueKey('onboarding-need-add'),
                tooltip: l10n.needAdd,
                icon: const Icon(Icons.add),
                onPressed: _add,
              ),
            ),
            onSubmitted: (_) => _add(),
          ),
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: HlSpace.s4),
          Text(
            l10n.needListTitle(items.length),
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: HlSpace.s2),
          Wrap(
            key: const ValueKey('onboarding-need-items'),
            spacing: HlSpace.s2,
            runSpacing: HlSpace.s2,
            children: [
              for (final item in items)
                // A plain chip, not an input: no "disabled" for screen readers.
                Chip(
                  key: ValueKey('onboarding-need-item-${item.text}'),
                  label: Text(item.text),
                  deleteButtonTooltipMessage: l10n.needRemove(item.text),
                  onDeleted: () => onboarding.removeItem(item.text),
                ),
            ],
          ),
        ],
        const SizedBox(height: HlSpace.s5),
        _NextAndSkip(
          nextLabel: l10n.needNext(items.length),
          // Signed in already (a household created from „Willkommen“): no
          // account step.
          onNext: () => onboarding.at(
            signedIn ? OnboardingStep.setup : OnboardingStep.account,
          ),
        ),
      ],
    );
  }
}

/// The account, as late as it can be: the household must exist with a real
/// user before anyone can be invited. Every sign-in method of the sign-in
/// screen; once signed in the router sets the household up.
class const _AccountStep() extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    void back() => context.read<OnboardingCubit>().at(OnboardingStep.need);
    // Android's back too, as on the other steps ([OnboardingPage]); popped,
    // it showed the first screen.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          back();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(onboardingProgressText(context, OnboardingStep.account)),
          automaticallyImplyLeading: false,
          leading: BackButton(onPressed: back),
          actions: const [OnboardingExitButton()],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: SignInPanel(
                    key: const ValueKey('onboarding-account'),
                    // Back at the root, where the router finds the draft
                    // (a web sign-in reloads the page, the apps return through
                    // their callback).
                    returnPath: '/',
                    header: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const OnboardingProgress(step: OnboardingStep.account),
                        const SizedBox(height: HlSpace.s5),
                        OnboardingHeading(l10n.accountStepTitle),
                        const SizedBox(height: HlSpace.s3),
                        Text(l10n.accountStepBody),
                      ],
                    ),
                  ),
                ),
              ),
              const LegalFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Signed in: the draft becomes the household (created, kind set, items
/// added). A failure shows with a retry; the router moves on once the draft
/// is set up.
class const _SetupStep() extends StatefulWidget {
  @override
  State<_SetupStep> createState() => _SetupStepState();
}

class _SetupStepState() extends State<_SetupStep> {
  HouseholdProblem? _problem;
  var _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Future<void> _run() async {
    if (_running || !mounted) {
      return;
    }
    final onboarding = context.read<OnboardingCubit>();
    final draft = onboarding.state;
    if (draft == null) {
      return;
    }
    setState(() {
      _running = true;
      _problem = null;
    });
    try {
      await onboarding.setUp(
        context.read<SessionCubit>(),
        context.read<OnboardingBackend>(),
        defaultName: suggestedHouseholdName(
          AppLocalizations.of(context),
          draft,
        ),
      );
    } on HouseholdError catch (e) {
      if (mounted) {
        setState(() => _problem = e.problem);
      }
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final problem = _problem;
    return OnboardingPage(
      title: l10n.appTitle,
      listKey: const ValueKey('onboarding-setup'),
      actions: const [OnboardingExitButton()],
      children: [
        OnboardingHeading(l10n.setupBusy),
        const SizedBox(height: HlSpace.s5),
        if (problem == null)
          const Center(child: CircularProgressIndicator())
        else ...[
          ProblemText(
            householdProblemText(l10n, problem),
            key: const ValueKey('onboarding-setup-problem'),
          ),
          const SizedBox(height: HlSpace.s4),
          FilledButton(
            key: const ValueKey('onboarding-setup-retry'),
            onPressed: _running ? null : () => unawaited(_run()),
            child: Text(l10n.retry),
          ),
        ],
      ],
    );
  }
}
