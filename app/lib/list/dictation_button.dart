import 'dart:async';

import 'package:family_groceries/l10n/app_localizations.dart';
import 'package:family_groceries/list/dictation.dart';
import 'package:family_groceries/list/list_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

/// The microphone in the add bar: fills [input] while the user speaks, then
/// adds what the server's splitter makes of the sentence. On failure the
/// text stays in the field. [onMessage] shows what happened.
class const DictationButton({
  required final Dictation dictation,
  required final TextEditingController input,
  required final ValueChanged<String> onMessage,

  /// Listening started (true) or ended (false).
  required final ValueChanged<bool> onListening,

  /// Back to typing once a sentence was handled.
  required final VoidCallback onDone,
  super.key,
}) extends StatefulWidget {
  @override
  State<DictationButton> createState() => _DictationButtonState();
}

/// Where the button is in one sentence. A tap starts one when [idle] and
/// stops it when [listening]; otherwise it does nothing, so a second tap
/// while the recognizer gets ready or the server splits starts no second
/// session.
enum _Phase() {
  idle,
  preparing,
  listening,
  adding,
}

class _DictationButtonState() extends State<DictationButton> {
  var _phase = _Phase.idle;

  void _enter(_Phase phase) {
    final listening = phase == _Phase.listening;
    final wasListening = _phase == _Phase.listening;
    setState(() => _phase = phase);
    if (listening != wasListening) {
      widget.onListening(listening);
    }
  }

  Future<void> _dictate() async {
    switch (_phase) {
      case _Phase.listening:
        await widget.dictation.stop();
        return;
      case _Phase.preparing || _Phase.adding:
        return;
      case _Phase.idle:
        try {
          await _sentence();
        } finally {
          if (mounted) {
            _enter(_Phase.idle);
          }
        }
    }
  }

  Future<void> _sentence() async {
    final dictation = widget.dictation;
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ListCubit>();
    final language = SpokenLanguage.of(Localizations.localeOf(context));
    _enter(_Phase.preparing);
    if (await dictation.prepare(language) case final problem?) {
      if (mounted) {
        widget.onMessage(_problem(l10n, problem));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    _enter(_Phase.listening);
    final dictated = await dictation.listen(
      onWords: (words) => widget.input.text = words,
    );
    if (!mounted) {
      return;
    }
    _enter(_Phase.adding);
    final String text;
    switch (dictated) {
      case Heard(text: final heard):
        text = heard;
      case NothingHeard():
        widget.onMessage(l10n.dictationNothingHeard);
        return;
      case Refused(:final problem):
        widget.onMessage(_problem(l10n, problem));
        return;
    }
    try {
      final (:results, :truncated) = await cubit.addSpoken(text, language);
      if (!mounted) {
        return;
      }
      if (results.isEmpty) {
        widget.onMessage(l10n.dictationNothingUnderstood);
      } else {
        widget.input.clear();
        widget.onMessage(
          [
            _summary(l10n, results),
            if (truncated) l10n.dictationTooMany,
          ].join(' '),
        );
      }
    } on Exception {
      if (mounted) {
        widget.onMessage(l10n.dictationSplitFailed);
      }
    }
    widget.onDone();
  }

  static String _problem(AppLocalizations l10n, DictationProblem problem) =>
      switch (problem) {
        DictationProblem.unavailable => l10n.dictationUnavailable,
        DictationProblem.noOfflineSpeech => l10n.dictationNoOfflineSpeech,
        DictationProblem.offlineSpeechDownloading =>
          l10n.dictationOfflineSpeechDownloading,
      };

  static String _summary(AppLocalizations l10n, List<AddResult> results) {
    final added = [
      for (final result in results)
        if (result case Added(:final item))
          // As Siri reads an add back: "Windeln Pampers Größe 3, Big Pack".
          [?item.quantity, item.name, ?item.brand, ?item.properties].join(' '),
    ];
    final existing = [
      for (final result in results)
        if (result case AlreadyOnList(:final item)) item.name,
    ];
    return [
      if (added.isNotEmpty) l10n.dictationAdded(added.join(', ')),
      if (existing.isNotEmpty) l10n.dictationAlreadyOnList(existing.join(', ')),
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final listening = _phase == _Phase.listening;
    return IconButton(
      key: const ValueKey('dictation-button'),
      tooltip: listening ? l10n.dictationStop : l10n.dictationStart,
      icon: Icon(listening ? Icons.stop_circle : Icons.mic),
      color: listening ? Theme.of(context).colorScheme.error : null,
      onPressed: () => unawaited(_dictate()),
    );
  }
}
