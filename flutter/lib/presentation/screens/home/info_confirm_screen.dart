import 'dart:io';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/data/services/image_resizer.dart';
import 'package:facely/data/services/supabase_service.dart';
import 'package:facely/domain/models/capture_result.dart';
import 'package:facely/domain/models/face_analysis.dart';
import 'package:facely/domain/models/face_metadata.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/tab_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 캡처 직후 demographic 확인·수정 화면.
///
/// `CaptureResult` 의 raw landmark·image 를 받아 사용자가 ethnicity·gender·
/// ageGroup 을 확인/수정한 뒤 [_runFullAnalysis] 에서 `analyzeFaceReading()`
/// 실행 + 썸네일 생성 + Hive history 저장 + Supabase publish.
///
/// 다음 turn 에 DeepFace 통합 시 [initial...] 인자를 DeepFace 응답으로 채울
/// 예정. 지금은 sensible default (eastAsian / female / thirties) 로 prefill.
class InfoConfirmScreen extends ConsumerStatefulWidget {
  final CaptureResult capture;
  final Ethnicity initialEthnicity;
  final Gender initialGender;
  final AgeGroup initialAgeGroup;
  // DeepFace background 결과. resolve 되면 사용자가 picker 를 만지지 않은 한
  // 자동으로 prefill. null 이면 default 그대로 유지.
  final Future<FaceMetadata?>? metadataFuture;

  const InfoConfirmScreen({
    super.key,
    required this.capture,
    this.initialEthnicity = Ethnicity.eastAsian,
    this.initialGender = Gender.female,
    this.initialAgeGroup = AgeGroup.thirties,
    this.metadataFuture,
  });

  @override
  ConsumerState<InfoConfirmScreen> createState() =>
      _InfoConfirmScreenState();
}

