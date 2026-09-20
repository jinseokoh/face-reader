# vendored: MiVOLO (model 코드 일부)

- 출처: https://github.com/WildChlamydia/MiVOLO — commit 37475e3f8818b5f22448003feec3e64b01bfb188
- 라이선스: Apache License 2.0 (동봉 LICENSE). setup.py 주석의 "Attribution-ShareAlike 4.0" 표기와
  다르지만 리포의 LICENSE 파일이 Apache 2.0 이다. 가중치(HF iitolstykh/mivolo_v2)도 Apache 2.0.
- 가져온 파일: mivolo/model/{create_timm_model,mivolo_model,cross_bottleneck_attn}.py,
  mivolo/data/misc.py (HF 원격 코드 modeling_mivolo.py 가 `mivolo.model.create_timm_model.create_model` 을,
  mivolo_image_processor.py 가 `mivolo.data.misc.prepare_classification_images` 를 import 한다).
  misc.py 의 scipy 의존은 추적용 함수 것이라 우리는 안 쓰지만 import 가 필요해 scipy 를 깐다.
- 왜 pip 이 아닌가: `pip install git+…MiVOLO` 는 setup.py 의 pkg_resources 사용으로 빌드가
  깨지고, install_requires 에 ultralytics·yt_dlp 등 추론에 불필요한 무거운 의존이 붙는다.
- 수정 없음. timm==0.8.13.dev0 에 묶여 있다 (`timm.models._helpers.remap_checkpoint`).
