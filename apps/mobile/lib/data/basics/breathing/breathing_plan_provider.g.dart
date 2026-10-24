// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'breathing_plan_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The plan. Rebuilds when settings or the snapshot change; invalidate it
/// after a sync to re-read the store.

@ProviderFor(breathingPlan)
final breathingPlanProvider = BreathingPlanProvider._();

/// The plan. Rebuilds when settings or the snapshot change; invalidate it
/// after a sync to re-read the store.

final class BreathingPlanProvider
    extends
        $FunctionalProvider<
          AsyncValue<BreathingPlan>,
          BreathingPlan,
          FutureOr<BreathingPlan>
        >
    with $FutureModifier<BreathingPlan>, $FutureProvider<BreathingPlan> {
  /// The plan. Rebuilds when settings or the snapshot change; invalidate it
  /// after a sync to re-read the store.
  BreathingPlanProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'breathingPlanProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$breathingPlanHash();

  @$internal
  @override
  $FutureProviderElement<BreathingPlan> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<BreathingPlan> create(Ref ref) {
    return breathingPlan(ref);
  }
}

String _$breathingPlanHash() => r'aad81d688807bbdcffe60ada3c139b701e9e5ab5';

/// Changes that also move the reminders.

@ProviderFor(BreathingActions)
final breathingActionsProvider = BreathingActionsProvider._();

/// Changes that also move the reminders.
final class BreathingActionsProvider
    extends $NotifierProvider<BreathingActions, void> {
  /// Changes that also move the reminders.
  BreathingActionsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'breathingActionsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$breathingActionsHash();

  @$internal
  @override
  BreathingActions create() => BreathingActions();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$breathingActionsHash() => r'10646be9eea8a2fc9c1159703cb2d852eae0ea7d';

/// Changes that also move the reminders.

abstract class _$BreathingActions extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
