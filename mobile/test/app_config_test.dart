import 'package:flutter_test/flutter_test.dart';
import 'package:okeyx_mobile/core/config.dart';

void main() {
  test('default app update metadata matches the current pubspec release', () {
    expect(AppConfig.versionName, '20.7.0');
    expect(AppConfig.buildNumber, 270);
  });
}
