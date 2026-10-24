/// The profile fields a link can open the profile screen on.
///
/// In `core` rather than beside the profile model because `routes.dart` builds
/// the link and imports nothing but Dart; `data/models/age_pause.dart` re-exports
/// it so the data layer names the same five fields.
library;

/// A field of the owner's profile.
///
/// The [name] of each value is also its `?focus=` spelling, so the link and
/// the enum cannot drift apart.
enum ProfileField {
  /// Date of birth.
  dob,

  /// Height.
  height,

  /// Sex for estimates.
  sex,

  /// A new weigh-in.
  weight,

  /// Usual activity level.
  activity,
}
