# Face Mesh Analyzer App

## Overview
Flutter app that streams camera frames through MediaPipe Face Mesh (468 landmarks) and provides facial proportion analysis compared against population averages.

## Tech Stack
- **Flutter** (Dart SDK ^3.11.0)
- **camera** ^0.11.1 — camera preview and frame streaming
- **mediapipe_face_mesh** ^1.2.4 — face mesh inference (FFI + TFLite)
- **path_provider** ^2.1.0 — file saving

## Architecture

### File Structure
```
lib/
├── main.dart                 # App entry point
├── face_mesh_page.dart       # Camera view + mesh overlay + controls
├── face_mesh_painter.dart    # CustomPainter for 468 landmarks + triangles
├── face_metrics.dart         # Landmark index constants + 12 ratio computations
├── face_reference_data.dart  # Population averages by ethnicity (6 groups)
├── face_analysis.dart        # Z-score analysis + multi-frame averaging
└── report_page.dart          # Analysis report UI with save/copy
```

### Frame Processing Pipeline
```
CameraController.startImageStream()
  → Platform branch:
    Android: NV21 (yPlane + vuPlane split) → processNv21()
    iOS: BGRA → process()
  → FaceMeshResult (468 landmarks, triangles, score)
  → Tracking quality check → overlay color (Red/Green)
  → CustomPainter renders overlay
```

### Key Design Decisions
- **NV21 on Android**: Camera delivers single buffer in `planes[0]`; must split into Y (width*height bytes) and VU (remainder) for `FaceMeshNv21Image`
- **Portrait aspect ratio**: `controller.value.previewSize` is in sensor orientation (landscape); swap width/height for portrait display
- **FittedBox.cover**: Camera preview + mesh overlay share same `SizedBox` inside `FittedBox(fit: BoxFit.cover)` to keep coordinates aligned
- **Frame throttling**: `_isProcessing` flag skips frames while previous is still processing
- **ROI tracking**: `enableRoiTracking: true` — no separate face detector needed
- **Ratios over absolute values**: Normalized landmarks (0~1) make facial ratios scale-invariant

### Overlay Color System
- **Red** (default): Normal tracking
- **Green**: Accurate tracking — all 3 criteria met:
  1. Confidence score >= 0.85
  2. Frame-to-frame stability (avg landmark movement < 0.005)
  3. Face width > 25% of frame

### Facial Analysis
- 12 metrics computed from landmark ratios (face proportions, eyes, nose, mouth)
- Compared against population averages (Farkas anthropometric studies, PMC9029890)
- 6 ethnicity groups supported (default: East Asian)
- Z-score interpretation: ±0.5 = average, ±1.0 = slight, ±2.0 = notable, ±3.0 = significant
- 5-frame averaging reduces measurement noise

### Landmark Indices (most used)
| Point | Index |
|-------|-------|
| Forehead top | 10 |
| Nasion | 168 |
| Nose tip | 1 |
| Subnasale | 94 |
| Nostrils (R/L) | 98 / 327 |
| Inner eye corners | 133 / 362 |
| Outer eye corners | 33 / 263 |
| Mouth corners | 61 / 291 |
| Lip top/bottom | 0 / 17 |
| Chin | 152 |
| Face edges | 234 / 454 |

## Platform Setup
- **Android**: `CAMERA` permission in AndroidManifest.xml
- **iOS**: `NSCameraUsageDescription` in Info.plist
- Physical device required (camera doesn't work in simulator/emulator)

## Build & Run
```bash
cd /Users/chuck/Code/face/flutter
flutter pub get
flutter run
```
