import 'package:flutter_test/flutter_test.dart';
import 'package:refract/core/device_time.dart';

void main() {
  test('Device event time is bounded and never invented from malformed values', () {
    expect(formatDeviceTime(42), '1970-01-01T00:00:42.000Z');
    for (final value in [null, -1, 253402300800, 1.5, '42']) {
      expect(formatDeviceTime(value), 'unavailable');
    }
  });
}
