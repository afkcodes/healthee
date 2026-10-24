/// A small sheet for the owner's own counts: in, hold, out, hold.
///
/// The steppers stop at the pattern's own limits, so what can be set is what
/// `BreathPattern.validateCustom` accepts. Saving still goes through the
/// settings controller, and its refusal is shown rather than dropped.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/shapes.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_settings_provider.dart';
import 'package:healthee/features/coach/v02/breathing_ink_button.dart';
import 'package:healthee/features/coach/v02/breathing_run.dart';
import 'package:healthee/shared/sheets/app_sheet.dart';

/// Opens the editor, starting from [current] when there is one.
Future<void> showBreathingCustomEditor(
  BuildContext context,
  BreathPattern? current,
) => showAppSheet<void>(
  context: context,
  builder: (_) => _Editor(start: current),
);

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.start});

  final BreathPattern? start;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late int _in = widget.start?.inSeconds ?? 4;
  late int _hold1 = widget.start?.hold1Seconds ?? 0;
  late int _out = widget.start?.outSeconds ?? 6;
  late int _hold2 = widget.start?.hold2Seconds ?? 0;
  String? _problem;

  Future<void> _save() async {
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(breathingSettingsControllerProvider.notifier)
          .setCustom(
            inSeconds: _in,
            hold1Seconds: _hold1,
            outSeconds: _out,
            hold2Seconds: _hold2,
          );
    } on FormatException catch (error) {
      setState(() => _problem = error.message);
      return;
    }
    if (mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        Insets.card,
        Insets.card,
        Insets.card,
        Insets.card + sheetBottomInset(context),
      ),
      decoration: ShapeDecoration(
        color: colors.surface,
        shape: hSquircle(Radii.sheet),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Custom pattern',
              style: TypeLadder.title2.copyWith(color: colors.ink),
            ),
            const SizedBox(height: Insets.xs),
            Text(
              'Breathing in and out take 1 to 12 seconds. Holds take 0 to 12.',
              style: TypeLadder.callout.copyWith(color: colors.ink2),
            ),
            const SizedBox(height: Insets.md),
            _Stepper('Breathe in', _in, 1, (v) => setState(() => _in = v)),
            _Stepper('Hold', _hold1, 0, (v) => setState(() => _hold1 = v)),
            _Stepper('Breathe out', _out, 1, (v) => setState(() => _out = v)),
            _Stepper(
              'Hold after out',
              _hold2,
              0,
              (v) => setState(() => _hold2 = v),
            ),
            if (_problem case final String problem)
              Padding(
                padding: const EdgeInsets.only(top: Insets.sm),
                child: Text(
                  problem,
                  style: TypeLadder.callout.copyWith(color: colors.unf),
                ),
              ),
            const SizedBox(height: Insets.lg),
            InkButton(
              label: 'Save',
              onPressed: () =>
                  runBreathingAction(context, 'save your pattern', _save),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper(this.label, this.value, this.min, this.onChanged);

  static const int _max = 12;

  final String label;
  final int value;
  final int min;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: TypeLadder.body.copyWith(color: colors.ink),
          ),
        ),
        IconButton(
          tooltip: 'Less $label',
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: TypeLadder.bodyStrong.copyWith(color: colors.ink),
          ),
        ),
        IconButton(
          tooltip: 'More $label',
          onPressed: value < _max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}