class _InfoConfirmScreenState
    extends ConsumerState<InfoConfirmScreen> {
  late Ethnicity _ethnicity;
  late Gender _gender;
  late AgeGroup _ageGroup;
  bool _isAnalyzing = false;
  // DeepFace background 진행 중 표시. future 가 resolve 되면 false.
  bool _inferring = false;
  // 사용자가 picker 하나라도 만진 적 있는가. 만졌으면 DeepFace 결과로 덮지
  // 않음 — 사용자가 명시적으로 수정한 값을 존중.
  bool _userTouched = false;
  // 마지막에 자동 prefill 된 값 (UI 에 "AI 가 추정: …" 보조 라인용).
  FaceMetadata? _inferred;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const FaIcon(FontAwesomeIcons.xmark, color: AppColors.textPrimary, size: 20),
          onPressed: _isAnalyzing ? null : () => Navigator.of(context).pop(),
        ),
        title: const Text('정보 확인'),
        titleTextStyle: AppText.appBarTitle,
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              const Text(
                '추정 정보가 맞나요?',
                style: AppText.display,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '인공지능은 실수할 수 있습니다.',
                style: AppText.body.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _PickerRow(
                label: '인종',
                value: _ethnicity.labelKo,
                inferring: _inferring && !_userTouched,
                onTap: () => _showPicker<Ethnicity>(
                  title: '인종 선택',
                  values: Ethnicity.values,
                  current: _ethnicity,
                  labelOf: (e) => e.labelKo,
                  onConfirm: (e) => _touchAndSet(() => _ethnicity = e),
                ),
              ),
              const SizedBox(height: 12),
              _PickerRow(
                label: '성별',
                value: _gender.labelKo,
                inferring: _inferring && !_userTouched,
                onTap: () => _showPicker<Gender>(
                  title: '성별 선택',
                  values: Gender.values,
                  current: _gender,
                  labelOf: (e) => e.labelKo,
                  onConfirm: (e) => _touchAndSet(() => _gender = e),
                ),
              ),
              const SizedBox(height: 12),
              _PickerRow(
                label: '나이대',
                value: _ageGroup.labelKo,
                inferring: _inferring && !_userTouched,
                onTap: () => _showPicker<AgeGroup>(
                  title: '나이대 선택',
                  values: AgeGroup.values
                      .where((e) => e.index <= AgeGroup.seventies.index)
                      .toList(),
                  current: _ageGroup,
                  labelOf: (e) => e.labelKo,
                  onConfirm: (e) => _touchAndSet(() => _ageGroup = e),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '잘못된 항목은 직접 수정해 주세요.',
                style: AppText.body.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _isAnalyzing ? null : _runFullAnalysis,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.surface,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isAnalyzing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        '분석 시작',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _ethnicity = widget.initialEthnicity;
    _gender = widget.initialGender;
    _ageGroup = widget.initialAgeGroup;

    final f = widget.metadataFuture;
    if (f != null) {
      _inferring = true;
      f.then((meta) {
        if (!mounted) return;
        setState(() {
          _inferring = false;
          _inferred = meta;
          if (meta == null || _userTouched) return;
          // 사용자가 picker 만지지 않은 경우에만 prefill.
          final e = meta.ethnicityEnum;
          final g = meta.genderEnum;
          if (e != null) _ethnicity = e;
          if (g != null) _gender = g;
          _ageGroup = meta.ageGroupEnum;
        });
      });
    }
  }

  /// 확인된 demographic 으로 full pipeline 실행.
  ///
  /// **stuck 방지 contract** —
  /// (1) metadata 대기는 8초 timeout. 안 끝나면 metadata 없이 진행. 사용자가
  ///     "분석 시작" 누르고 무한정 spinner 만 돌아가는 케이스 차단.
  /// (2) 모든 예외 path 에서 `_isAnalyzing` 가 false 로 reset 보장 (try/finally).
  ///     이전엔 metadataFuture 가 throw 하면 영구히 spinner 상태로 stuck.
  /// metadata timeout 시 thumbnailKey 는 null — 카카오 공유는 영향 없음
  /// (uploadImage 경로), 웹 OG preview 만 logo.png 로 fallback.
  Future<void> _runFullAnalysis() async {
    setState(() => _isAnalyzing = true);
    try {
      if (_inferring && widget.metadataFuture != null) {
        try {
          final meta = await widget.metadataFuture!
              .timeout(const Duration(seconds: 8));
          if (!mounted) return;
          if (meta != null) _inferred = meta;
        } catch (e) {
          // timeout / network 에러 / API 실패 — metadata 없이 진행.
          debugPrint('[DemographicConfirm] metadata wait failed: $e');
        }
      }

      final c = widget.capture;
      final report = analyzeFaceReading(
        landmarks: c.frontalLandmarks,
        ethnicity: _ethnicity,
        gender: _gender,
        ageGroup: _ageGroup,
        source: c.source,
        imageWidth: c.imageWidth,
        imageHeight: c.imageHeight,
        lateralLandmarks: c.lateralLandmarks,
      );

      // metadata.uuid 가 있으면 그걸 supabaseId 로 그대로 사용 (R2 thumbnailKey 의
      // uuid 부분과 매칭되어야 single trace id 유지). 없으면 fallback v4.
      final id = _inferred?.uuid ?? const Uuid().v4();
      report.supabaseId = id;
      // R2 영구 thumbnail 의 path key — analyze 시점에 이미 PUT 됨.
      // Worker SSR 의 og:image 가 `cdn.facely.kr/${thumbnailKey}` 로 조립.
      report.thumbnailKey = _inferred?.thumbnailKey;

      // 썸네일 생성 — ML Kit bbox 기반 face-centered 256 square crop.
      // 단순 비례 축소 (FlutterImageCompress) 만 하면 album path 의 square-padded
      // 1024×1024 이미지가 그대로 작아지면서 face 가 가운데 점처럼 보이는 문제 발생.
      // faceCenterSquareCrop 가 ML Kit 으로 face 위치를 찾아 padding 25% 둘러
      // 200×200 으로 출력 → 사용자가 보는 thumbnail 은 항상 얼굴 중심.
      final still = c.stillBytes;
      if (still != null) {
        try {
          final cropped = await ImageResizer.faceCenterSquareCropFromBytes(
            still,
            outSize: 200,
          );
          final dir = await getApplicationDocumentsDirectory();
          final file = File('${dir.path}/$id.jpg');
          await file.writeAsBytes(cropped);
          // 절대경로 박지 말 것 — iOS sandbox UUID 회전 / Android applicationId
          // 변경 시 stale 됨. filename 만 저장 → 읽을 때 ThumbnailPaths 가 현재
          // documents dir 와 조립.
          report.thumbnailPath = '$id.jpg';
        } catch (e) {
          debugPrint('[Thumbnail] save error: $e');
        }
      }

      if (!mounted) return;
      ref.read(historyProvider.notifier).add(report);
      // 분석을 마친 모든 카드는 기본으로 metrics row 생성 (썸네일은 analyze
      // 시점에 이미 R2 업로드됨). 비로그인이면 user_id=null 로 익명 저장되고,
      // 이후 로그인 시 HistoryNotifier 가 일괄 claim 한다. fire-and-forget —
      // 네트워크/RLS 실패가 화면 전환을 막지 않도록 await 하지 않는다.
      SupabaseService().saveMetrics(report).catchError((Object e) {
        debugPrint('[InfoConfirm] saveMetrics error: $e');
        return report.supabaseId ?? '';
      });
      ref.read(historyTabProvider.notifier).selectTab(
          c.source == AnalysisSource.camera ? 0 : 1);
      ref.read(selectedTabProvider.notifier).selectTab(1);

      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _showPicker<T>({
    required String title,
    required List<T> values,
    required T current,
    required String Function(T) labelOf,
    required void Function(T) onConfirm,
  }) {
    var tempIndex = values.indexOf(current);
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 280,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('취소',
                        style: TextStyle(color: AppColors.textHint)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(title,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: const Text('확인',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    onPressed: () {
                      onConfirm(values[tempIndex]);
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            Expanded(
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(
                    initialItem: values.indexOf(current)),
                itemExtent: 40,
                onSelectedItemChanged: (index) => tempIndex = index,
                children: values
                    .map((v) => Center(
                          child: Text(labelOf(v),
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 18)),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// picker 한 항목이 바뀌면 userTouched flag 켜고 setState 로 값 반영.
  void _touchAndSet(VoidCallback updater) {
    setState(() {
      _userTouched = true;
      updater();
    });
  }
}

class _PickerRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  // DeepFace 결과 대기 중 — value 자리에 spinner + "추정 중..." 표시.
  // default 값(eastAsian/female/thirties) 이 잠깐 보였다가 추정치로 깜빡이는
  // 혼란을 차단. tap 은 허용 — 만지면 _userTouched=true 되어 추정값으로 덮지
  // 않으므로 사용자 선택 존중 로직과 자연스럽게 연동.
  final bool inferring;
  const _PickerRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.inferring = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: AppText.body.copyWith(color: AppColors.textSecondary)),
            Row(
              children: [
                if (inferring) ...[
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.textHint),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('추정 중...',
                      style: AppText.body.copyWith(
                          color: AppColors.textHint,
                          fontWeight: FontWeight.w500)),
                ] else
                  Text(value,
                      style: AppText.body
                          .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                const FaIcon(FontAwesomeIcons.chevronDown,
                    color: AppColors.textHint, size: 12),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
