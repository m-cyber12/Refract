import 'package:flutter/material.dart';

/// REFRACT design tokens — "Prismatic Intelligence".
///
/// Color semantics (per spec §8.2):
/// - cyan   → information & navigation
/// - violet → intelligence & transformations
/// - amber  → attention & uncertainty
/// - green  → successful verification
class RefractColors {
  RefractColors._();

  // Dark palette (default)
  static const obsidian = Color(0xFF0B0D12);
  static const graphite = Color(0xFF151923);
  static const elevated = Color(0xFF1C2230);
  static const softWhite = Color(0xFFF2F4F8);
  static const muted = Color(0xFF929BAC);
  static const prismCyan = Color(0xFF70D7E8);
  static const spectralViolet = Color(0xFFA78BFA);
  static const signalAmber = Color(0xFFE8B96A);
  static const verificationGreen = Color(0xFF65C99A);

  // Light palette
  static const lightBackground = Color(0xFFFAFBFD);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightText = Color(0xFF151923);
  static const lightMuted = Color(0xFF5A6478);
}
