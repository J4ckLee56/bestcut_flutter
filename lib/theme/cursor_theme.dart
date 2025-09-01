import 'package:flutter/material.dart';

/// Cursor AI 스타일 다크 테마 시스템
class CursorTheme {
  // 🎨 Cursor AI 핵심 컬러 팔레트
  static const Color cursorBlue = Color(0xFF007ACC); // Cursor AI의 메인 블루
  static const Color cursorBlueDark = Color(0xFF005A9F); // 더 어두운 블루
  static const Color cursorBlueLight = Color(0xFF4DA6E0); // 더 밝은 블루

  // 🌙 다크 테마 배경 컬러
  static const Color backgroundPrimary = Color(0xFF1E1E1E); // 메인 배경 (Cursor AI 스타일)
  static const Color backgroundSecondary = Color(0xFF2D2D30); // 카드/컨테이너 배경
  static const Color backgroundTertiary = Color(0xFF383838); // 더 밝은 요소 배경
  static const Color backgroundElevated = Color(0xFF404040); // 높이 있는 요소 배경

  // 📝 텍스트 컬러
  static const Color textPrimary = Color(0xFFFFFFFF); // 메인 텍스트
  static const Color textSecondary = Color(0xFFCCCCCC); // 보조 텍스트
  static const Color textTertiary = Color(0xFF969696); // 희미한 텍스트
  static const Color textAccent = Color(0xFF007ACC); // 강조 텍스트 (Cursor 블루)

  // 🖼️ 테두리 및 구분선
  static const Color borderPrimary = Color(0xFF414141); // 메인 테두리
  static const Color borderSecondary = Color(0xFF555555); // 보조 테두리
  static const Color borderAccent = Color(0xFF007ACC); // 강조 테두리
  static const Color borderHover = Color(0xFF4DA6E0); // 호버 테두리

  // ✨ 상태 컬러
  static const Color success = Color(0xFF4CAF50); // 성공
  static const Color warning = Color(0xFFFF9800); // 경고
  static const Color error = Color(0xFFF44336); // 오류
  static const Color info = Color(0xFF2196F3); // 정보

  // 🎯 특별한 효과
  static const Color shadow = Color(0x1A000000); // 그림자
  static const Color overlay = Color(0x80000000); // 오버레이
  static const Color highlight = Color(0x1A007ACC); // 하이라이트

  // 📐 디자인 시스템 상수
  static const double radiusSmall = 4.0;
  static const double radiusMedium = 8.0;
  static const double radiusLarge = 12.0;
  static const double radiusXLarge = 16.0;

  static const double spacingXS = 4.0;
  static const double spacingS = 8.0;
  static const double spacingM = 16.0;
  static const double spacingL = 24.0;
  static const double spacingXL = 32.0;

  /// Cursor AI 스타일 다크 테마 데이터
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      
      // 🎨 컬러 스킴 (Cursor AI 스타일)
      colorScheme: const ColorScheme.dark(
        primary: cursorBlue,
        primaryContainer: cursorBlueDark,
        secondary: cursorBlueLight,
        secondaryContainer: backgroundTertiary,
        surface: backgroundSecondary,
        surfaceContainerHighest: backgroundTertiary,
        background: backgroundPrimary,
        error: error,
        onPrimary: textPrimary,
        onSecondary: textPrimary,
        onSurface: textPrimary,
        onBackground: textPrimary,
        onError: textPrimary,
        outline: borderPrimary,
        outlineVariant: borderSecondary,
      ),

      // 📱 앱바 테마
      appBarTheme: const AppBarTheme(
        backgroundColor: backgroundSecondary,
        foregroundColor: textPrimary,
        elevation: 1,
        shadowColor: shadow,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      // 🏗️ 스캐폴드 테마
      scaffoldBackgroundColor: backgroundPrimary,

      // 📦 카드 테마
      cardTheme: CardThemeData(
        color: backgroundSecondary,
        shadowColor: shadow,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: const BorderSide(color: borderPrimary, width: 1),
        ),
      ),

      // 🔘 버튼 테마
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cursorBlue,
          foregroundColor: textPrimary,
          elevation: 2,
          shadowColor: shadow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacingM,
            vertical: spacingS,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: cursorBlue,
          side: const BorderSide(color: cursorBlue, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: spacingM,
            vertical: spacingS,
          ),
        ),
      ),

      // 📝 텍스트 테마
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: textPrimary,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: TextStyle(
          color: textPrimary,
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
        headlineSmall: TextStyle(
          color: textPrimary,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        titleSmall: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.normal,
        ),
        bodyMedium: TextStyle(
          color: textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.normal,
        ),
        bodySmall: TextStyle(
          color: textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.normal,
        ),
        labelLarge: TextStyle(
          color: textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: TextStyle(
          color: textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        labelSmall: TextStyle(
          color: textTertiary,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),

      // 📥 입력 필드 테마
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: backgroundTertiary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: borderPrimary),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: borderPrimary),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: const BorderSide(color: cursorBlue, width: 2),
        ),
        labelStyle: const TextStyle(color: textSecondary),
        hintStyle: const TextStyle(color: textTertiary),
      ),

      // 📊 프로그레스바 테마
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: cursorBlue,
        linearTrackColor: backgroundTertiary,
      ),

      // 🎛️ 슬라이더 테마
      sliderTheme: SliderThemeData(
        activeTrackColor: cursorBlue,
        inactiveTrackColor: backgroundTertiary,
        thumbColor: cursorBlue,
        overlayColor: highlight,
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
    );
  }

  /// 컨테이너 데코레이션 빌더
  static BoxDecoration containerDecoration({
    Color? backgroundColor,
    Color? borderColor,
    double borderRadius = radiusMedium,
    bool elevated = false,
    bool glowing = false,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? backgroundSecondary,
      borderRadius: BorderRadius.circular(borderRadius),
      border: borderColor != null 
        ? Border.all(color: borderColor, width: 1) 
        : Border.all(color: borderPrimary, width: 1),
      boxShadow: [
        if (elevated) ...[
          BoxShadow(
            color: shadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        if (glowing) ...[
          BoxShadow(
            color: cursorBlue.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(0, 0),
          ),
        ],
      ],
    );
  }

  /// 글래스모피즘 효과 데코레이션
  static BoxDecoration glassmorphismDecoration({
    double borderRadius = radiusMedium,
    double opacity = 0.1,
  }) {
    return BoxDecoration(
      color: textPrimary.withOpacity(opacity),
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(
        color: borderPrimary.withOpacity(0.2),
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: shadow,
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  /// 호버 효과 데코레이션
  static BoxDecoration hoverDecoration({
    Color? backgroundColor,
    double borderRadius = radiusMedium,
  }) {
    return BoxDecoration(
      color: backgroundColor ?? backgroundTertiary,
      borderRadius: BorderRadius.circular(borderRadius),
      border: Border.all(color: borderHover, width: 1),
      boxShadow: [
        BoxShadow(
          color: cursorBlue.withOpacity(0.1),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}
