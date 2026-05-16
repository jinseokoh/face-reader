import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Native HW-accelerated image resize. Used for two outputs of the analyze
/// pipeline:
///   * 720px wide  — uploaded to R2 temp/, sent to Python /analyze
///   * 256px wide  — uploaded to R2 thumbnails/ after analyze success
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
}
