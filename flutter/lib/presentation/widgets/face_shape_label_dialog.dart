import 'dart:typed_data';

import 'package:flutter/material.dart';

/// 얼굴형 라벨링 다이얼로그.
///
/// 분석 완료 직후(`_runAnalysis` 마지막 단계)에 띄워 사용자가 정답 얼굴형을
/// 선택하게 한다. 선택값은 `FaceReadingReport.calibrationLabel` 에 저장되어
/// 관상 탭 CSV 내보내기로 Python 재학습 스크립트 입력이 된다.
///
/// Returns: `'wide'` | `'standard'` | `'long'` | `null` (건너뛰기).
Future<String?> showFaceShapeLabelDialog(
  BuildContext context, {
  Uint8List? thumbnailBytes,
}) {
  return showDialog<String>(
    context: context,
    // 실수로 바깥 탭 해서 건너뛰기 되는 걸 방지 — 명시적 선택을 강제.
    barrierDismissible: false,
    builder: (ctx) => _FaceShapeLabelDialog(thumbnailBytes: thumbnailBytes),
  );
}

class _FaceShapeLabelDialog extends StatelessWidget {
  final Uint8List? thumbnailBytes;
  const _FaceShapeLabelDialog({this.thumbnailBytes});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '얼굴형 라벨링',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '분류기 재보정용 데이터입니다',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 16),
            if (thumbnailBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  thumbnailBytes!,
                  width: 180,
                  height: 180,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 20),
            _labelButton(context, 'wide', '가로로 넓은 얼굴형'),
            const SizedBox(height: 10),
            _labelButton(context, 'standard', '표준 얼굴형'),
            const SizedBox(height: 10),
            _labelButton(context, 'long', '세로로 긴 얼굴형'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text(
                '건너뛰기',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelButton(BuildContext context, String value, String label) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => Navigator.of(context).pop(value),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
