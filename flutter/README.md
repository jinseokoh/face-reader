# 관상은 과학이다

안면 계측 데이터 기반 인공지능 관상앱.

MediaPipe Face Mesh 468 landmarks → 26 frontal + 8 lateral metric → 14-node tree
→ 10 attribute → archetype → 8 인생 질문 본문. 궁합 엔진은 별도.
제품 3층: 1인 관상 · 2인 궁합 · 다인 케미.

오리엔테이션·작업 규칙·SSOT 문서 안내: [`CLAUDE.md`](CLAUDE.md).

```bash
flutter pub get
flutter analyze     # 기준선 7건 (경미)
flutter test        # 전부 green
flutter run         # 실기기 (camera/MediaPipe 는 simulator 불가)
```
