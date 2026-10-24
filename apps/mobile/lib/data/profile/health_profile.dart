/// Demographics and the last dated weight. A restored weight is never a new log.
class HealthProfile {
  const HealthProfile({
    this.name,
    this.bmi,
    this.heightCm,
    this.sex,
    this.dobDate,
    this.weightKg,
    this.weightAsOf,
    this.weightAgeDays,
    this.srpa,
    this.legacyBirthdayPresent = false,
  });

  factory HealthProfile.fromJson(Map<String, Object?> json) => HealthProfile(
    name: json['name'] as String?,
    bmi: (json['bmi'] as num?)?.toDouble(),
    heightCm: (json['height_cm'] as num?)?.toDouble(),
    sex: json['sex'] as String?,
    dobDate: json['dob_date'] as String?,
    weightKg: (json['weight_kg'] as num?)?.toDouble(),
    weightAsOf: json['weight_as_of'] as String?,
    weightAgeDays: (json['weight_age_days'] as num?)?.toInt(),
    srpa: (json['srpa'] as num?)?.toInt(),
    legacyBirthdayPresent: json['dob'] != null && json['dob_date'] == null,
  );

  final String? name;
  final double? bmi;
  final double? heightCm;
  final String? sex;
  final String? dobDate;
  final double? weightKg;
  final String? weightAsOf;

  /// How many days old [weightKg] is, as the server counts it. Null when there
  /// is no weight or the server predates the field.
  final int? weightAgeDays;
  final int? srpa;

  /// Older servers return only an instant; never guess its calendar timezone.
  final bool legacyBirthdayPresent;
}
