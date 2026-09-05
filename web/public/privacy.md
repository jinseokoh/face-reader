# 개인정보처리방침

관상은 과학이다(이하 "서비스")는 사용자의 개인정보를 소중히 다루며, 「개인정보 보호법」 등 관련 법령을 준수합니다.

## 1. 수집하는 개인정보 항목

| 구분 | 항목                                                                              |
| ---- | --------------------------------------------------------------------------------- |
| 필수 | 얼굴 사진, 안면 계측값 (얼굴 랜드마크 기반 수치), 사진 기반 추정 성별·연령대·인종 |
| 선택 | 닉네임, 이메일 (계정 연동 시), 결제 정보 (인앱 결제 시), 채팅 메시지 (매칭 채팅 이용 시) |
| 자동 | 기기 식별자, 광고 식별자, OS 버전, 앱 사용 로그, IP 주소                          |

## 2. 얼굴 데이터의 처리

이 조항은 얼굴 사진과 그로부터 얻는 정보(이하 "얼굴 데이터")에 관하여 다른 조항보다 우선하여 적용됩니다.

### 2.1 수집하는 얼굴 데이터

- **얼굴 사진**: 카메라로 촬영하거나 앨범에서 선택한 정면 사진
- **안면 계측값**: 이용자 기기 안에서 얼굴 랜드마크(468점)를 검출한 뒤 계산한 비율·각도 등의 수치. 랜드마크 좌표 자체는 저장하지 않습니다.
- **사진 기반 추정 범주**: 사진에서 추정한 성별·연령대·인종의 범주값
- **얼굴 썸네일**: 결과 구분과 기록 확인을 위한 200×200 저해상도 얼굴 이미지 1장

### 2.2 이용 목적

- 관상 분석 결과의 생성, 두 사람의 궁합 계산, 케미 그룹의 참여자 간 궁합 계산
- 분석 기록·공유 카드·케미 방에서 어느 얼굴의 결과인지 구분

서비스는 얼굴 인식(신원 확인)을 하지 않습니다. 얼굴을 다른 사진이나 데이터베이스와 대조하지 않으며, 기기의 Face ID 등 생체인증 정보에 접근하지 않습니다. 얼굴 데이터를 광고, 이용자 프로파일링, 학습용 데이터셋 구축, 판매에 사용하지 않습니다.

### 2.3 처리 위치와 저장

- 랜드마크 검출과 계측값 계산은 이용자 기기 안에서 이루어집니다.
- 성별·연령대·인종 추정을 위해 축소본(긴 변 720px)이 서비스 운영자가 운영하는 분석 서버로 전송되며, 추정이 끝나면 즉시 삭제됩니다. 전송 과정에서 Cloudflare R2 임시 저장소를 거치며, 미처리 파일도 1일 내 자동 삭제됩니다.
- 원본 사진은 서버에 저장하지 않습니다.
- 분석 기록을 저장하면 안면 계측값·추정 범주는 Supabase 데이터베이스에, 얼굴 썸네일은 Cloudflare R2에 저장됩니다. 썸네일은 추측할 수 없는 주소로만 접근되며 검색엔진 색인을 차단합니다. Supabase·Cloudflare는 해외 사업자로 서버가 국외에 위치할 수 있습니다.
- 이용자 기기 안에는 안면 계측값과 썸네일이 저장되며, 이용자가 기록을 삭제하거나 앱을 삭제하면 사라집니다.

### 2.4 제3자 제공 및 다른 이용자에게의 공개

- 얼굴 데이터를 제3자에게 제공하거나 판매하지 않습니다. 제6조의 수탁자는 저장·전송을 위탁받을 뿐 얼굴 데이터를 자체 목적으로 이용하지 않습니다.
- 다음의 경우에는 이용자 본인의 행위에 따라 다른 이용자에게 썸네일과 분석 결과가 공개됩니다. 이용자가 결과를 공유 링크로 보낸 경우에는 링크를 받은 사람에게, 케미 그룹에 참여한 경우에는 같은 그룹의 참여자에게, 다른 이용자가 이용자의 사진으로 궁합을 해제한 경우에는 그 이용자에게 공개됩니다.
- 케미 그룹 참여 시 사진 공개 여부는 참여 전에 확인을 받습니다.

