import 'package:flutter/services.dart';

/// Formats up to eight DOB digits as MM/DD/YYYY.
class DateOfBirthInputFormatter extends TextInputFormatter {
  const DateOfBirthInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 8) digits = digits.substring(0, 8);

    final digitsBeforeCursor = newValue.selection.isValid
        ? newValue.text
              .substring(
                0,
                newValue.selection.end.clamp(0, newValue.text.length),
              )
              .replaceAll(RegExp(r'\D'), '')
              .length
              .clamp(0, digits.length)
        : digits.length;

    final formatted = formatDateOfBirthDigits(digits);
    var cursor = _formattedOffsetForDigitCount(
      digitsBeforeCursor,
      digits.length,
    );
    cursor = cursor.clamp(0, formatted.length);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  static int _formattedOffsetForDigitCount(int count, int totalDigits) {
    var offset = count;
    if (count >= 2 && totalDigits > 2) offset++;
    if (count >= 4 && totalDigits > 4) offset++;
    return offset;
  }
}

String formatDateOfBirthDigits(String digits) {
  final limited = digits.length > 8 ? digits.substring(0, 8) : digits;
  final buffer = StringBuffer();
  for (var index = 0; index < limited.length; index++) {
    if (index == 2 || index == 4) buffer.write('/');
    buffer.write(limited[index]);
  }
  return buffer.toString();
}

/// Parses a complete MM/DD/YYYY value, rejecting normalized invalid dates.
DateTime? parseDateOfBirth(String value) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(value);
  if (match == null) return null;

  final month = int.parse(match.group(1)!);
  final day = int.parse(match.group(2)!);
  final year = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}
