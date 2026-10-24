/// The scaffold's only screen: a live specimen sheet of the honesty states.
///
/// This is **not** a feature screen and does not belong to `features/` — nothing
/// there is built yet. It exists so the foundation is verifiable by looking at it:
/// the theme resolves in both modes, the shared state widgets render, and all four
/// [Reading] cases are on screen at once, so whoever builds Today tomorrow can see
/// what a withhold looks like beside a caveated value before writing any of it.
///
/// It was the widget-smoke-test target and it sat on `/`, where the owner ran the
/// app and reasonably took a specimen loading card for a hung request. Today now
/// owns `/` and this lives at `Routes.devFoundation`.
///
/// It is kept rather than deleted, against its own original instruction, for one
/// concrete reason: it is the only place all four `Reading` states are on screen
/// together, which is what you want open while building a card that has to
/// handle them. It is a design reference, reachable only by typing its path, and
/// it must never be linked from a product screen.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/data/honesty/disclosure.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/shared/states/reading_view.dart';
import 'package:healthee/shared/states/state_scaffold.dart';

/// The specimen sheet.
class FoundationScreen extends StatelessWidget {
  /// Builds the scaffold's placeholder screen.
  const FoundationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Healthee')),
      body: ListView(
        // ListView.builder is the rule for real lists (Standards §1); this is a
        // fixed handful of specimens, so the children form is the honest one.
        padding: const EdgeInsets.all(Insets.lg),
        children: [
          Text(
            'Foundation — the four honesty states',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: Insets.xs),
          Text(
            'Specimens, not readings. This screen is deleted when Today lands.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.ink2),
          ),
          const SizedBox(height: Insets.xl),

          const _Specimen(
            title: 'Present',
            child: ReadingView<String>(
              reading: Present<String>('43.0 mL/kg/min'),
              label: 'VO₂max',
              builder: _value,
            ),
          ),

          const _Specimen(
            title: 'Caveated — reported, and which way it leans',
            child: ReadingView<String>(
              reading: Caveated<String>('34.3 years', [
                Disclosure(
                  reason: 'vo2max_measured_from_session',
                  message:
                      'The fitness half of this number was measured rather than '
                      'modelled: it comes from a recorded session in the last two '
                      'weeks. Checked against lab tests it is off by about 7%.',
                  term: 'fitness',
                ),
              ]),
              label: 'Biological age',
              builder: _value,
            ),
          ),

          const _Specimen(
            title: 'Withheld — no value, and what would bring one back',
            child: ReadingView<String>(
              // Real production copy, quoted in brief §3 as the text to design
              // against. Not invented for the specimen.
              reading: Withheld<String>(
                Disclosure(
                  reason: 'insufficient_rhr_nights',
                  message:
                      'Fewer than 3 nights of resting heart rate in the last '
                      'week — wear the strap overnight for a few more nights '
                      'and this comes back.',
                  asOfDate: '2026-07-28',
                  ageDays: 7,
                ),
              ),
              label: 'Recovery',
              builder: _value,
              // The explainer pill. It opens the reasoning; it is NOT a retry.
              onExplainWithheld: _noop,
            ),
          ),

          const _Specimen(
            title: 'Excluded — nobody can price this, ever',
            child: ReadingView<String>(
              reading: Excluded<String>([
                Disclosure(
                  reason: 'sri_hazard_not_transportable',
                  message:
                      'Sleep regularity is not one of the levers behind this '
                      'number. The published risk-per-point belongs to the '
                      'software, not to the index — so we cannot honestly convert '
                      'it into years.',
                  term: 'regularity',
                ),
              ]),
              label: 'Biological age',
              builder: _value,
            ),
          ),

          const _Specimen(title: 'Loading', child: LoadingState(label: 'Loading today')),

          _Specimen(
            title: 'Error — ours, and retryable',
            child: ErrorState(
              message: "Couldn't reach the server",
              detail: 'Your data is safe. This is a connection problem, not a gap in it.',
              onRetry: () {},
            ),
          ),

          const _Specimen(
            title: 'Empty — nothing yet, and how to change that',
            child: EmptyState(
              message: 'No workouts this week',
              hint: 'Recorded sessions of 10 minutes or more appear here after a sync.',
            ),
          ),
        ],
      ),
    );
  }

  /// The specimen sheet has no sheets to open; a real screen supplies one.
  static void _noop() {}

  static Widget _value(BuildContext context, String value) {
    return StateCard(
      child: Text(value, style: Theme.of(context).textTheme.displayMedium),
    );
  }
}

class _Specimen extends StatelessWidget {
  const _Specimen({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: Insets.sm),
          child,
        ],
      ),
    );
  }
}
