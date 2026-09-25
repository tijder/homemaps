import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:homemaps/services/app_log.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('app_log'));
  tearDown(() => dir.deleteSync(recursive: true));

  String exported(AppLog log) => utf8.decode(log.export()!);

  test('nothing logged: nothing to export', () {
    expect(AppLog().export(), isNull);
  });

  test('what came before the file is written after the header', () {
    final log = AppLog()..add('early');
    log.attach(dir, '==== header ====');
    log.add('late');
    final text = exported(log);
    expect(text.indexOf('==== header ===='), lessThan(text.indexOf('early')));
    expect(text.indexOf('early'), lessThan(text.indexOf('late')));
    expect(File('${dir.path}/homemaps.log').readAsStringSync(), text);
  });

  test('rotates to one old file and exports both, oldest first', () {
    final log = AppLog(maxFileBytes: 100)..attach(dir, 'header');
    log.add('first ${'x' * 120}');
    log.add('second');
    expect(File('${dir.path}/homemaps.log.1').existsSync(), isTrue);
    final text = exported(log);
    expect(text.indexOf('first'), lessThan(text.indexOf('second')));
  });

  test('the export keeps the end', () {
    final log = AppLog(maxExportBytes: 50)..attach(dir, 'header');
    log.add('a' * 200);
    log.add('the end');
    final bytes = log.export()!;
    expect(bytes.length, 50);
    expect(utf8.decode(bytes, allowMalformed: true), endsWith('the end\n'));
  });
}
