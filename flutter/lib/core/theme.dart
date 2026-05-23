import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// Facely — 디자인 토큰 SSOT.
/// 위젯 코드에서 fontSize·color·padding·radius 를 inline 으로 박지 말고
/// 본 파일의 토큰만 참조한다. 자세한 운영 규칙은 `flutter/DESIGN.md` 참고.
///
/// 본 파일이 정의하는 것:
///   - [AppColors] : 브랜드 컬러 팔레트
///   - [AppText]   : 6 단 텍스트 스타일 (display 만 SongMyung)
///   - [AppSpacing]: 4-스텝 spacing 스케일
///   - [AppRadius] : border radius 스케일
///   - [AppTheme]  : Material 3 ThemeData (위 토큰들을 textTheme/appBarTheme 에 주입)
/// ---------------------------------------------------------------------------

// SongMyung 은 display 토큰(화면 최상위 타이틀, AppBar 타이틀)에서만 쓴다.
// 그 외 모든 텍스트는 system default font.
const String _kDisplayFont = 'SongMyung';

class AppColors {
  // Surface
  static const background = Colors.white;

  static const surface = Color(0xFFF5F5F5);
  static const border = Color(0xFFE0E0E0);
  // Text
  static const textPrimary = Color(0xFF333333);

  static const textSecondary = Color(0xFF777777);
  static const textHint = Color(0xFFAAAAAA);
  // Accent (general)
  static const accent = Color(0xFF555555);

  // Semantic
  static const success = Color(0xFF2E7D32);

  static const danger = Color(0xFFD32F2F);
  static const info = Color(0xFF1565C0);
  // Premium / brand-warm (gold family)
  static const gold = Color(0xFFC9A876);

  static const goldDim = Color(0xFFA89678);
  static const goldSoft = Color(0xFFF4E4C1);
  // Warm beige palette — 관상 본문 카드 및 통일된 본문 컨테이너.
  // 신규 본문 카드는 cream 배경 + shell border + darkBrown title + warmBrown secondary.
  static const cream = Color(0xFFF5EFE0);

  static const shell = Color(0xFFEDE5D5);
  static const darkBrown = Color(0xFF5C4033);
  static const warmBrown = Color(0xFF7B5B3A);
  AppColors._();
}

/// border radius 스케일.
class AppRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 16;
  AppRadius._();
}

/// 4-스텝 spacing 스케일. SizedBox·padding·gap 은 본 값만 사용.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double huge = 32;
  AppSpacing._();
}

/// 6-단 텍스트 토큰 + AppBar 타이틀.
/// **display 만 SongMyung. 나머지는 system default.**
/// 신규 화면은 inline `TextStyle(fontSize: …)` 대신 `AppText.X` 또는
/// `AppText.X.copyWith(color: …)` 만 사용.
class AppText {
  /// **display** — 28 w700 SongMyung. 홈 화면 "AI 관상가" 같은 화면 최상위 타이틀.
  static const TextStyle display = TextStyle(
    fontFamily: _kDisplayFont,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
    height: 1.2,
  );

  /// **appBarTitle** — 20 w600 SongMyung. Scaffold AppBar 타이틀 ("관상", "궁합" 등).
  /// `AppTheme.light` 의 `appBarTheme.titleTextStyle` 로 주입되므로 위젯에서
  /// 별도 지정할 필요 없음. inline 사용은 비권장.
  static const TextStyle appBarTitle = TextStyle(
    fontFamily: _kDisplayFont,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// **displaySubtitle** — 16 w400 SongMyung. [display] 바로 아래에 붙는 sub-title.
  /// 홈 화면 hero 영역에서 display 와 시각적으로 한 쌍을 이루는 보조 문구.
  static const TextStyle displaySubtitle = TextStyle(
    fontFamily: _kDisplayFont,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  /// **modalTitle** — 18 w600. AlertDialog title, bottomSheet header.
  static const TextStyle modalTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  /// **sectionTitle** — 16 w600. 리포트 큰 구획 헤딩.
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  /// **subTitle** — 14 w600. 카드 헤더, InfoRow label.
  static const TextStyle subTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  /// **body** — 15 w400 textSecondary. 모달·리포트 본문 단락.
  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.7,
  );

  /// **caption** — 13 w400 textSecondary. 보조 설명·tagline.
  static const TextStyle caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.55,
  );

  /// **hint** — 12 w400 textHint. 한자·메타·percent.
  static const TextStyle hint = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textHint,
    height: 1.4,
  );

  AppText._();
}

/// Material 3 ThemeData — 토큰을 `textTheme`·`appBarTheme` 에 주입.
/// `AppTheme.textPrimary` 등의 색상 alias 는 backward-compat 용으로 유지하되
/// 신규 코드는 [AppColors] 를 직접 참조한다.
class AppTheme {
  // ---- Color aliases (backward-compat with existing call sites) -----------
  static const background = AppColors.background;

  static const surface = AppColors.surface;
  static const border = AppColors.border;
  static const textPrimary = AppColors.textPrimary;
  static const textSecondary = AppColors.textSecondary;
  static const textHint = AppColors.textHint;
  static const accent = AppColors.accent;
  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.grey,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0.5,
          titleTextStyle: AppText.appBarTitle,
        ),
        // TextField outline — Material 3 의 ColorScheme.fromSeed(grey) 가 yellow-
        // green tint primary 를 만들어 focused border 가 녹색으로 나오는 문제
        // 차단. 전역 InputDecorationTheme 으로 명시.
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide:
                const BorderSide(color: AppColors.textPrimary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: AppColors.danger),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide:
                const BorderSide(color: AppColors.danger, width: 1.5),
          ),
          labelStyle: const TextStyle(color: AppColors.textSecondary),
          floatingLabelStyle:
              const TextStyle(color: AppColors.textPrimary),
        ),
        // Material 3 TextTheme slot 에 본 프로젝트 토큰을 매핑.
        // `Theme.of(context).textTheme.titleLarge` 같은 lookup 이 토큰을 반환한다.
        textTheme: const TextTheme(
          displayLarge: AppText.display,
          headlineMedium: AppText.appBarTitle,
          titleLarge: AppText.modalTitle,
          titleMedium: AppText.sectionTitle,
          titleSmall: AppText.subTitle,
          bodyLarge: AppText.body,
          bodyMedium: AppText.caption,
          bodySmall: AppText.hint,
        ),
        useMaterial3: true,
      );

  AppTheme._();
}
