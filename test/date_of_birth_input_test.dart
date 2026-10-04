import 'package:attendus/screens/Authentication/create_account/dob_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const formatter = DateOfBirthInputFormatter();

  TextEditingValue format(String text, {TextEditingValue? oldValue}) {
    return formatter.formatEditUpdate(
      oldValue ?? TextEditingValue.empty,
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      ),
    );
  }

  test('formats eight DOB digits as MM/DD/YYYY', () {
    expect(format('07271998').text, '07/27/1998');
  });

  test('adds separators progressively and limits input to eight digits', () {
    expect(format('072').text, '07/2');
    expect(format('07271').text, '07/27/1');
    expect(format('07271998123').text, '07/27/1998');
    expect(format('07a27-1998').text, '07/27/1998');
  });

  test('keeps the cursor at the end of formatted input', () {
    final value = format('07271998');
    expect(value.selection, const TextSelection.collapsed(offset: 10));
  });

  test('parses valid dates including leap days', () {
    expect(parseDateOfBirth('02/29/2000'), DateTime(2000, 2, 29));
    expect(parseDateOfBirth('07/27/1998'), DateTime(1998, 7, 27));
  });

  test('rejects incomplete and impossible dates', () {
    expect(parseDateOfBirth('07/27/'), isNull);
    expect(parseDateOfBirth('02/30/1998'), isNull);
    expect(parseDateOfBirth('02/29/2001'), isNull);
  });
}
