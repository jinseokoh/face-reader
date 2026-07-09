import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 내 관상 정체성 헤더 — DESIGN.md §3.7 (Integrated sliver header — 옅은 톤).
/// 관상 탭 sliver header 와 홈 상단이 공유하는 단일 레시피 (§2.5 공용 승격):
///   - background: AppColors.background (white) + bottom 0.5px border
///   - borderRadius: 0 (chrome 의 일부, 카드 chrome 없음)
///   - avatar: 42px + gold 1.5px border
///   - eyebrow: gold / title: textPrimary / caption: textHint
/// [onTap] — 홈에서 설정 시 내 리포트, 미설정 시 셀카 등록 플로우 진입.
/// [unsetCaption] — 미설정 안내 한 줄 (화면별 진입 경로가 달라 인자로 받음).
/// [padding] — 기본은 §3.7 스펙. nudge 배너처럼 위계가 다른 컨테이너만 override.
class MyFaceHeader extends StatelessWidget {
  final FaceReadingReport? myFace;
  final VoidCallback? onTap;
  final String unsetCaption;
  final EdgeInsetsGeometry padding;

  const MyFaceHeader({
    super.key,
    required this.myFace,
    this.onTap,
    this.unsetCaption = '더보기 메뉴를 통해 설정 가능합니다.',
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.md,
    ),
  });

  @override
  Widget build(BuildContext context) {
    final mf = myFace;
    final isSet = mf != null;
    final titleText = isSet
        ? '${mf.ageGroup.labelKo} ${mf.gender.labelKo} '
              '${mf.ethnicity.labelKo}'
        : '내 관상을 설정해주세요.';
    final captionText = isSet ? (mf.alias ?? mf.faceShape.korean) : unsetCaption;
    final content = Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _HeaderAvatar(myFace: myFace),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // eyebrow 는 설정된 정체성에만 — 미설정 nudge 는 문구가 곧 제목.
                if (isSet) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const FaIcon(
                        FontAwesomeIcons.circleCheck,
                        size: 12,
                        color: AppColors.gold,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '내 관상',
                        style: AppText.caption.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.gold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.sectionTitle.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // §0.0.1 title↔subtitle gap = AppSpacing.xs (list item 과 동일).
                const SizedBox(height: AppSpacing.xs),
                Text(
                  captionText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: AppColors.textHint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  final FaceReadingReport? myFace;

  const _HeaderAvatar({required this.myFace});

  @override
  Widget build(BuildContext context) {
    // §3.7 — 다크 hero 의 84px 절반.
    const size = 42.0;
    // 미설정 — 사진 찍는 점술가를 원형 chrome 없이 2배(84) 크기로.
    if (myFace == null) {
      return Image.asset(
        'assets/images/emotion-photo.png',
        width: size * 2,
        height: size * 2,
        fit: BoxFit.contain,
      );
    }
    Widget inner = const _HeaderAvatarPlaceholder();
    final file = ThumbnailPaths.resolveFileSync(myFace?.thumbnailPath);
    if (file != null && file.existsSync()) {
      inner = Image.file(file, width: size, height: size, fit: BoxFit.cover);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold, width: 1.5),
      ),
      child: ClipOval(child: inner),
    );
  }
}

class _HeaderAvatarPlaceholder extends StatelessWidget {
  const _HeaderAvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    // 미설정 상태 — 어깨를 으쓱하는 점술가 (설정 상태의 사진 아바타와 동일 문법).
    return Image.asset('assets/images/shrug.png', fit: BoxFit.cover);
  }
}
