/// Quote every field and neutralize spreadsheet formulas in user supplied text.
String analyticsCsv(Iterable<Iterable<Object?>> rows) => rows
    .map(
      (row) => row
          .map((value) {
            var text = value?.toString() ?? '';
            if (RegExp(r'^\s*[=+@-]').hasMatch(text)) text = "'$text";
            return '"${text.replaceAll('"', '""')}"';
          })
          .join(','),
    )
    .join('\r\n');
