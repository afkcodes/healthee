/// The profile form: what is written, and every rule about writing it.
///
/// v02's `.field` geometry throughout. **No rule about the data changed** — the
/// three that matter are called out here because each of them is one edit away
/// from being wrong:
///
///   * **A stored weight is never prefilled into the new-weigh-in field.** It is
///     shown, dated, beside a badge that says it is a dated measurement, and the
///     field starts empty. A prefilled 79.9 that the owner taps *Save* on
///     becomes a 79.9 measured today, and the freshness horizon that withholds
///     a stale VO₂max would then be satisfied by a number nobody stepped on a
///     scale for.
///   * **The activity level is only written when it was touched.** `updateSrpa`
///     exists so that saving a name does not also write "not answered" over an
///     answer the server already holds.
///   * **A failed save keeps the form.** The notice says the write could not be
///     confirmed and the typed values stay on screen, because the alternative is
///     an owner retyping their height to find out whether it saved.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:healthee/core/logging.dart';
import 'package:healthee/core/profile_field.dart';
import 'package:healthee/data/profile/health_profile.dart';
import 'package:healthee/data/profile/profile_repository.dart';
import 'package:healthee/data/today_repository.dart';
import 'package:healthee/features/profile/widgets/activity_level_field.dart';
import 'package:healthee/features/profile/widgets/profile_fields.dart';
import 'package:healthee/shared/v02/buttons.dart';
import 'package:healthee/shared/v02/fields.dart';
import 'package:healthee/shared/v02/notices.dart';
import 'package:healthee/shared/v02/section_head.dart';
import 'package:healthee/shared/v02/settings_page.dart';
import 'package:healthee/shared/v02/stat_block.dart';
import 'package:healthee/shared/v02/surfaces.dart';

/// The owner's details, their activity self-report, and a new weigh-in.
class ProfileEditor extends ConsumerStatefulWidget {
  /// [profile] seeds the fields; [repository] is what a save goes through.
  const ProfileEditor({
    required this.repository,
    required this.profile,
    this.focus,
    super.key,
  });

  /// The field a link asked to open on (`/profile?focus=weight`), or null.
  ///
  /// Weight and height take the keyboard; the date of birth opens its picker;
  /// sex and activity level are scrolled into view. Nothing is prefilled by it.
  final ProfileField? focus;

  /// The write path.
  final ProfileRepository repository;

  /// What the server currently holds.
  final HealthProfile profile;

  /// The prototype's own note under the form.
  static const String note =
      'These details personalise the reference estimates. Unanswered fields '
      'stay unknown — nothing here is guessed from your strap.';

