import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:okeyx_mobile/core/config.dart';

void main() {
  test('varsayılan sürüm bilgisi pubspec ile aynı', () {
    // Sürüm her yükseltildiğinde testi elle güncellemek gerekmesin.
    final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final version = line.split(':').last.trim();
    final name = version.split('+').first;
    final build = int.parse(version.split('+').last);
    expect(AppConfig.versionName, name);
    expect(AppConfig.buildNumber, build);
  });
}
