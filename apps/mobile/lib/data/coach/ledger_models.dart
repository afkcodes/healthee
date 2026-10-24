/// The coach ledger, typed: `GET /api/coach/ledger`.
///
/// Parsed defensively. A verdict string this build does not know is
/// [LedgerVerdict.noData], never [LedgerVerdict.done]: a ledger that rounds an
/// unknown word up to a yes is the flattery this product exists not to do.
library;

/// How the server judged one yes.
enum LedgerVerdict {
  /// Checked against the strap and met.
  done,

  /// Half met.
  partial,

  /// Checked and not met.
  missed,

  /// The strap had no reading for the day.
  noData,

  /// The strap cannot see this kind of ask.
  uncheckable;

  /// The wire word to a verdict; anything unknown is [noData].
  static LedgerVerdict parse(Object? word) => switch (word) {
    'done' => done,
    'partial' => partial,
    'missed' => missed,
    'uncheckable' => uncheckable,
    _ => noData,
  };

  /// Whether the strap gave a proof either way.
  bool get isProof => this == done || this == partial || this == missed;
}

/// What the strap measured for one entry. Every field may be absent.
class LedgerMeasured {
  /// Builds a measurement.
  const LedgerMeasured({this.value, this.unit, this.label});

  /// Reads the `measured` block; a missing block is an empty measurement.
  factory LedgerMeasured.fromJson(Object? json) {
    if (json is! Map) {
      return const LedgerMeasured();
    }
    final value = json['value'];
    final unit = json['unit'];
    final label = json['label'];
    return LedgerMeasured(
      value: value is num ? value.toDouble() : null,
      unit: unit is String && unit.isNotEmpty ? unit : null,
      label: label is String && label.isNotEmpty ? label : null,
    );
  }

  /// The number, when there is one.
  final double? value;

  /// Its unit.
  final String? unit;

  /// The server's own words for it.
  final String? label;

  /// The server's label, else value and unit, else null. Nothing invented.
  String? get text {
    if (label != null) {
      return label;
    }
    final v = value;
    if (v == null) {
      return null;
    }
    final number = v == v.roundToDouble() ? '${v.round()}' : '$v';
    return unit == null ? number : '$number $unit';
  }
}

/// One idea the owner said yes to, and what became of it.
class LedgerEntry {
  /// Builds an entry.
  const LedgerEntry({
    required this.date,
    required this.title,
    required this.verdict,
    required this.measured,
    required this.source,
    this.refId,
  });

  /// Reads one entry.
  factory LedgerEntry.fromJson(Map<String, Object?> json) => LedgerEntry(
    date: json['date'] as String? ?? '',
    title: json['title'] as String? ?? '',
    verdict: LedgerVerdict.parse(json['verdict']),
    measured: LedgerMeasured.fromJson(json['measured']),
    source: json['source'] as String? ?? '',
    refId: (json['ref_id'] as num?)?.toInt(),
  );

  /// ISO day.
  final String date;

  /// What was asked.
  final String title;

  /// How it was judged.
  final LedgerVerdict verdict;

  /// What the strap saw.
  final LedgerMeasured measured;

  /// `challenge` or `recommendation`.
  final String source;

  /// The row it came from.
  final int? refId;
}

/// One week of the ledger.
class LedgerWeek {
  /// Builds a week.
  const LedgerWeek({
    required this.from,
    required this.to,
    required this.ideasGiven,
    required this.yeses,
    required this.entries,
  });

  /// Reads one week.
  factory LedgerWeek.fromJson(Map<String, Object?> json) => LedgerWeek(
    from: json['from'] as String? ?? '',
    to: json['to'] as String? ?? '',
    ideasGiven: (json['ideas_given'] as num?)?.toInt() ?? 0,
    yeses: (json['yeses'] as num?)?.toInt() ?? 0,
    entries: _entries(json['entries']),
  );

  /// First day.
  final String from;

  /// Last day.
  final String to;

