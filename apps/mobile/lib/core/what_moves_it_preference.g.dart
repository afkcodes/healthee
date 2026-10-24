// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'what_moves_it_preference.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Open or shut. Closed until the stored choice has been read.

@ProviderFor(WhatMovesItOpen)
final whatMovesItOpenProvider = WhatMovesItOpenProvider._();

/// Open or shut. Closed until the stored choice has been read.
final class WhatMovesItOpenProvider
    extends $NotifierProvider<WhatMovesItOpen, bool> {
  /// Open or shut. Closed until the stored choice has been read.
  WhatMovesItOpenProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'whatMovesItOpenProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$whatMovesItOpenHash();

  @$internal
  @override
  WhatMovesItOpen create() => WhatMovesItOpen();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }
}

String _$whatMovesItOpenHash() => r'c65c20b3400ced387437d21308f24d77b5c35bb3';

/// Open or shut. Closed until the stored choice has been read.

abstract class _$WhatMovesItOpen extends $Notifier<bool> {
  bool build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
