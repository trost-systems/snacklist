import 'dart:async';

import 'package:family_groceries/design/motion.dart';
import 'package:family_groceries/design/tokens.g.dart';
import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:family_groceries/list/model.dart';
import 'package:family_groceries/list/retailer.dart';
import 'package:material_ui/material_ui.dart';

/// What a store picker needs to offer chains for a new store (job 313):
/// the matches for a typed name, a store created linked to a chain, and the
/// answer to „Ist das REWE?“ once a plain name is saved.
@immutable
class const StoreChains({
  required final Future<List<RetailerMatch>> Function(String name) match,
  required final Future<Store?> Function(String name, Retailer retailer)
  addLinked,
  required final Future<bool> Function(String storeId, Retailer retailer) link,
  required final Future<bool> Function(String storeId) decline,
}) {
  factory of(ListCubit cubit) => StoreChains(
    match: cubit.matchRetailers,
    addLinked: (name, retailer) => cubit.addStore(name, retailer: retailer),
    link: cubit.linkStore,
    decline: cubit.declineStore,
  );

  /// Answers the question about [storeId]: linked to [chain], or never asked
  /// again when null.
  Future<bool> answer(String storeId, Retailer? chain) => switch (chain) {
    final chain? => link(storeId, chain),
    null => decline(storeId),
  };
}

/// The chains a saved name names („Lidl“, „Lidl am Markt“), not those it
/// only begins: the question after saving a plain name asks about these.
List<Retailer> exactChains(List<RetailerMatch> matches) => [
  for (final m in matches)
    if (m.exact) m.retailer,
];

/// How long typing pauses before the chains are looked up.
const chainSuggestionDelay = Duration(milliseconds: 250);

/// At most this many chains show under the field.
const _shown = 3;

/// The chains matching [text] under a new store's name field: from two
/// letters, once typing pauses, up to three rows with the chain's name, its
/// country and its app. A tap hands the match to [onPick]. Nothing shows
/// while offline or when nothing matches: typing goes on as without it.
class const ChainSuggestions({
  required final String text,
  required final Future<List<RetailerMatch>> Function(String name) match,
  required final ValueChanged<RetailerMatch> onPick,
  super.key,
}) extends StatefulWidget {
  @override
  State<ChainSuggestions> createState() => _ChainSuggestionsState();
}

class _ChainSuggestionsState() extends State<ChainSuggestions> {
  Timer? _wait;
  var _rows = const <RetailerMatch>[];

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ChainSuggestions old) {
    super.didUpdateWidget(old);
    if (old.text.trim() != widget.text.trim()) {
      _schedule();
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  void _schedule() {
    _wait?.cancel();
    final query = widget.text.trim();
    if (query.length < 2) {
      if (_rows.isNotEmpty) {
        setState(() => _rows = const []);
      }
      return;
    }
    _wait = Timer(chainSuggestionDelay, () async {
      final rows = await widget.match(query);
      // A later letter asked again meanwhile: its answer shows.
      if (mounted && widget.text.trim() == query) {
        setState(() => _rows = rows.take(_shown).toList());
      }
    });
  }

  @override
  Widget build(BuildContext context) => _rows.isEmpty
      // Not an empty Column: its spacing makes a negative intrinsic size
      // in a scrollable AlertDialog.
      ? const SizedBox.shrink()
      : ComesIntoView(
          key: ValueKey([for (final m in _rows) m.retailer.key].join()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: HlSpace.s2,
            children: [
              for (final m in _rows)
                _Suggestion(
                  key: ValueKey(
                    'chain-suggestion-'
                    '${m.retailer.chain}-${m.retailer.country}',
                  ),
                  retailer: m.retailer,
                  onTap: () => widget.onPick(m),
                ),
            ],
          ),
        );
}

/// Scrolls [child] into view in the scrollable around it once it appears:
/// in the add sheet's details (a steady three-row area) the chains and the
/// question would otherwise land under the add field. Key it by its content
/// to scroll again when that changes.
class const ComesIntoView({required final Widget child, super.key})
    extends StatefulWidget {
  @override
  State<ComesIntoView> createState() => _ComesIntoViewState();
}

class _ComesIntoViewState() extends State<ComesIntoView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Scrollable.ensureVisible(
          context,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: hlMotion(context, HlDuration.medium),
          curve: HlEasing.standard,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A chain to pick: its name over its country, its app trailing; one button
/// for screen readers („REWE (Deutschland) wählen“). Plain text and a
/// neutral icon, no logo.
class const _Suggestion({
  required final Retailer retailer,
  required final VoidCallback onTap,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = SnacklistColors.of(Theme.of(context).brightness);
    final text = Theme.of(context).textTheme;
    final country = l10n.countryName(retailer.country);
    final app = retailer.apps.firstOrNull;
    // Its own node: otherwise the button's label and tap go up to the node
    // around it, and the name field above becomes a child of the button
    // (the onboarding store step, job 321).
    return Semantics(
      container: true,
      button: true,
      label: l10n.chainSuggestionPick(retailer.name, country),
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: t.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HlRadius.s),
          side: BorderSide(color: t.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: HlSize.target),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HlSpace.s3,
                vertical: HlSpace.s2,
              ),
              child: Row(
                spacing: HlSpace.s3,
                children: [
                  Icon(Icons.storefront_outlined, color: t.textMuted),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          retailer.name,
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        // The app under the country, not beside the name:
                        // large text keeps a whole line for each.
                        Wrap(
                          spacing: HlSpace.s3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              country,
                              style: text.bodySmall?.copyWith(
                                color: t.textMuted,
                              ),
                            ),
                            if (app != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                spacing: HlSpace.s1,
                                children: [
                                  Icon(
                                    Icons.open_in_new,
                                    size: 14,
                                    color: t.accent,
                                  ),
                                  Flexible(
                                    child: Text(
                                      app.name,
                                      style: text.bodySmall?.copyWith(
                                        color: t.accent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
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
