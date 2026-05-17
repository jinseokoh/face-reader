import 'dart:io';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/services/supabase_service.dart';
import 'package:face_reader/domain/models/capture_result.dart';
import 'package:face_reader/domain/models/face_analysis.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';
import 'package:face_reader/presentation/providers/tab_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
class DemographicConfirmScreen extends ConsumerStatefulWidget {
  final CaptureResult capture;
  final Ethnicity initialEthnicity;
  final Gender initialGender;
  final AgeGroup initialAgeGroup;

  const DemographicConfirmScreen({
    super.key,
    required this.capture,
    this.initialEthnicity = Ethnicity.eastAsian,
    this.initialGender = Gender.female,
    this.initialAgeGroup = AgeGroup.thirties,
  });

  @override
  ConsumerState<DemographicConfirmScreen> createState() =>
      _DemographicConfirmScreenState();
}

class _DemographicConfirmScreenState
    extends ConsumerState<DemographicConfirmScreen> {
  late Ethnicity _ethnicity;
  late Gender _gender;
  late AgeGroup _ageGroup;
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _ethnicity = widget.initialEthnicity;
    _gender = widget.initialGender;
    _ageGroup = widget.initialAgeGroup;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: AppColors.textPrimary),
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
                '추정된 정보가 맞나요?',
                style: AppText.display,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '잘못된 항목은 직접 수정해 주세요.',
                style: AppText.body.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _PickerRow(
                label: '인종',
                value: _ethnicity.labelKo,
                onTap: () => _showPicker<Ethnicity>(
                  title: '인종 선택',
                  values: Ethnicity.values,
                  current: _ethnicity,
                  labelOf: (e) => e.labelKo,
                  onConfirm: (e) => setState(() => _ethnicity = e),
                ),
              ),
              const SizedBox(height: 12),
              _PickerRow(
                label: '성별',
                value: _gender.labelKo,
                onTap: () => _showPicker<Gender>(
                  title: '성별 선택',
                  values: Gender.values,
                  current: _gender,
                  labelOf: (e) => e.labelKo,
                  onConfirm: (e) => setState(() => _gender = e),
                ),
              ),
              const SizedBox(height: 12),
              _PickerRow(
                label: '나이대',
                value: _ageGroup.labelKo,
                onTap: () => _showPicker<AgeGroup>(
                  title: '나이대 선택',
                  values: AgeGroup.values
                      .where((e) => e.index <= AgeGroup.seventies.index)
                      .toList(),
                  current: _ageGroup,
                  labelOf: (e) => e.labelKo,
                  onConfirm: (e) => setState(() => _ageGroup = e),
                ),
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

  /// 확인된 demographic 으로 full pipeline 실행.
  Future<void> _runFullAnalysis() async {
    setState(() => _isAnalyzing = true);

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

    final id = const Uuid().v4();
    report.supabaseId = id;

    // 썸네일 생성 (있을 때만)
    final still = c.stillBytes;
    if (still != null) {
      try {
        final compressed = await FlutterImageCompress.compressWithList(
          still,
          minWidth: 128,
          minHeight: 128,
          quality: 80,
          format: CompressFormat.webp,
        );
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$id.webp');
        await file.writeAsBytes(compressed);
        report.thumbnailPath = file.path;
      } catch (e) {
        debugPrint('[Thumbnail] save error: $e');
      }
    }

    if (!mounted) return;
    ref.read(historyProvider.notifier).add(report);
    ref.read(historyTabProvider.notifier).selectTab(
        c.source == AnalysisSource.camera ? 0 : 1);
    ref.read(selectedTabProvider.notifier).selectTab(1);

    SupabaseService().saveMetrics(report).catchError((e) {
      debugPrint('[Supabase] save error: $e');
      return '';
    });

    if (!mounted) return;
    Navigator.of(context).pop();
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
}

class _PickerRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _PickerRow(
      {required this.label, required this.value, required this.onTap});

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
                Text(value,
                    style: AppText.body
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                const Icon(CupertinoIcons.chevron_down,
                    color: AppColors.textHint, size: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
