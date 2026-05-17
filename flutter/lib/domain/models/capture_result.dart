import 'dart:typed_data';

import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';

/// 캡처 단계 (camera / album) 가 끝났을 때 분석 단계로 전달되는 raw 데이터.
///
/// `analyzeFaceReading()` 입력에 필요한 모든 것을 담고, demographic
/// (ethnicity·gender·ageGroup) 은 후속 DemographicConfirmScreen 에서 사용자
/// 확인 후 결정한다. 즉 이 객체는 demographic-agnostic.
class CaptureResult {
  /// 정면 캡처에서 추출된 MediaPipe 468 landmark.
  final List<FaceMeshLandmark> frontalLandmarks;

  /// 측면 캡처 (3/4 view) 의 landmark. null = 정면만.
  final List<FaceMeshLandmark>? lateralLandmarks;

  /// 정면 이미지의 픽셀 차원. metric 계산 시 aspect correction 에 사용.
  final int imageWidth;
  final int imageHeight;

  /// 정면 still frame 의 PNG bytes. 썸네일 생성 + DeepFace 분석 입력으로 사용.
  final Uint8List? stillBytes;

  /// 분석 진입 경로 (Hive 저장 시 audit 용).
  final AnalysisSource source;

  const CaptureResult({
    required this.frontalLandmarks,
    this.lateralLandmarks,
    required this.imageWidth,
    required this.imageHeight,
    this.stillBytes,
    required this.source,
  });
}