  /// Ideas offered that week.
  final int ideasGiven;

  /// Ideas accepted.
  final int yeses;

  /// The accepted ones, newest first as served.
  final List<LedgerEntry> entries;

  /// Ideas offered and not accepted.
  int get skipped => ideasGiven > yeses ? ideasGiven - yeses : 0;
}

List<LedgerEntry> _entries(Object? rows) => <LedgerEntry>[
  if (rows is List)
    for (final row in rows)
      if (row is Map<String, Object?>) LedgerEntry.fromJson(row),
];

/// The five counts.
class LedgerTotals {
  /// Builds the counts.
  const LedgerTotals({
    this.done = 0,
    this.partial = 0,
    this.missed = 0,
    this.noData = 0,
    this.uncheckable = 0,
  });

  /// Reads the counts.
  factory LedgerTotals.fromJson(Object? json) {
    final map = json is Map ? json : const <Object?, Object?>{};
    int n(String key) => (map[key] as num?)?.toInt() ?? 0;
    return LedgerTotals(
      done: n('done'),
      partial: n('partial'),
      missed: n('missed'),
      noData: n('no_data'),
      uncheckable: n('uncheckable'),
    );
  }

  /// Met.
  final int done;

  /// Half met.
  final int partial;

  /// Not met.
  final int missed;

  /// No reading.
  final int noData;

  /// Not visible to the strap.
  final int uncheckable;

  /// "No proof": the strap could say nothing either way.
  int get noProof => noData + uncheckable;

  /// Every yes counted.
  int get all => done + partial + missed + noProof;
}

/// Done of provable, as the server counts it.
class DoneRate {
  /// Builds the rate.
  const DoneRate({required this.done, required this.provable});

  /// Reads the rate.
  factory DoneRate.fromJson(Object? json) {
    final map = json is Map ? json : const <Object?, Object?>{};
    return DoneRate(
      done: (map['done'] as num?)?.toInt() ?? 0,
      provable: (map['provable'] as num?)?.toInt() ?? 0,
    );
  }

  /// Done.
  final int done;

  /// Yeses the strap could judge.
  final int provable;
}

/// The whole response.
class CoachLedger {
  /// Builds a ledger.
  const CoachLedger({
    required this.window,
    required this.from,
    required this.to,
    required this.ideasGiven,
    required this.yeses,
    required this.totals,
    required this.doneRate,
    required this.weeks,
    this.pattern,
  });

  /// Reads the response.
  factory CoachLedger.fromJson(Map<String, Object?> json) {
    final pattern = json['pattern'];
    return CoachLedger(
      window: json['window'] as String? ?? '',
      from: json['from'] as String? ?? '',
      to: json['to'] as String? ?? '',
      ideasGiven: (json['ideas_given'] as num?)?.toInt() ?? 0,
      yeses: (json['yeses'] as num?)?.toInt() ?? 0,
      totals: LedgerTotals.fromJson(json['totals']),
      doneRate: DoneRate.fromJson(json['done_rate']),
      weeks: <LedgerWeek>[
        if (json['weeks'] case final List<Object?> rows)
          for (final row in rows)
            if (row is Map<String, Object?>) LedgerWeek.fromJson(row),
      ],
      pattern: pattern is String && pattern.trim().isNotEmpty ? pattern : null,
    );
  }

  /// `week`, `month` or `all`.
  final String window;

  /// First day of the window.
  final String from;

  /// Last day.
  final String to;

  /// Ideas offered across the window.
  final int ideasGiven;

  /// Ideas accepted.
  final int yeses;

  /// The five counts.
  final LedgerTotals totals;

  /// Done of provable.
  final DoneRate doneRate;

  /// Newest first.
  final List<LedgerWeek> weeks;

  /// The server's sentence, verbatim; null hides the card.
  final String? pattern;

  /// Nothing was offered and nothing accepted.
  bool get isEmpty => ideasGiven == 0 && yeses == 0 && weeks.isEmpty;
}
