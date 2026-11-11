/// Format an optional device-recorded Unix second count without inventing a date.
/// The caller must label the event kind separately (consent, approval, etc.).
String formatDeviceTime(Object? value) {
  if (value is! int || value < 0 || value > 253402300799) return 'unavailable';
  return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true).toIso8601String();
}
