# ── TensorFlow Lite (tflite_flutter — face shape classifier) ──
# GPU delegate 의 optional 클래스(GpuDelegateFactory$Options 등)는 참조되지만
# GPU delegate 의존성이 번들되지 않아 R8 가 "Missing class" 로 release 빌드를
# 실패시킨다. 누락 참조 경고를 무시하고, 실제 존재하는 TFLite 클래스는 보존.
-dontwarn org.tensorflow.lite.gpu.**
-keep class org.tensorflow.lite.gpu.** { *; }
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**
