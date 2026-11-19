import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// An exception of the app's own that names itself in error reports, so
/// analytics needs no import of the feature that throws it.
abstract interface class ReportedError() implements Exception {
  /// The type's name; release web builds minify `runtimeType`.
  String get typeName;

  /// A code that says what went wrong, never a value the user typed.
  String get code;
}

/// The error's type for `$exception_list`. Release web builds minify type
/// names (`minified:hm`), so the common ones are named here.
String errorType(Object error) => switch (error) {
  StateError() => 'StateError',
  IndexError() => 'IndexError',
  RangeError() => 'RangeError',
  ArgumentError() => 'ArgumentError',
  TypeError() => 'TypeError',
  NoSuchMethodError() => 'NoSuchMethodError',
  UnimplementedError() => 'UnimplementedError',
  UnsupportedError() => 'UnsupportedError',
  ConcurrentModificationError() => 'ConcurrentModificationError',
  StackOverflowError() => 'StackOverflowError',
  OutOfMemoryError() => 'OutOfMemoryError',
  FlutterError() => 'FlutterError',
  AssertionError() => 'AssertionError',
  FormatException() => 'FormatException',
  TimeoutException() => 'TimeoutException',
  PostgrestException() => 'PostgrestException',
  AuthException() => 'AuthException',
  FunctionException() => 'FunctionException',
  ReportedError(:final typeName) => typeName,
  _ => _runtimeName(error),
};

String _runtimeName(Object error) {
  final name = '${error.runtimeType}';
  return name.isEmpty ? 'Error' : name;
}

/// What may be said about [error] without personal data or list content.
///
/// Errors the Dart runtime and Flutter raise themselves (type errors,
/// ranges, null checks, bad states, layout) keep the shape of their first
/// line: anything quoted, any e-mail address, URL, UUID or number replaced,
/// and every word outside the runtime's own templates ([_templateWords])
/// reduced to `<w>`, so `cannot parse Hafermilch` reads `cannot <w>`.
/// Everything else (a server error echoing a value, a
/// format error quoting its input, an exception of the app's own) keeps
/// only a code that looks like one (`invalid_invite`, `23505`) or nothing.
String scrubMessage(Object error) {
  if (!_runtimeError(error)) {
    final code = _codeOf(error);
    return code != null && _codeLike.hasMatch(code) ? code : '<redacted>';
  }
  final text = error is FlutterError ? error.message : error.toString();
  final firstLine = text.split('\n').first;
  return _clip(_shape(_scrub(firstLine)), 120);
}

/// Errors whose message the runtime or the framework writes. App code can
/// raise a `StateError` with its own text too, so the text is scrubbed all
/// the same.
bool _runtimeError(Object error) =>
    error is TypeError ||
    error is RangeError ||
    error is NoSuchMethodError ||
    error is StateError ||
    error is UnsupportedError ||
    error is ConcurrentModificationError ||
    error is StackOverflowError ||
    error is OutOfMemoryError ||
    error is AssertionError ||
    error is FlutterError ||
    error is TimeoutException;

/// The code a server or library error carries beside its message.
String? _codeOf(Object error) => switch (error) {
  PostgrestException(:final code) => code,
  AuthException(:final code, :final statusCode) => code ?? statusCode,
  FunctionException(:final status) => '$status',
  ReportedError(:final code) => code,
  _ => null,
};

final _codeLike = RegExp(r'^[A-Za-z0-9_.:-]{1,64}$');

final _quoted = RegExp(
  '''"[^"]*"|'[^']*'|„[^“”]*[“”]|“[^”]*”|‘[^’]*’|«[^»]*»|`[^`]*`''',
);
final _email = RegExp(r'[^\s@]+@[^\s@]+');
final _url = RegExp(r'[a-z][a-z0-9+.-]*://[^\s]+', caseSensitive: false);
final _uuid = RegExp(
  '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
  caseSensitive: false,
);
final _longNumber = RegExp('[0-9]{6,}');

String _scrub(String text) => text
    .replaceAll(_url, '<url>')
    .replaceAll(_email, '<email>')
    .replaceAll(_quoted, '<redacted>')
    .replaceAll(_uuid, '<uuid>')
    .replaceAll(_longNumber, '<n>');