### 2.5 보유 기간과 삭제

- **얼굴 사진 원본·분석용 축소본**: 추정 완료 즉시 삭제, 미처리 파일은 1일 내 자동 삭제
- **안면 계측값·추정 범주·얼굴 썸네일**: 회원 탈퇴 시 삭제. 비로그인 기록은 90일 미활동 시 자동 삭제
- **케미 그룹의 얼굴 데이터**: 그룹 종료 후 30일이 지나면 자동 삭제
- **다른 이용자가 코인으로 해제한 궁합 결과에 포함된 썸네일 사본**: 그 구매자의 콘텐츠로 남으며, 그 구매자가 탈퇴할 때 삭제
- 이용자는 앱의 설정 화면에서 회원 탈퇴로 얼굴 데이터를 포함한 모든 데이터를 즉시 삭제할 수 있으며, [/contact](/contact) 페이지에서도 삭제를 요청할 수 있습니다.

### 2.6 Face Data (English summary of this section)

- **Collected**: a front-facing photo (camera or album); facial measurements (ratios and angles computed on the device from 468 face landmarks; landmark coordinates themselves are not stored); estimated gender, age group and ethnicity categories; one 200×200 low-resolution face thumbnail.
- **Use**: generating the user's own face-reading result, computing compatibility between two people, and computing pairwise compatibility within a chemistry group; telling results apart in history, share cards and group rooms. The app does not perform facial recognition or identification, does not match faces against any database, does not access Face ID or other biometric authentication data, and does not use face data for advertising, profiling, training datasets, or sale.
- **Processing and storage**: landmark detection and measurement run on the device. A downscaled copy (720px long side) is sent to a server operated by the service provider to estimate gender, age group and ethnicity, and is deleted immediately after estimation (unprocessed files are auto-deleted within 1 day). Original photos are not stored on any server. When a record is saved, measurements and estimated categories are stored in a Supabase database and the thumbnail in Cloudflare R2, behind an unguessable URL with search-engine indexing blocked. Supabase and Cloudflare are non-Korean providers and may store data outside Korea.
- **Sharing**: face data is not sold or provided to third parties. Processors listed in Section 6 store or transmit data on our behalf only. Thumbnails and results become visible to other users only through the user's own actions: recipients of a share link, members of a chemistry group the user joined, and a user who unlocked a compatibility result with the user's photo. Joining a group asks for confirmation of photo visibility beforehand.
- **Retention and deletion**: originals and analysis copies are deleted immediately after estimation; measurements, categories and thumbnails are deleted on account deletion, and records made without an account are auto-deleted after 90 days of inactivity; chemistry group data is auto-deleted 30 days after the group ends; a thumbnail copy inside a compatibility result another user paid to unlock remains as that buyer's content until the buyer deletes their account. Users can delete their account and all data in the app's Settings screen, or request deletion at [/contact](/contact).

## 3. 수집 및 이용 목적

- 관상 분석 수행 및 결과 제공
- 분석 이력 저장 및 사용자 식별
- 인앱 결제 처리 및 구매 복원
- 서비스 개선을 위한 통계 분석 (비식별 처리 후 활용)
- 부정 이용 방지

## 4. 보유 및 이용 기간

