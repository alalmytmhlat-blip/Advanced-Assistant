import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:advanced_assistant/features/pdf_import/data/universal_file_extractor.dart';

void main() {
  late Directory directory;
  late UniversalFileExtractor extractor;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('universal-import-');
    extractor = UniversalFileExtractor();
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('detects CSV delimiter and preserves quoted delimiters', () async {
    final file = File('${directory.path}/customers.csv');
    await file.writeAsString('name,phone,address\n"أحمد، علي",777,صنعاء\n');
    final result = await extractor.extract(file);
    expect(result.format, 'CSV');
    expect(result.text, contains('أحمد، علي\t777\tصنعاء'));
  });

  test('converts JSON object arrays into tabular rows', () async {
    final file = File('${directory.path}/customers.json');
    await file.writeAsString('[{"name":"سالم","phone":"700"},{"name":"علي","phone":"701"}]');
    final result = await extractor.extract(file);
    expect(result.format, 'JSON');
    expect(result.text, contains('name\tphone'));
    expect(result.text, contains('سالم\t700'));
    expect(result.text, contains('علي\t701'));
  });

  test('reports unsupported formats instead of silently ignoring them', () async {
    final file = File('${directory.path}/unknown.bin');
    await file.writeAsString('data');
    expect(() => extractor.extract(file), throwsFormatException);
  });
}
