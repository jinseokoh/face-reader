import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/presentation/providers/age_group_provider.dart';
import 'package:face_reader/presentation/providers/ethnicity_provider.dart';
import 'package:face_reader/presentation/providers/gender_provider.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:face_reader/presentation/widgets/login_bottom_sheet.dart';

import 'album_preview_page.dart';
import 'face_mesh_page.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isProcessing = false;

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
              value: ethnicity.labelKo,
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
              value: ageGroup.labelKo,
              onTap: () => _showCupertinoPicker(
                title: '나이 선택',
                values: AgeGroup.values,
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
              value: gender.labelKo,
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
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _openCamera,
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
                      onPressed: _isProcessing ? null : _openAlbum,
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickerRow({
    required String label,
    required String value,
    required VoidCallback onTap,
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
                          color: AppTheme.textPrimary,
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

  Future<void> _openAlbum() async {
    if (!ref.read(authProvider.notifier).isLoggedIn) {
      final loggedIn = await showLoginBottomSheet(context, ref);
      if (!loggedIn) return;
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (picked == null) return;

    setState(() => _isProcessing = true);

    try {
      // Step 1: Detect face bounding box with ML Kit
      final inputImage = InputImage.fromFilePath(picked.path);
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

      // Step 2: Decode image to raw RGBA pixels
      final bytes = await File(picked.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) throw Exception('이미지를 디코딩할 수 없습니다');

      // dart:ui rawRgba is already RGBA – pass directly (no BGRA conversion needed)
      final rgba = Uint8List.sublistView(byteData.buffer.asUint8List());

      // Step 3: Build face bounding box for mediapipe
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

      // Step 4: Single-frame inference with mediapipe + bounding box
      final processor = await FaceMeshProcessor.create(
        delegate: FaceMeshDelegate.xnnpack,
        enableRoiTracking: false,
        minDetectionConfidence: 0.5,
        minTrackingConfidence: 0.5,
      );

      debugPrint('[Album] image=${image.width}x${image.height} '
          'rgba.length=${rgba.length} '
          'expected=${image.width * image.height * 4} '
          'bbox=$bbox clamped=$clamped '
          'platform=${Platform.operatingSystem}');

      // Both platforms: use RGBA + process() for static images
      // (matches plugin author's static image example)
      final meshImage = FaceMeshImage(
        pixels: rgba,
        width: image.width,
        height: image.height,
      );
      debugPrint('[Album] calling process...');
      final result = processor.process(
        meshImage,
        box: box,
        boxScale: 1.2,
        boxMakeSquare: true,
        rotationDegrees: 0,
      );
      debugPrint('[Album] landmarks=${result.landmarks.length} '
          'score=${result.score.toStringAsFixed(4)}');
      processor.close();

      if (result.landmarks.isEmpty) {
        throw Exception('얼굴 랜드마크를 추출할 수 없습니다.\n다른 사진을 선택해 주세요.');
      }

      // Step 5: Encode decoded image to PNG for display
      // (avoids EXIF rotation mismatch between dart:ui and Image.file)
      final pngData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (pngData == null) throw Exception('이미지 인코딩 실패');
      final pngBytes = Uint8List.sublistView(pngData.buffer.asUint8List());

      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => AlbumPreviewPage(
          imageBytes: pngBytes,
          meshResult: result,
          imageWidth: image.width,
          imageHeight: image.height,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
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

  void _showCupertinoPicker<T>({
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
                    initialItem: values.indexOf(current)),
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
}
