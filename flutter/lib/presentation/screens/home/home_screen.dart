import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/data/services/supabase_service.dart';
import 'package:face_reader/domain/models/face_analysis.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/face_metrics_lateral.dart';
import 'package:face_reader/presentation/providers/age_group_provider.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:face_reader/presentation/providers/ethnicity_provider.dart';
import 'package:face_reader/presentation/providers/gender_provider.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';
import 'package:face_reader/presentation/providers/tab_provider.dart';
import 'package:face_reader/presentation/widgets/login_bottom_sheet.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'album_preview_page.dart';
import 'face_mesh_page.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

/// One processed album image — bundle of bytes + landmarks + yaw classification.
class _AlbumPhoto {
  final Uint8List pngBytes;
  final FaceMeshResult meshResult;
  final int width;
  final int height;
  final double yaw;

  _AlbumPhoto({
    required this.pngBytes,
    required this.meshResult,
    required this.width,
    required this.height,
    required this.yaw,
  });
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isProcessing = false;
  OverlayEntry? _topMessageEntry;

  @override
  Widget build(BuildContext context) {
    final ethnicity = ref.watch(ethnicityProvider);
    final ageGroup = ref.watch(ageGroupProvider);
    final gender = ref.watch(genderProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Text(
              '위험한 관상가',
              style: TextStyle(
                fontFamily: 'SongMyung',
                color: AppTheme.textPrimary,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '인상에 담긴 그 운명을 냉정히 풀어 드립니다.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 16, fontFamily: 'SongMyung'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Ethnicity selector
            _buildPickerRow(
              label: '인종',
              value: ethnicity?.labelKo ?? '선택하세요',
              isPlaceholder: ethnicity == null,
              onTap: () => _showCupertinoPicker(
                title: '인종 선택',
                values: Ethnicity.values,
                current: ethnicity,
                labelOf: (e) => e.labelKo,
                onConfirm: (e) =>
                    ref.read(ethnicityProvider.notifier).select(e),
              ),
            ),
            const SizedBox(height: 12),

            // Age group selector
            _buildPickerRow(
              label: '나이',
              value: ageGroup?.labelKo ?? '선택하세요',
              isPlaceholder: ageGroup == null,
              onTap: () => _showCupertinoPicker(
                title: '나이 선택',
                // 10대~70대 선택 가능 (eighties/nineties는 enum에 남기되 UI에서 제외)
                values: AgeGroup.values
                    .where((e) => e.index <= AgeGroup.seventies.index)
                    .toList(),
                current: ageGroup,
                labelOf: (e) => e.labelKo,
                onConfirm: (e) =>
                    ref.read(ageGroupProvider.notifier).select(e),
              ),
            ),
            const SizedBox(height: 12),

            // Gender selector
            _buildPickerRow(
              label: '성별',
              value: gender?.labelKo ?? '선택하세요',
              isPlaceholder: gender == null,
              onTap: () => _showCupertinoPicker(
                title: '성별 선택',
                values: Gender.values,
                current: gender,
                labelOf: (e) => e.labelKo,
                onConfirm: (e) =>
                    ref.read(genderProvider.notifier).select(e),
              ),
            ),
            const SizedBox(height: 24),

            // Camera & Album buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Builder(builder: (context) {
                final ready = ethnicity != null &&
                    ageGroup != null &&
                    gender != null;
                return Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: ready ? _openCamera : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppTheme.border),
                        ),
                      ),
                      child: const Text(
                        '카메라 열기',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: (_isProcessing || !ready) ? null : _openAlbum,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppTheme.textPrimary,
                        disabledBackgroundColor: AppTheme.surface,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppTheme.border),
                        ),
                      ),
                      child: _isProcessing
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.textHint,
                              ),
                            )
                          : const Text(
                              '앨범 열기',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                ],
              );
              }),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dismissTopMessage();
    super.dispose();
  }

  Widget _buildPickerRow({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool isPlaceholder = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 15)),
              Row(
                children: [
                  Text(value,
                      style: TextStyle(
                          color: isPlaceholder
                              ? AppTheme.textHint
                              : AppTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Icon(CupertinoIcons.chevron_down,
                      color: AppTheme.textHint, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _dismissTopMessage() {
    _topMessageEntry?.remove();
    _topMessageEntry = null;
  }

  Future<void> _openAlbum() async {
    if (!ref.read(authProvider.notifier).isLoggedIn) {
      final loggedIn = await showLoginBottomSheet(context, ref);
      if (!loggedIn) return;
    }

    final picker = ImagePicker();

    // Step 1: frontal photo
    _showTopMessage('정면 사진을 선택하세요.');
    final frontalPick = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (frontalPick == null) {
      _dismissTopMessage();
      return;
    }

    setState(() => _isProcessing = true);
    _AlbumPhoto frontal;
    try {
      frontal = await _processAlbumPhoto(frontalPick.path);
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        _dismissTopMessage();
        _showError(e.toString());
      }
      return;
    }
    if (!mounted) return;
    setState(() => _isProcessing = false);

    // Preview must not show the top snackbar.
    _dismissTopMessage();
    // Show frontal preview; user taps "정면 분석" to continue to lateral step.
    final frontalConfirmed = await _showPreview(
      phase: AlbumPreviewPhase.frontal,
      photo: frontal,
    );
    if (!mounted || frontalConfirmed != true) return;

    // Step 2: lateral photo (OPTIONAL — 콧부리 분석 전용)
    // 생략 시 코 모양은 "정상 범주"로 fallback.
    final wantLateral = await _askAttachLateral();
    _AlbumPhoto? lateral;
    if (wantLateral == true) {
      _showTopMessage('두눈은 보이지만, 한쪽 귀가 살짝 안보이는 측면(3/4)사진을 올려주세요.');
      final lateralPick = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (lateralPick != null) {
        setState(() => _isProcessing = true);
        try {
          lateral = await _processAlbumPhoto(lateralPick.path);
        } catch (e) {
          if (mounted) {
            setState(() => _isProcessing = false);
            _dismissTopMessage();
            _showError(e.toString());
          }
          return;
        }
        if (!mounted) return;
        setState(() => _isProcessing = false);

        _dismissTopMessage();
        final lateralConfirmed = await _showPreview(
          phase: AlbumPreviewPhase.lateral,
          photo: lateral,
        );
        if (!mounted || lateralConfirmed != true) return;
      }
    }

    _dismissTopMessage();
    await _runAnalysis(frontal: frontal, lateral: lateral);
  }

  /// 측면(3/4) 사진 첨부 여부 확인. cancel이면 null.
  Future<bool?> _askAttachLateral() async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('측면 사진 첨부'),
        content: const Text(
            '코 모양 분석을 위해 3/4 측면 사진을 추가하시겠습니까?\n'
            '추가하지 않으면 코는 "정상 범주"로 처리됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('건너뛰기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('측면 추가'),
          ),
        ],
      ),
    );
  }

  void _openCamera() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const FaceMeshPage(),
    );
  }

  /// Run the full ML-Kit-bbox + MediaPipe pipeline on a single image file and
  /// return everything needed to either display it or analyze it.
  Future<_AlbumPhoto> _processAlbumPhoto(String path) async {
    // ML Kit: face bbox
    final inputImage = InputImage.fromFilePath(path);
    final faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    final faces = await faceDetector.processImage(inputImage);
    await faceDetector.close();

    if (faces.isEmpty) {
      throw Exception('얼굴을 찾을 수 없습니다.\n다른 사진을 선택해 주세요.');
    }

    // Decode → raw RGBA
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData =
        await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) throw Exception('이미지를 디코딩할 수 없습니다');
    final rgba = Uint8List.sublistView(byteData.buffer.asUint8List());

    // BBox clamped + scaled
    final bbox = faces.first.boundingBox;
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final clamped = Rect.fromLTRB(
      bbox.left.clamp(0.0, imgW),
      bbox.top.clamp(0.0, imgH),
      bbox.right.clamp(0.0, imgW),
      bbox.bottom.clamp(0.0, imgH),
    );
    final box = FaceMeshBox.fromLTWH(
      left: clamped.left,
      top: clamped.top,
      width: clamped.width,
      height: clamped.height,
    );

    // MediaPipe single-frame inference
    final processor = await FaceMeshProcessor.create(
      delegate: FaceMeshDelegate.xnnpack,
      enableRoiTracking: false,
      minDetectionConfidence: 0.5,
      minTrackingConfidence: 0.5,
    );
    final meshImage = FaceMeshImage(
      pixels: rgba,
      width: image.width,
      height: image.height,
    );
    final result = processor.process(
      meshImage,
      box: box,
      boxScale: 1.2,
      boxMakeSquare: true,
      rotationDegrees: 0,
    );
    processor.close();

    if (result.landmarks.isEmpty) {
      throw Exception('얼굴 랜드마크를 추출할 수 없습니다.\n다른 사진을 선택해 주세요.');
    }

    // Re-encode for display
    final pngData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (pngData == null) throw Exception('이미지 인코딩 실패');
    final pngBytes = Uint8List.sublistView(pngData.buffer.asUint8List());

    final yaw = estimateYaw(result.landmarks);
    debugPrint('[Album] processed image=${image.width}x${image.height} '
        'yaw=${yaw.toStringAsFixed(3)} class=${classifyYaw(yaw)}');

    return _AlbumPhoto(
      pngBytes: pngBytes,
      meshResult: result,
      width: image.width,
      height: image.height,
      yaw: yaw,
    );
  }

  Future<void> _runAnalysis({
    required _AlbumPhoto frontal,
    _AlbumPhoto? lateral,
  }) async {
    final ethnicity = ref.read(ethnicityProvider)!;
    final gender = ref.read(genderProvider)!;
    final ageGroup = ref.read(ageGroupProvider)!;

    final report = analyzeFaceReading(
      landmarks: frontal.meshResult.landmarks,
      ethnicity: ethnicity,
      gender: gender,
      ageGroup: ageGroup,
      source: AnalysisSource.album,
      imageWidth: frontal.width,
      imageHeight: frontal.height,
      lateralLandmarks: lateral?.meshResult.landmarks,
    );

    final id = const Uuid().v4();
    report.supabaseId = id;

    try {
      final compressed = await FlutterImageCompress.compressWithList(
        frontal.pngBytes,
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

    if (!mounted) return;
    ref.read(historyProvider.notifier).add(report);
    ref.read(historyTabProvider.notifier).selectTab(1);
    ref.read(selectedTabProvider.notifier).selectTab(1);
    SupabaseService().saveMetrics(report).catchError((e) {
      debugPrint('[Supabase] save error: $e');
      return '';
    });
  }

  void _showCupertinoPicker<T>({
    required String title,
    required List<T> values,
    required T? current,
    required String Function(T) labelOf,
    required void Function(T) onConfirm,
  }) {
    var tempIndex = current == null ? 0 : values.indexOf(current);

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
                    child: Text('취소',
                        style: TextStyle(color: AppTheme.textHint)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(title,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    child: Text('확인',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.w600)),
                    onPressed: () {
                      onConfirm(values[tempIndex]);
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Divider(color: AppTheme.border, height: 1),
            Expanded(
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(
                    initialItem: current == null ? 0 : values.indexOf(current)),
                itemExtent: 40,
                onSelectedItemChanged: (index) => tempIndex = index,
                children: values
                    .map((e) => Center(
                          child: Text(labelOf(e),
                              style: TextStyle(
                                  color: AppTheme.textPrimary, fontSize: 18)),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  Future<bool?> _showPreview({
    required AlbumPreviewPhase phase,
    required _AlbumPhoto photo,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AlbumPreviewPage(
        imageBytes: photo.pngBytes,
        meshResult: photo.meshResult,
        imageWidth: photo.width,
        imageHeight: photo.height,
        phase: phase,
        onConfirm: () => Navigator.of(ctx).pop(true),
      ),
    );
  }

  void _showTopMessage(String msg) {
    _dismissTopMessage();
    final mq = MediaQuery.of(context);
    final entry = OverlayEntry(
      builder: (ctx) => Positioned(
        top: mq.padding.top + 12,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.textPrimary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              msg,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(entry);
    _topMessageEntry = entry;
  }
}