/// Words of the Dart runtime's and Flutter's own error templates, the same
/// list as the edge functions' `telemetry.ts` plus Dart's and Flutter's.
/// Any other word came from a value (an item, a name, a key).
final _templateWords = {
  ...'''
  a abort aborted access already an and argument arguments array assignment
  async at await been before between bigint body bounds buffer call called
  cannot character class code column constant constructor convert create date
  decode declared deep defined detached digits element empty encode end error
  exceeded expected explicit expression extensible failed fetch field flags
  fraction frozen function generator getter has in index initial
  initialization input instance invalid is iterable iterator json keyword left
  length line literal locked malformed maximum member method missing mix mode
  must network new non not null number object of offset on only or out
  position precision primitive private promise properties property radix range
  read reading recursion redefine reduce regular request reserved response
  right sealed set setter setting side size stack strict stream string super
  symbol the this time timed to token too type types undefined unexpected
  unterminated uri use used valid value variable with without writable
  '''
      .split(_space),
  // Dart and Flutter.
  ...'''
  after assertion bad be bottom by calling cast check completed concurrent
  during elements fixed for from future inclusive initialized iteration late
  less list many memory modification no operation operator overflow
  overflowed pixels rangeerror receiver renderflex should state subtype than
  top tried unmodifiable unsupported was
  '''
      .split(_space),
}..remove('');

final _space = RegExp(r'\s+');
final _word = RegExp(
  r'<[a-z]+>|[\p{L}\p{N}_$]+(?:\.[\p{L}\p{N}_$]+)*',
  unicode: true,
);
final _marker = RegExp(r'^<(?:url|email|redacted|uuid|n)>$');
final _numeric = RegExp(r'^\p{N}+(?:\.\p{N}+)*$', unicode: true);
final _wordRun = RegExp(r'<w>(?:\s*<w>)+');

/// [text] with numbers as `<n>` and words outside [_templateWords] as
/// `<w>`, a run of them collapsed into one.
String _shape(String text) => text
    .replaceAllMapped(
      _word,
      (match) => switch (match[0]!) {
        final marker when _marker.hasMatch(marker) => marker,
        final number when _numeric.hasMatch(number) => '<n>',
        final word when _templateWords.contains(word.toLowerCase()) => word,
        _ => '<w>',
      },
    )
    .replaceAll(_wordRun, '<w>');

String _clip(String text, int max) =>
    text.length <= max ? text : text.substring(0, max);

/// One `$exception_list` item as posthog_flutter built it, reduced to what
/// may be sent: [report]'s scrubbed type and message ([errorType],
/// [scrubMessage]) for the error itself, the first item; `<redacted>` for a
/// cause, which has no report. Frames keep code locations only: a device
/// path or a web URL keeps its file name.
Map<String, Object> scrubException(
  Map<Object?, Object?> item,
  Map<String, Object>? report,
) {
  final mechanism = item['mechanism'];
  final threadId = item['thread_id'];
  return {
    'type': report?['type'] ?? _text(item['type']) ?? 'Error',
    'value': report?['value'] ?? '<redacted>',
    'mechanism': {
      'type': _text(mechanism is Map ? mechanism['type'] : null) ?? 'generic',
      'handled':
          report?['handled'] ??
          (mechanism is Map && mechanism['handled'] == true),
      'synthetic': mechanism is Map && mechanism['synthetic'] == true,
    },
    if (item['stacktrace'] case {'frames': final List<Object?> frames})
      'stacktrace': {
        'type': 'raw',
        'frames': [
          for (final frame in frames)
            if (frame is Map) _frame(frame),
        ],
      },
    if (threadId is int) 'thread_id': threadId,
  };
}

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? _clip(value, 200) : null;

const _frameKeys = {
  'platform',
  'abs_path',
  'filename',
  'function',
  'module',
  'package',
  'lineno',
  'colno',
  'in_app',
  'synthetic',
  'chunk_id',
  'lang',
  'instruction_addr',
  'image_addr',
};

Map<String, Object> _frame(Map<Object?, Object?> frame) => {
  for (final MapEntry(:key, :value) in frame.entries)
    if (key is String && _frameKeys.contains(key) && value != null)
      key: key == 'abs_path' && value is String ? _location(value) : value,
};

/// A `dart:` or `package:` location as it is, any other its file name.
String _location(String path) {
  final uri = Uri.tryParse(path);
  if (uri == null) {
    return '';
  }
  if (uri.scheme == 'dart' || uri.scheme == 'package' || !path.contains('/')) {
    return path;
  }
  return uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
}