- **얼굴 사진 원본**: 분석에 사용된 원본 사진은 보관하지 않습니다. 분석을 위해 축소본이 일시적으로 서버에 전송되며, 분석 완료 즉시 삭제됩니다 (미처리 파일도 1일 내 자동 삭제).
- **얼굴 썸네일 (200×200)**: 결과 구분 및 기록 확인을 위해 저해상도 얼굴 썸네일 1장만 서버에 보관되며, 탈퇴 시 삭제됩니다. 비로그인 상태의 분석 기록과 썸네일은 90일 미활동 시 자동 삭제됩니다. 다만 다른 이용자가 코인으로 해제한 궁합 결과에 포함된 썸네일 사본은 그 구매자의 콘텐츠로서 남으며(아래 「결제한 궁합 결과」), 그 구매자가 탈퇴할 때 함께 삭제됩니다.
- **분석 결과 데이터**: 사용자가 직접 삭제하거나 회원 탈퇴 시까지. 비로그인 기록은 90일 미활동 시 자동 삭제
- **케미 그룹 데이터**: 참가 정보·결과표·매칭 채팅 메시지는 그룹 종료 후 30일이 지나면 자동 삭제됩니다.
- **결제한 궁합 결과**: 코인으로 해제한 궁합 분석은 구매 콘텐츠로서 이용자 계정에 보관되며, 상대방의 데이터 삭제 여부와 무관하게 이용할 수 있습니다.
- **결제 기록**: 「전자상거래법」에 따라 5년
- **앱 사용 로그**: 「통신비밀보호법」에 따라 3개월

## 5. 제3자 제공

서비스는 다음 경우 외에는 사용자의 개인정보를 제3자에게 제공하지 않습니다:

- 사용자의 사전 동의가 있는 경우
- 법령 또는 수사기관의 적법한 요청이 있는 경우

## 6. 처리 위탁

| 수탁자          | 위탁 업무                   | 보유 기간            |
| --------------- | --------------------------- | -------------------- |
| Supabase Inc.   | 데이터베이스 및 인증 호스팅 | 회원 탈퇴 전까지     |
| Cloudflare Inc. | CDN 및 이미지 저장 (R2)     | 썸네일만 탈퇴 전까지 (구매된 궁합의 사본은 구매자 탈퇴 전까지) |
| Google Firebase | 분석 로그 및 푸시 알림      | 6개월                |
| Google AdMob    | 광고 게재 (광고 식별자)     | Google 정책에 따름   |
| Kakao Corp.     | 카카오 로그인 및 공유       | 회원 탈퇴 전까지     |
| RevenueCat      | 인앱 결제 검증              | 결제 기록 보유 기간  |

## 7. 사용자 권리

사용자는 언제든지 다음 권리를 행사할 수 있습니다:

- 개인정보 열람 / 정정 / 삭제 요청
- 처리 정지 요청
- 회원 탈퇴 및 데이터 영구 삭제

개인정보 삭제 요청은 [/contact](/contact) 페이지에서 접수 가능합니다.

## 8. 안전성 확보 조치

- 통신 구간 TLS 1.3 암호화
- 원본 사진은 분석 완료 즉시 폐기, 작은 식별용 200×200 저해상도 썸네일만 보관
- 최소 권한 원칙 기반의 직원 접근 제어
- 정기적 보안 점검 및 취약점 패치

## 9. 만 18세 미만 청소년

서비스는 만 18세 미만의 가입을 허용하지 않습니다. 만 18세 미만 청소년의 개인정보가 수집된 사실을 인지한 경우 즉시 삭제 조치합니다.

## 10. 개인정보 보호책임자

- 사업자: 에스아이(S.I.)
- 책임자: Chuck JS. Oh (a.k.a., 공대삼촌)
- 이메일: uncle@facely.kr

## 11. 변경 이력

- 2026-05-25 — 최초 제정
- 2026-07-29 — 보유 기간 구체화 (비로그인 90일 자동 삭제, 케미 그룹 30일 자동 삭제), 수집 항목(안면 계측값·광고 식별자·채팅 메시지) 및 수탁자(Google AdMob·Kakao) 현행화, 가입 연령 만 18세 이상으로 상향
- 2026-09-05 — 얼굴 데이터의 처리 조항(제2조) 신설: 수집 항목·처리 위치·다른 이용자에게의 공개·보유 기간·삭제 방법을 한 곳에 명시, 영문 요약 추가
