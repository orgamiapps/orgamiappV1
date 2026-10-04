import 'package:flutter_test/flutter_test.dart';
import 'package:attendus/Utils/analytics_csv.dart';

void main() {
  test('CSV preserves commas quotes and newlines', () {
    expect(
      analyticsCsv([
        ['Doe, Jane', 'a"b', 'first\nsecond'],
      ]),
      '"Doe, Jane","a""b","first\nsecond"',
    );
  });
  test('CSV neutralizes formula prefixes including leading whitespace', () {
    expect(
      analyticsCsv([
        ['=1+1', ' @SUM(A1)', '-formula'],
      ]),
      r'''"'=1+1","' @SUM(A1)","'-formula"''',
    );
  });
}
