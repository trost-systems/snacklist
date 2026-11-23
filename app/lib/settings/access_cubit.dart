import 'package:family_groceries/settings/access_repository.dart';
import 'package:family_groceries/siri/siri_channel.dart';
import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_bloc/flutter_bloc.dart';

/// One independently loaded section of the screen.
sealed class const Section<T>();

final class const SectionLoading<T>() extends Section<T>;

final class const SectionLoaded<T>(final T value) extends Section<T>;

final class const SectionFailed<T>(final String message) extends Section<T>;

@immutable
class const AccessState({
  final Section<List<AccessToken>> tokens = const SectionLoading(),
  final Section<List<ConnectedApp>> apps = const SectionLoading(),

  /// The Siri credential in this iPhone's keychain, which the list calls
  /// "this iPhone".
  final String? siriHere,

  /// Job 397: the server makes keys for the MCP server and the API alike.
  final bool unified = false,
});

class AccessCubit(
  final AccessRepository _repo, {

  /// This iPhone's Siri; null elsewhere.
  final SiriChannel? siri,
}) extends Cubit<AccessState> {
  this : super(const AccessState());

  Future<void> load() =>
      Future.wait([_loadTokens(), _loadApps(), _loadSiri(), _loadUnified()]);

  /// Throws [AccessError], e.g. `too_many_tokens`.
  Future<NewToken> create(String name) async {
    final token = await _repo.createToken(name);
    await _loadTokens();
    return token;
  }

  /// Throws [AccessError], e.g. `too_many_tokens` or `session_required`.
  Future<NewToken> createApi(String name, ApiScopes scopes) async {
    final token = await _repo.createApiToken(name, scopes);
    await _loadTokens();
    return token;
  }

  Future<void> revoke(String id) async {
    await _repo.revokeToken(id);
    await _loadTokens();
  }

  Future<void> disconnect(String clientId) async {
    await _repo.disconnect(clientId);
    await _loadApps();
  }

  Future<void> _loadTokens() async {
    final tokens = await _section(_repo.fetchTokens);
    if (!isClosed) {
      emit(
        AccessState(
          tokens: tokens,
          apps: state.apps,
          siriHere: state.siriHere,
          unified: state.unified,
        ),
      );
    }
  }

  Future<void> _loadApps() async {
    final apps = await _section(_repo.fetchApps);
    if (!isClosed) {
      emit(
        AccessState(
          tokens: state.tokens,
          apps: apps,
          siriHere: state.siriHere,
          unified: state.unified,
        ),
      );
    }
  }

  Future<void> _loadSiri() async {
    final String? id;
    try {
      id = (await siri?.read())?.id;
    } on Object {
      // No channel or no keychain: every Siri row is another iPhone's.
      return;
    }
    if (!isClosed && id != null) {
      emit(
        AccessState(
          tokens: state.tokens,
          apps: state.apps,
          siriHere: id,
          unified: state.unified,
        ),
      );
    }
  }

  Future<void> _loadUnified() async {
    final unified = await _repo.unifiedKeys();
    if (!isClosed && unified) {
      emit(
        AccessState(
          tokens: state.tokens,
          apps: state.apps,
          siriHere: state.siriHere,
          unified: true,
        ),
      );
    }
  }

  static Future<Section<T>> _section<T>(Future<T> Function() fetch) async {
    try {
      return SectionLoaded(await fetch());
    } on Object catch (e) {
      return SectionFailed(e is AccessError ? e.code : '$e');
    }
  }
}
