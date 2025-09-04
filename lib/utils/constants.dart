import 'package:flutter/material.dart';

/// 앱에서 사용하는 색상 상수들
class AppColors {
  // Primary Color (파란색 계열) - Material Design 색상 스케일
  static const Color primary50 = Color(0xFFE3F2FD);
  static const Color primary100 = Color(0xFFBBDEFB);
  static const Color primary200 = Color(0xFF90CAF9);
  static const Color primary300 = Color(0xFF64B5F6);
  static const Color primary400 = Color(0xFF42A5F5);
  static const Color primary500 = Color(0xFF2196F3);
  static const Color primary600 = Color(0xFF1E88E5);
  static const Color primary700 = Color(0xFF1976D2);
  static const Color primary800 = Color(0xFF1565C0);
  static const Color primary900 = Color(0xFF0D47A1);

  // Secondary Color (보라색 계열) - Material Design 색상 스케일
  static const Color secondary50 = Color(0xFFF3E5F5);
  static const Color secondary100 = Color(0xFFE1BEE7);
  static const Color secondary200 = Color(0xFFCE93D8);
  static const Color secondary300 = Color(0xFFBA68C8);
  static const Color secondary400 = Color(0xFFAB47BC);
  static const Color secondary500 = Color(0xFF9C27B0);
  static const Color secondary600 = Color(0xFF8E24AA);
  static const Color secondary700 = Color(0xFF7B1FA2);
  static const Color secondary800 = Color(0xFF6A1B9A);
  static const Color secondary900 = Color(0xFF4A148C);

  // 기존 배열 형태도 지원 (하위 호환성)
  static const List<Color> primaryColor = [
    primary50, primary100, primary200, primary300, primary400,
    primary500, primary600, primary700, primary800, primary900,
  ];

  static const List<Color> secondaryColor = [
    secondary50, secondary100, secondary200, secondary300, secondary400,
    secondary500, secondary600, secondary700, secondary800, secondary900,
  ];
}

/// 앱에서 사용하는 기본값들
class AppDefaults {
  // 윈도우 크기
  static const double defaultWindowWidth = 1280.0;
  static const double defaultWindowHeight = 800.0;
  static const double minWindowWidth = 1280.0;
  static const double minWindowHeight = 800.0;
  
  // 버튼 크기
  static const double buttonHeight = 50.0;
  static const double buttonBorderRadius = 14.0;
  
  // 간격
  static const double smallSpacing = 8.0;
  static const double mediumSpacing = 16.0;
  static const double largeSpacing = 24.0;
  static const double extraLargeSpacing = 32.0;
} 