/// The sheet behind "change": a stepper for the owner's own glass count.
///
/// No advice beyond one honest line. The app never says how much to drink.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/water/water_format.dart';
import 'package:healthee/data/basics/water/water_settings.dart';
import 'package:healthee/data/basics/water/water_settings_provider.dart';
import 'package:healthee/shared/sheets/app_sheet.dart';
import 'package:healthee/shared/v02/buttons.dart';

/// The one line the sheet says about the number.
const String kWaterTargetNote =
    'Pick your own number. There is no one right amount.';

/// Opens the sheet starting from [current].
Future<void> showWaterTargetSheet(BuildContext context, int current) =>
    showAppSheet<void>(
      context: context,
      builder: (context) => _Sheet(current: current),
    );

class _Sheet extends ConsumerStatefulWidget {
  const _Sheet({required this.current});

  final int current;

  @override
  ConsumerState<_Sheet> createState() => _SheetState();
}

class _SheetState extends ConsumerState<_Sheet> {
  late int _glasses = widget.current;
  String? _error;
  bool _saving = false;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      await ref.read(waterSettingsProvider.notifier).setGlasses(_glasses);
      if (mounted) navigator.pop();
    } on Object catch (error, stack) {
      AppLog.failure('water', 'saving the glass count', error, stack);
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save your number. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.sheet),
        ),
        border: Border.all(color: colors.line),
      ),
      padding: EdgeInsets.fromLTRB(22, 12, 22, 24 + sheetBottomInset(context)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.line,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
              ),
            ),
            const SizedBox(height: Insets.xl),
            Text(
              'Glasses a day',
              style: TypeLadder.title2.copyWith(color: colors.ink),
            ),
            const SizedBox(height: Insets.xs),
            Text(
              kWaterTargetNote,
              style: TypeLadder.callout.copyWith(color: colors.ink2),
            ),
            const SizedBox(height: Insets.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  tooltip: 'Fewer glasses',
                  onPressed: _glasses > kMinGlasses
                      ? () => setState(() => _glasses--)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                ),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          '$_glasses ${_glasses == 1 ? 'glass' : 'glasses'}',
                          style: TypeLadder.title1.copyWith(color: colors.ink),
                        ),
                      ),
                      Text(
                        '${groupedMl(_glasses * kGlassMl)} ml',
                        style: TypeLadder.callout.copyWith(color: colors.ink2),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'More glasses',
                  onPressed: _glasses < kMaxGlasses
                      ? () => setState(() => _glasses++)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                ),
              ],
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: Insets.sm),
              Text(
                _error!,
                style: TypeLadder.callout.copyWith(color: colors.ink),
              ),
            ],
            const SizedBox(height: Insets.lg),
            HButton(label: 'Save', onPressed: _saving ? null : _save),
          ],
        ),
      ),
    );
  }
}
