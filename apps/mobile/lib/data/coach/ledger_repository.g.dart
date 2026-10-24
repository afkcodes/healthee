// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ledger_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ledgerRepository)
final ledgerRepositoryProvider = LedgerRepositoryProvider._();

final class LedgerRepositoryProvider
    extends
        $FunctionalProvider<
          AsyncValue<LedgerRepository>,
          LedgerRepository,
          FutureOr<LedgerRepository>
        >
    with $FutureModifier<LedgerRepository>, $FutureProvider<LedgerRepository> {
  LedgerRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ledgerRepositoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ledgerRepositoryHash();

  @$internal
  @override
  $FutureProviderElement<LedgerRepository> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<LedgerRepository> create(Ref ref) {
    return ledgerRepository(ref);
  }
}

String _$ledgerRepositoryHash() => r'227382c4b6d7128b9743277c88d5ebf83ba9b015';

@ProviderFor(coachLedger)
final coachLedgerProvider = CoachLedgerFamily._();

final class CoachLedgerProvider
    extends
        $FunctionalProvider<
          AsyncValue<CoachLedger>,
          CoachLedger,
          FutureOr<CoachLedger>
        >
    with $FutureModifier<CoachLedger>, $FutureProvider<CoachLedger> {
  CoachLedgerProvider._({
    required CoachLedgerFamily super.from,
    required LedgerWindow super.argument,
  }) : super(
         retry: null,
         name: r'coachLedgerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$coachLedgerHash();

  @override
  String toString() {
    return r'coachLedgerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<CoachLedger> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<CoachLedger> create(Ref ref) {
    final argument = this.argument as LedgerWindow;
    return coachLedger(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CoachLedgerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$coachLedgerHash() => r'752ecc858a5e3dedc76b70bbb13bee09900ab11c';

final class CoachLedgerFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<CoachLedger>, LedgerWindow> {
  CoachLedgerFamily._()
    : super(
        retry: null,
        name: r'coachLedgerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CoachLedgerProvider call(LedgerWindow window) =>
      CoachLedgerProvider._(argument: window, from: this);

  @override
  String toString() => r'coachLedgerProvider';
}
