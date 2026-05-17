import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Native HW-accelerated image resize. Used for two outputs of the analyze
/// pipeline:
///   * 720px wide   — uploaded to R2 temp/, sent to Python /analyze
///   * 256×256 sq   — face-centered crop, uploaded to R2 thumbnails/ after
///                    analyze success
///
/// JPEG output is the default since R2 storage cost matters and the analysis
/// model is happy with mild compression.
class ImageResizer {
  static const _kJpegQuality = 85;

  ImageResizer._();

  /// Resize an in-memory image to the given width (height auto-scaled).
  /// Returns JPEG bytes ready for upload.
  static Future<Uint8List> resizeToWidth(
    Uint8List input, {
    required int width,
    int quality = _kJpegQuality,
  }) async {
    final result = await FlutterImageCompress.compressWithList(
      input,
      minWidth: width,
      // minHeight 무한대 효과 — 가로 폭만 강제하고 비율은 그대로 유지.
      minHeight: 1,
      quality: quality,
      format: CompressFormat.jpeg,
      // EXIF rotation 보존 → portrait 사진이 90° 돌아 저장되는 문제 차단.
      keepExif: false,
      autoCorrectionAngle: true,
    );
    return Uint8List.fromList(result);
  }

  /// 얼굴 중심을 기준으로 정사각형 crop 후 [outSize]×[outSize] 로 다운스케일
  /// 한 JPEG bytes 반환.
  ///
  /// ML Kit FaceDetector 로 bbox 를 찾고 [padding] 비율만큼 여백을 더한 square
  /// 영역을 image bounds 안에 clamp 한다. ML Kit 가 얼굴을 못 찾으면 image
  /// 의 정중앙을 기준으로 square crop 으로 fallback — 어쨌든 결과는 항상
  /// [outSize]×[outSize].
  ///
  /// 흐름: ML Kit → dart:ui Canvas drawImageRect (crop + scale 동시 처리) →
  /// PNG → flutter_image_compress 로 JPG 재인코딩.
  static Future<Uint8List> faceCenterSquareCrop(
    File file, {
    int outSize = 256,
    double padding = 0.25,
    int quality = _kJpegQuality,
  }) async {
    // 1) bbox 검출 — 실패해도 throw 안 함, fallback 으로 image-center 사용.
    Rect? faceBox;
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
      ),
    );
    try {
      final faces = await detector
          .processImage(InputImage.fromFilePath(file.path));
      if (faces.isNotEmpty) faceBox = faces.first.boundingBox;
    } catch (_) {
      // detector 실패 — fallback path 로.
    } finally {
      await detector.close();
    }

    // 2) image 디코드.
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();

    // 3) 얼굴 중심 square 영역 산출.
    final double cx;
    final double cy;
    final double faceSize;
    if (faceBox != null) {
      cx = faceBox.center.dx;
      cy = faceBox.center.dy;
      faceSize = math.max(faceBox.width, faceBox.height);
    } else {
      cx = imgW / 2;
      cy = imgH / 2;
      faceSize = math.min(imgW, imgH) * 0.7;
    }
    final maxCrop = math.min(imgW, imgH);
    final cropSize = math.min(faceSize * (1.0 + padding * 2), maxCrop);
    final left = (cx - cropSize / 2).clamp(0.0, imgW - cropSize);
    final top = (cy - cropSize / 2).clamp(0.0, imgH - cropSize);
    final srcRect = Rect.fromLTWH(left, top, cropSize, cropSize);

    // 4) Canvas 로 crop + scale 동시 처리.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final dst = Rect.fromLTWH(0, 0, outSize.toDouble(), outSize.toDouble());
    canvas.drawImageRect(
      image,
      srcRect,
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final outImage = await picture.toImage(outSize, outSize);
    final pngData = await outImage.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    outImage.dispose();
    if (pngData == null) {
      throw StateError('faceCenterSquareCrop: PNG encode 실패');
    }
    final png = Uint8List.sublistView(pngData.buffer.asUint8List());

    // 5) PNG → JPG (R2 thumbnails/ 는 JPG SSOT).
    final jpg = await FlutterImageCompress.compressWithList(
      png,
      minWidth: outSize,
      minHeight: outSize,
      quality: quality,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
    return Uint8List.fromList(jpg);
  }
}