  @override
  ConsumerState<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<ProfileEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.profile.name,
  );
  late final TextEditingController _height = TextEditingController(
    text: widget.profile.heightCm?.toString(),
  );

  /// **Deliberately empty.** See the library docstring.
  final TextEditingController _weight = TextEditingController();

  late String? _sex = widget.profile.sex;
  late int? _srpa = widget.profile.srpa;
  bool _srpaTouched = false;
  late String? _birthday = widget.profile.dobDate;
  late bool _weighing = widget.focus == ProfileField.weight;
  bool _saving = false;
  String? _notice;

  /// Where the sex and activity fields sit, so a link can scroll to them.
  final GlobalKey _sexKey = GlobalKey();
  final GlobalKey _activityKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final key = switch (widget.focus) {
      ProfileField.sex => _sexKey,
      ProfileField.activity => _activityKey,
      _ => null,
    };
    if (key != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = key.currentContext;
        if (mounted && target != null) {
          unawaited(Scrollable.ensureVisible(target));
        }
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        PlainCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              HField(
                label: 'What should we call you?',
                child: HTextField(
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              BirthdayField(
                value: _birthday,
                legacyStored: profile.legacyBirthdayPresent,
                enabled: !_saving,
                autoOpen: widget.focus == ProfileField.dob,
                onChanged: (value) => setState(() => _birthday = value),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: HField(
                      label: 'Height · cm',
                      reserveHint: true,
                      child: HTextField(
                        controller: _height,
                        enabled: !_saving,
                        autofocus: widget.focus == ProfileField.height,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: ProfileFields.columnGap),
                  Expanded(
                    child: HField(
                      key: _sexKey,
                      label: 'Sex for estimates',
                      reserveHint: true,
                      child: HSelect<String>(
                        title: 'Sex for estimates',
                        value: _sex,
                        placeholder: 'Not provided',
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _sex = value),
                        items: const <(String, String)>[
                          ('male', 'Male'),
                          ('female', 'Female'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              ActivityLevelField(
                key: _activityKey,
                value: _srpa,
                enabled: !_saving,
                onChanged: (value) => setState(() {
                  _srpa = value;
                  _srpaTouched = true;
                }),
              ),
            ],
          ),
        ),
        const SectionGap(),
        const SectionHead(title: 'Your latest weigh-in'),
        PlainCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: StatBlock(
                      label: profile.weightKg == null
                          ? 'No weight recorded'
                          : 'Last recorded '
                                '${profile.weightAsOf ?? 'date unavailable'}',
                      value: profile.weightKg?.toString(),
                      unit: 'kg',
                    ),
                  ),
                  if (profile.weightKg != null)
                    const HBadge('Dated measurement'),
                ],
              ),
              const SizedBox(height: ProfileFields.blockGap),
              if (_weighing)
                HField(
                  label: 'New weigh-in today',
                  hint:
                      'Enter a new measurement explicitly. Your previous '
                      'weight is not prefilled.',
                  child: HTextField(
                    controller: _weight,
                    enabled: !_saving,
                    autofocus: widget.focus == ProfileField.weight,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                )
              else
                HButton(
                  label: 'Log a new weigh-in',
                  kind: HButtonKind.secondary,
                  onPressed: _saving
                      ? null
                      : () => setState(() => _weighing = true),
                ),
              if (profile.bmi case final double bmi) ...<Widget>[
                const SizedBox(height: ProfileFields.blockGap),
                SmallProse(
                  'BMI from stored height and weight: $bmi kg/m² · weight '
                  'dated ${profile.weightAsOf ?? 'unknown'}. BMI does not '
                  'measure body composition.',
                ),
              ],
            ],
          ),
        ),
        const FormNote(ProfileEditor.note),
        if (_notice case final String message) ...<Widget>[
          Semantics(
            liveRegion: true,
            child: HNotice(title: 'About that save', body: message),
          ),
          const SectionGap(),
        ],
        HButton(
          label: _saving ? 'Saving…' : 'Save profile',
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Future<void> _save() async {
    final height = double.tryParse(_height.text.trim());
    final weight = double.tryParse(_weight.text.trim());
    if (!ProfileFields.validNumber(_height.text, height, 300) ||
        !ProfileFields.validNumber(_weight.text, weight, 500)) {
      setState(
        () => _notice =
            'Enter a valid positive height or weight, or leave it blank.',
      );
      return;
    }
    // Taken before the await: the owner may leave this screen while the save
    // is in flight, and the refresh must still happen. `ref` is dead by then.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      await widget.repository.save(
        name: _name.text,
        heightCm: height,
        sex: _sex,
        dobDate: _birthday,
        srpa: _srpa,
        updateSrpa: _srpaTouched,
        measuredWeightKg: weight,
      );
      container
        ..invalidate(healthProfileProvider)
        ..invalidate(todaySnapshotProvider);
      if (!mounted) {
        return;
      }
      _weight.clear();
      setState(() {
        _weighing = false;
        _notice = 'Saved. Daily estimates refresh with subsequent analysis.';
      });
    } on Exception catch (error, stack) {
      AppLog.failure('profile', 'saving profile', error, stack);
      if (mounted) {
        setState(
          () => _notice =
              'Save could not be confirmed. Your form is still here; check '
              'your connection and server version.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
