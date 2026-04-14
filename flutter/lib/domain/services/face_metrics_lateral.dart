import 'dart:math';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';
import 'package:face_reader/domain/services/face_metrics.dart';

/// Lateral / 3-4-view facial metrics.
///
/// Computed from a SEPARATE capture taken with the head rotated ~30-45 degrees
/// yaw. At that angle, sagittal-plane structures (nose bridge convexity, chin
/// projection, lip protrusion) project into the image plane and become
/// measurable from a 2D MediaPipe Face Mesh.
///
/// Aquiline-nose detection is a BINARY flag (no continuous Korean baseline
/// exists in the literature) — see [aquilineNoseFlag].
class LateralFaceMetrics {
  final List<FaceMeshLandmark> landmarks;

  LateralFaceMetrics(this.landmarks);

  FaceMeshLandmark _lm(int i) => landmarks[i];

  double _dist2D(int a, int b) {
    final la = _lm(a);
    final lb = _lm(b);
    final dx = la.x - lb.x;
    final dy = la.y - lb.y;
    return sqrt(dx * dx + dy * dy);
  }

  /// Angle in degrees at vertex v between rays v→a and v→b.
  double _angleAt(int v, int a, int b) {
    final pv = _lm(v);
    final pa = _lm(a);
    final pb = _lm(b);
    final ax = pa.x - pv.x;
    final ay = pa.y - pv.y;
    final bx = pb.x - pv.x;
    final by = pb.y - pv.y;
    final dot = ax * bx + ay * by;
    final magA = sqrt(ax * ax + ay * ay);
    final magB = sqrt(bx * bx + by * by);
    if (magA == 0 || magB == 0) return 0;
    final c = (dot / (magA * magB)).clamp(-1.0, 1.0);
    return acos(c) * (180.0 / pi);
  }

  /// Signed perpendicular distance from point p to line through (a, b),
  /// normalized by face height. Positive = on one side, negative = the other.
  /// Sign is determined by 2D cross product, so consistency depends on the
  /// reference frame; use abs() if direction doesn't matter.
  double _perpDistNormalized(int p, int lineA, int lineB) {
    final pp = _lm(p);
    final pa = _lm(lineA);
    final pb = _lm(lineB);
    final dx = pb.x - pa.x;
    final dy = pb.y - pa.y;
    final len = sqrt(dx * dx + dy * dy);
    if (len == 0) return 0;
    final cross = (dx * (pa.y - pp.y) - (pa.x - pp.x) * dy) / len;
    return cross / faceHeight;
  }

  double get faceHeight =>
      _dist2D(LandmarkIndex.foreheadTop, LandmarkIndex.chin);

  // ─── 7 continuous lateral metrics ───

  /// 비전두각 — angle at nasion between forehead direction and nose tip.
  /// Vertex = 168 (nasion), rays to 10 (foreheadTop / glabella proxy) and
  /// 1 (noseTip). Korean adult mean ~131 deg M / 141 deg F.
  double get nasofrontalAngle =>
      _angleAt(LandmarkIndex.nasion, LandmarkIndex.foreheadTop, LandmarkIndex.noseTip);

  /// 비순각 (tip-rotation proxy) — angle at subnasale (94) between rays to
  /// noseTip (1) and upperLipTop (0).
  ///
  /// NOTE: This is NOT the strict clinical nasolabial angle. Without a proper
  /// upper-lip-tangent landmark in MediaPipe's mesh, we use the 94→0 direction
  /// (roughly downward) as the lip reference. Consequences:
  ///   - Normal noses measure ~130-140° (not the clinical ~98°).
  ///   - Upturned (snub) noses push toward 160°+.
  ///   - Drooping tips pull toward 100°.
  /// Reference data and thresholds in face_reference_data.dart / analysis are
  /// calibrated to THIS measurement, not to clinical NLA. Do not compare to
  /// clinical norms directly.
  double get nasolabialAngle => _angleAt(
      LandmarkIndex.subnasale, LandmarkIndex.noseTip, LandmarkIndex.upperLipTop);

  /// 안면 돌출각 (G-Sn-Pog) — soft-tissue facial convexity.
  /// Vertex = 94 (subnasale) as a proxy for soft-tissue subnasale,
  /// rays to 10 (glabella proxy) and 152 (chin/pogonion).
  /// Reported as deviation from 180 deg (straight profile).
  /// Korean adult mean ~7.7 deg of convexity.
  double get facialConvexity {
    final raw = _angleAt(LandmarkIndex.subnasale, LandmarkIndex.foreheadTop, LandmarkIndex.chin);
    return 180.0 - raw;
  }

  /// 상순 E-line 거리 — perpendicular distance from upperLipTop (0)
  /// to E-line from noseTip (1) to chin (152). Normalized by faceHeight.
  /// Korean adult ~ -1mm on a typical face. We report normalized; reference
  /// data is stored in the same normalized convention.
  double get upperLipEline =>
      _perpDistNormalized(LandmarkIndex.upperLipTop, LandmarkIndex.noseTip, LandmarkIndex.chin);

