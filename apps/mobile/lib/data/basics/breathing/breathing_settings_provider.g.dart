// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'breathing_settings_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Reads and writes [BreathingSettings].

@ProviderFor(BreathingSettingsController)
final breathingSettingsControllerProvider =
    BreathingSettingsControllerProvider._();

/// Reads and writes [BreathingSettings].
final class BreathingSettingsControllerProvider
    extends
        $AsyncNotifierProvider<BreathingSettingsController, BreathingSettings> {
  /// Reads and writes [BreathingSettings].
  BreathingSettingsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'breathingSettingsControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$breathingSettingsControllerHash();

  @$internal
  @override
  BreathingSettingsController create() => BreathingSettingsController();
}

String _$breathingSettingsControllerHash() =>
    r'23069972be188cd2c029444ef0114166d08723bc';

/// Reads and writes [BreathingSettings].

abstract class _$BreathingSettingsController
    extends $AsyncNotifier<BreathingSettings> {
  FutureOr<BreathingSettings> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<BreathingSettings>, BreathingSettings>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<BreathingSettings>, BreathingSettings>,
              AsyncValue<BreathingSettings>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
