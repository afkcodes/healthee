import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/challenges/challenge.dart';
import 'package:healthee/data/challenges/challenge_feed.dart';

import '../features/_workouts_host.dart' show loadSnapshot;

const String _path = '../../packages/contracts/snapshots/challenges.json';

void main() {
  test('the committed snapshot parses and a plain challenge has no job', () {
    final feed = ChallengeFeed.fromJson(loadSnapshot(_path));
    final c = feed.active.first;
    expect(c.daysRequired, isNull);
    expect(c.slot, isNull);
    expect(c.floor, isNull);
    expect(c.countsWhen, isNull);
    expect(c.actionText, isNull);
  });

  test('a coach job entry carries the server wire keys through', () {
    final json = loadSnapshot(_path);
    final row = <String, Object?>{
      ...((json['active']! as List).first as Map<String, Object?>),
      'action_text': 'brisk walk',
      'slot_text': 'after 10 pm',
      'floor_text': '10 minutes. Half credit.',
      'floor_value': 10.0,
      'counts_when': 'when the strap logs 15 minutes',
      'days_required': 4,
    };
    final c = Challenge.fromJson(row);
    expect(c.actionText, 'brisk walk');
    expect(c.slot, 'after 10 pm');
    expect(c.floor, '10 minutes. Half credit.');
    expect(c.countsWhen, 'when the strap logs 15 minutes');
    expect(c.daysRequired, 4);
  });
}