  /// 하순 E-line 거리 — perpendicular distance from lowerLipBottom (17) to E-line.
  double get lowerLipEline =>
      _perpDistNormalized(LandmarkIndex.lowerLipBottom, LandmarkIndex.noseTip, LandmarkIndex.chin);

  /// 순이각 — labiomental / mentolabial angle.
  /// Vertex = 17 (lowerLipBottom) as proxy for mentolabial fold,
  /// rays to 14 (lowerLipInner) and 152 (chin).
  /// East Asian mean ~134 deg.
  double get mentolabialAngle =>
      _angleAt(LandmarkIndex.lowerLipBottom, LandmarkIndex.lowerLipInner, LandmarkIndex.chin);

  /// 코끝 위치 — Goode-style: nose tip projection / nose length.
  /// Length from nasion (168) to noseTip (1) divided by faceHeight,
  /// gives a stable ratio that captures whether the tip is far forward.
  /// (Not the strict Goode ratio because we lack a true alar-crease landmark
  /// for the denominator on a 3/4 view; this is the closest 2D proxy.)
  double get noseTipProjection =>
      _dist2D(LandmarkIndex.nasion, LandmarkIndex.noseTip) / faceHeight;

  /// 코 등선 돌출도 — CONTINUOUS measure of nasal dorsum convexity
  /// (signed perpendicular distance of rhinion from the nasion→noseTip line,
  /// normalized by faceHeight). Positive = bridge bulges forward (매부리코),
  /// negative = bridge is concave (안장코). The [hasAquilineNose] flag is just
  /// a thresholded view of this same signal; this continuous metric lets rules
  /// distinguish "살짝 매부리" from "강한 매부리" via z-score bands.
  double get dorsalConvexity =>
      _perpDistNormalized(195, LandmarkIndex.nasion, LandmarkIndex.noseTip).abs();

  Map<String, double> computeAll() {
    return {
      'nasofrontalAngle': nasofrontalAngle,
      'nasolabialAngle': nasolabialAngle,
      'facialConvexity': facialConvexity,
      'upperLipEline': upperLipEline,
      'lowerLipEline': lowerLipEline,
      'mentolabialAngle': mentolabialAngle,
      'noseTipProjection': noseTipProjection,
      'dorsalConvexity': dorsalConvexity,
    };
  }

  // ─── Binary flags ───

  /// NOTE: 매부리코 (aquiline) and 들창코 (snub) flags are no longer computed
  /// here — absolute thresholds proved unreliable across faces (bridge noise
  /// and projection geometry vary too much). Instead, both flags are derived
  /// from z-scores inside [analyzeFaceReading], where population reference
  /// data is available. See face_analysis.dart for the z-based logic.
}

/// Estimate head yaw via face-edge asymmetry (distance from nose tip to each
/// face-outline edge landmark). This is more robust than the earlier
/// faceCenter-based proxy because the face center shifts with head rotation,
/// which damps the signal. Asymmetry ratio directly reflects yaw regardless
/// of camera distance or face position in frame.
///
/// Returns yaw in normalized units in [-1, +1]. Sign indicates direction;
/// magnitude grows monotonically with rotation angle up to ~60 deg.
///
/// |yaw| ranges (retuned 2026-04-14 — pushed higher to improve nose-bridge
/// signal-to-noise. At low yaw the rhinion's perpendicular displacement from
/// the nasion→tip line projects weakly: 2mm of actual hump at 30° yaw shows
/// as only ~1mm in image space, indistinguishable from mesh noise. At 50-60°
/// yaw the projection factor rises to 0.77-0.87, giving clean aquiline /
/// straight separation):
///   < 0.70          → frontal (need more rotation, or nose profile unreliable)
///   0.70 .. 0.88    → 3/4 view (valid lateral zone, ~45-60° rotation)
///   0.88 .. 0.95    → near-profile (mesh starts losing far-side landmarks)
///   > 0.95          → true profile / unusable
double estimateYaw(List<FaceMeshLandmark> landmarks) {
  final noseTip = landmarks[LandmarkIndex.noseTip];
  final rightEdge = landmarks[LandmarkIndex.rightFaceEdge];
  final leftEdge = landmarks[LandmarkIndex.leftFaceEdge];
  final rightDist = (noseTip.x - rightEdge.x).abs();
  final leftDist = (leftEdge.x - noseTip.x).abs();
  final total = rightDist + leftDist;
  if (total == 0) return 0;
  return (leftDist - rightDist) / total;
}

/// Yaw classification for capture-flow gating.
enum YawClass { frontal, threeQuarter, profile, unusable }

YawClass classifyYaw(double yaw) {
  final a = yaw.abs();
  if (a < 0.70) return YawClass.frontal;
  if (a < 0.88) return YawClass.threeQuarter;
  if (a < 0.95) return YawClass.profile;
  return YawClass.unusable;
}
