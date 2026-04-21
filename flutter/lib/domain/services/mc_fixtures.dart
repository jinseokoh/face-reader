/// Shared Monte Carlo face templates for physiognomy sanity/stage-contribution
/// tests. Each template biases the metric pathway the hierarchical engine uses
/// for a specific attribute cluster.
///
///   leader   → forehead/cheekbone/chin strong + Z-07 (all zones hot)
///   scholar  → forehead + eye + eyebrow, Z-02/P-02 (upper zone dominant)
///   merchant → nose + mouth + eye, O-NM1/P-01 (middle zone dominant)
///   charmer  → cheekbone + mouth + eye, O-EM
///   sensual  → lip full + eye tilt + short philtrum, O-PH1/Z-04/P-06
///   anchor   → chin + long philtrum + moderate forehead/nose, O-CH/O-PH2
///
/// See `lib/domain/services/attribute_derivation.dart` for the weight matrix
/// and rule conditions these biases exploit.
library;

class FaceTemplate {
  final String label;
  final Map<String, double> bias;
  const FaceTemplate(this.label, this.bias);
}

const faceTemplates = <FaceTemplate>[
  FaceTemplate('leader', {
    'upperFaceRatio': 1.4,
    'foreheadWidth': 1.3,
    'cheekboneWidth': 1.3,
    'gonialAngle': 1.2,
    'lowerFaceFullness': 1.0,
    'chinAngle': 1.1,
    'nasalHeightRatio': 0.8,
    'noseTipProjection': 0.8,
  }),
  FaceTemplate('scholar', {
    'upperFaceRatio': 1.3,
    'foreheadWidth': 1.2,
    'eyebrowThickness': 1.1,
    'browEyeDistance': 1.0,
    'eyeFissureRatio': 1.3,
    'eyeAspect': 1.1,
    'nasalWidthRatio': -0.3,
    'gonialAngle': -0.3,
    'lowerFaceFullness': -0.3,
    'mouthWidthRatio': -0.2,
  }),
  FaceTemplate('merchant', {
    'nasalWidthRatio': 1.3,
    'nasalHeightRatio': 1.5,
    'nasofrontalAngle': 1.1,
    'noseTipProjection': 1.3,
    'mouthWidthRatio': 1.2,
    'mouthCornerAngle': 1.0,
    'cheekboneWidth': 1.1,
    'eyeFissureRatio': 1.1,
    'upperFaceRatio': -0.3,
    'foreheadWidth': -0.3,
    'philtrumLength': -0.3,
    'lowerFaceFullness': -0.2,
  }),
  FaceTemplate('charmer', {
    'cheekboneWidth': 1.5,
    'mouthWidthRatio': 1.5,
    'mouthCornerAngle': 1.4,
    'lipFullnessRatio': 1.0,
    'lowerFaceFullness': 0.9,
    'chinAngle': 0.8,
    'eyeFissureRatio': 1.1,
    'eyeAspect': 0.9,
    'nasalHeightRatio': 0.2,
  }),
  FaceTemplate('sensual', {
    'eyeCanthalTilt': 1.5,
    'eyeAspect': 1.1,
    'lipFullnessRatio': 1.6,
    'upperVsLowerLipRatio': 1.0,
    'mouthCornerAngle': 0.9,
    'philtrumLength': -1.2,
    'lowerFaceFullness': 0.9,
    'chinAngle': 0.7,
    'upperFaceRatio': -0.3,
    'foreheadWidth': -0.3,
    'nasalWidthRatio': -0.2,
    'eyebrowThickness': -0.2,
  }),
  FaceTemplate('anchor', {
    'gonialAngle': 1.2,
    'lowerFaceRatio': 0.8,
    'lowerFaceFullness': 1.1,
    'chinAngle': 1.3,
    'philtrumLength': 1.3,
    'upperFaceRatio': 0.8,
    'foreheadWidth': 0.7,
    'eyebrowThickness': 1.0,
    'browEyeDistance': 0.8,
    'nasalHeightRatio': 0.6,
    'nasalWidthRatio': 0.4,
    'eyeFissureRatio': 0.4,
    'mouthWidthRatio': 0.0,
    'lipFullnessRatio': -0.3,
    'mouthCornerAngle': -0.3,
  }),
];
