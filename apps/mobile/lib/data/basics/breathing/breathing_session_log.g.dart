// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'breathing_session_log.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The session log bound to the current account's journal.

@ProviderFor(breathingSessionLog)
final breathingSessionLogProvider = BreathingSessionLogProvider._();

/// The session log bound to the current account's journal.

final class BreathingSessionLogProvider
    extends
        $FunctionalProvider<
          AsyncValue<BreathingSessionLog>,
          BreathingSessionLog,
          FutureOr<BreathingSessionLog>
        >
    with
        $FutureModifier<BreathingSessionLog>,
        $FutureProvider<BreathingSessionLog> {
  /// The session log bound to the current account's journal.
  BreathingSessionLogProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'breathingSessionLogProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$breathingSessionLogHash();

  @$internal
  @override
  $FutureProviderElement<BreathingSessionLog> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<BreathingSessionLog> create(Ref ref) {
    return breathingSessionLog(ref);
  }
}

String _$breathingSessionLogHash() =>
    r'7e31de009419ec1329d84c7f222a298da3e6e64a';
