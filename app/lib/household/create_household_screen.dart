import 'dart:async';

import 'package:family_groceries/app/router.dart';
import 'package:family_groceries/design/field_border.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/household/invite_repository.dart';
import 'package:family_groceries/household/onboarding_page.dart';
import 'package:family_groceries/household/popular_stores.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/store_name_field.dart';
import 'package:family_groceries/session/session_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// The longest household name, in characters (code points, as Postgres'
/// char_length counts them).
const maxHouseholdName = 80;

/// Whether [name] is a household name the server takes: 1 to 80
/// characters once trimmed.
bool validHouseholdName(String name) {
  final length = name.trim().runes.length;
  return length >= 1 && length <= maxHouseholdName;
}

/// Onboarding Step 2a: the household's name (prefilled, editable) and its
/// stores: [popularStores] to pick, nothing picked, plus own ones typed in
/// place; "Überspringen" creates it without stores. Once the server has
/// created it the router moves on to Step 3, inviting the partner. A
/// second tap while creating does nothing; a retry after a lost answer
/// finds the household and goes on (no second one).
///
/// From the switcher ([HouseholdOrigin.switcher], job 169b) it creates one
/// more household beside the user's others, shows it, and goes on to Step 3
/// for it.
class const CreateHouseholdScreen({
  super.key,
  final HouseholdOrigin from = HouseholdOrigin.onboarding,
}) extends StatefulWidget {
  @override
  State<CreateHouseholdScreen> createState() => _CreateHouseholdScreenState();
}

class _CreateHouseholdScreenState() extends State<CreateHouseholdScreen> {
  /// Onboarding prefills the usual first name; a further household starts
  /// empty, since "Unser Haushalt" is most likely taken by the first.
  late final _name = TextEditingController(
    text: widget.from == HouseholdOrigin.switcher
        ? ''
        : AppLocalizations.of(context).householdNameDefault,
  );

  /// The stores to create, in the order picked.
  var _stores = <String>[];

  /// The own store being typed; false while the add row shows.
  var _naming = false;
  final _nameFocus = FocusNode();
  var _busy = false;
  var _invalidName = false;
  HouseholdProblem? _problem;

  @override
  void dispose() {
    _name.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  void _toggle(String store) {
    final key = nameKey(store);
    setState(
      () => _stores = _stores.any((s) => nameKey(s) == key)
          ? [..._stores.where((s) => nameKey(s) != key)]
          : [..._stores, store],
    );
  }

  /// A typed name of an offered chain ticks its chip; one already picked
  /// stays picked.
  Future<bool> _addOwn(String name) async {
    final key = nameKey(name);
    final offered = popularStores.where((p) => nameKey(p) == key);
    setState(() {
      if (!_stores.any((s) => nameKey(s) == key)) {
        _stores = [
          ..._stores,
          offered.firstOrNull ?? name.trim().replaceAll(RegExp(r'\s+'), ' '),
        ];
      }
      _naming = false;
    });
    return true;
  }

  Future<void> _create({bool skip = false}) async {
    if (_busy) {
      return;
    }
    final name = _name.text.trim();
    if (!validHouseholdName(name)) {
      setState(() => _invalidName = true);
      // Below the store choices the field may be out of view.
      _nameFocus.requestFocus();
      return;
    }
    final session = context.read<SessionCubit>();
    setState(() {
      _busy = true;
      _invalidName = false;
      _problem = null;
    });
    try {
      await session.createHousehold(
        name,
        stores: skip ? const [] : _stores,
        from: widget.from,
      );
      // Onboarding's router moves on by itself once there is a household.
      if (widget.from == HouseholdOrigin.switcher && mounted) {
        context.go(invitePartnerPath);
      }
    } on HouseholdError catch (e) {
      if (mounted) {
        setState(() => _problem = e.problem);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = HummlistColors.of(theme.brightness);
    final problem = _problem;
    final nameError = _invalidName ? l10n.householdNameInvalid : null;
    final own = [
      for (final s in _stores)
        if (!popularStores.contains(s)) s,
    ];
    return OnboardingPage(
      title: widget.from == HouseholdOrigin.switcher
          ? l10n.newHousehold
          : l10n.createHousehold,
      listKey: const ValueKey('create-household-screen'),
      onBack: _busy ? null : () => leaveStep(context),
      children: [
        LabeledField(
          label: l10n.householdName,
          field: Semantics(
            hint: nameError ?? '',
            child: TextField(
              key: const ValueKey('household-name'),
              controller: _name,
              focusNode: _nameFocus,
              autofocus: widget.from == HouseholdOrigin.switcher,
              enabled: !_busy,
              maxLength: maxHouseholdName,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                error: nameError == null ? null : FieldError(nameError),
                hintText: widget.from == HouseholdOrigin.switcher
                    ? l10n.householdNameHintFurther
                    : null,
              ),
              onSubmitted: (_) => unawaited(_create()),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(l10n.storesChoice, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(l10n.onboardingStoresHint, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 12),
        Wrap(
          key: const ValueKey('onboarding-stores'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final store in [...popularStores, ...own])
              FilterChip(
                key: ValueKey('onboarding-store-$store'),
                label: Text(store),
                // The theme's label colour is white in dark; on honey the
                // text is navy.
                labelStyle: theme.chipTheme.labelStyle?.copyWith(
                  color: _stores.contains(store) ? t.onHoney : t.text,
                ),
                selected: _stores.contains(store),
                onSelected: _busy ? null : (_) => _toggle(store),
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
                onPressed: _busy ? null : () => setState(() => _naming = true),
              ),
          ],
        ),
        if (_naming) ...[
          const SizedBox(height: 8),
          StoreNameField(
            confirmLabel: l10n.storeAddOwn,
            onConfirm: _addOwn,
            onCancel: () => setState(() => _naming = false),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          l10n.storesDisclaimer,
          key: const ValueKey('stores-disclaimer'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_invalidName)
          ProblemText(
            l10n.householdNameInvalid,
            key: const ValueKey('create-name-problem'),
          ),
        if (problem != null)
          ProblemText(
            householdProblemText(l10n, problem),
            key: const ValueKey('create-problem'),
          ),
        const SizedBox(height: 24),
        FilledButton(
          key: const ValueKey('create-household'),
          onPressed: _busy ? null : () => unawaited(_create()),
          child: _busy
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.createHousehold),
        ),
        const SizedBox(height: 8),
        TextButton(
          key: const ValueKey('skip-stores'),
          onPressed: _busy ? null : () => unawaited(_create(skip: true)),
          child: Text(l10n.skipStores),
        ),
        Text(
          l10n.skipStoresHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
