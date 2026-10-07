import 'package:flutter/material.dart';

/// TSAK 브랜드 테마 — 컬러풀 커스텀 디자인 (스타일 2)
/// 한국범스카우트 색상: 보라(중앙회), 태극 레드/블루, 호랑이 골드
class AppColors {
  static const purple = Color(0xFF5B2C8D);
  static const purpleLight = Color(0xFF7E4FB0);
  static const purpleDark = Color(0xFF3D1B63);
  static const taegeukRed = Color(0xFFD62828);
  static const taegeukBlue = Color(0xFF1B4F9C);
  static const tigerGold = Color(0xFFF2B705);

  /// 평생회원 강조용 — 흰 배경 위에서도 가독성 높은 진한 골드
  static const lifetimeGold = Color(0xFFB8860B);
  static const scoutGreen = Color(0xFF2E7D32);
  static const bg = Color(0xFFF6F4FB);
  static const card = Colors.white;
  static const textDark = Color(0xFF1F1A2E);
  static const textGray = Color(0xFF6E6A7C);

  /// 역할 배지용 세련된 저채도 팔레트 — 원색 대신 딥톤 글자 + 옅은 틴트.
  ///  (마스터=딥 와인 / 관리자=딥 슬레이트 인디고)
  static const masterInk = Color(0xFF7B2635);
  static const masterTint = Color(0xFFF6E8EA);
  static const adminInk = Color(0xFF2E3E63);
  static const adminTint = Color(0xFFE9EDF6);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [purple, purpleLight, taegeukRed],
  );
}

class AppTheme {
  static ThemeData light() {
    // 한글 폰트: 번들된 NanumGothic 을 기본으로 지정한다.
    //  - 이전에는 fontFamily 미지정 → 웹에서 기본 Roboto 사용 → 한글 글리프
    //    부재로 Flutter 가 런타임에 Google Fonts(Noto Sans KR)를 9회 추가
    //    다운로드(=첫 로딩 지연 + 외부 의존)했다. 번들 폰트를 쓰면 이 요청이
    //    완전히 사라지고, 이미 임계경로에 있는 폰트를 재사용한다.
    //  - fontFamilyFallback: 혹시 모를 미수록 글리프는 플랫폼 시스템 폰트로.
    const kFontFallback = <String>[
      'NanumGothic', // 번들 기본
      'Apple SD Gothic Neo', // iOS/macOS
      'Noto Sans CJK KR', // Android/리눅스
      'Malgun Gothic', // Windows
      'sans-serif',
    ];
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: 'NanumGothic',
      fontFamilyFallback: kFontFallback,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.purple,
        primary: AppColors.purple,
      ),
      scaffoldBackgroundColor: AppColors.bg,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.purple,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontWeight: FontWeight.w800),
        unselectedLabelStyle: TextStyle(fontWeight: FontWeight.w600),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 2,
        shadowColor: AppColors.purple.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.taegeukRed,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.purple.withValues(alpha: 0.2),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.purple.withValues(alpha: 0.2),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.purple, width: 2),
        ),
      ),
    );
  }
}

/// 연맹별 색상 (시각적 구분)
Color leagueColor(String league) {
  const palette = [
    AppColors.purple,
    AppColors.taegeukBlue,
    AppColors.taegeukRed,
    AppColors.scoutGreen,
    Color(0xFFB8860B),
    Color(0xFF00838F),
    Color(0xFF6D4C41),
    Color(0xFFAD1457),
    Color(0xFF283593),
    Color(0xFF2E7D32),
  ];
  if (league.isEmpty) return AppColors.textGray;
  final idx = league.codeUnits.fold<int>(0, (p, e) => p + e) % palette.length;
  return palette[idx];
}
