# Flutter Project Setup Guide

**마지막 업데이트**: 2026-04-18

본 문서는 Face Reader 앱의 Flutter 프로젝트 구조 패턴을 설명한다. 현재 프로젝트의 실제 구조는 `flutter/CLAUDE.md`를 참조.

## 1. 폴더 구조

```
lib/
├── main.dart                              # Entry point (Firebase + Hive init)
├── app.dart                               # MainApp: IndexedStack + BottomNavigationBar
├── config/
│   ├── router.dart                        # GoRouter 설정
│   └── api_config.dart                    # API base URL + endpoint 상수
├── core/
│   ├── http/http_client.dart              # Dio Provider + AuthInterceptor 연결
│   ├── interceptors/auth_interceptor.dart # JWT 주입, 401 자동 refresh, 요청 큐잉
│   ├── firebase/firebase_messaging_handler.dart
│   ├── hive/hive_setup.dart               # Hive 초기화 + Box 정의
│   └── theme.dart                         # AppTheme 색상
├── data/
│   ├── datasources/
│   │   ├── remote/                        # API 클라이언트 (Dio)
│   │   └── local/                         # Hive 로컬 저장소
│   ├── repositories/                      # DataSource 조합 + 비즈니스 로직
│   ├── models/                            # Freezed + json_serializable 모델
│   ├── enums/                             # Gender, Role 등 enum 상수
│   ├── services/                          # S3Upload, Firebase Chat 등
│   └── constants/
├── domain/
│   ├── models/                            # 순수 비즈니스 엔티티
│   └── services/                          # 비즈니스 로직 인터페이스
└── presentation/
    ├── providers/
    │   ├── di_providers.dart              # 모든 DI 정의 (중앙 집중)
    │   ├── auth_provider.dart             # Auth 상태 (NotifierProvider)
    │   ├── tab_provider.dart              # Tab 상태
    │   └── *_provider.dart                # 기능별 Provider
    ├── screens/
    │   ├── home/
    │   │   ├── home_screen.dart
    │   │   └── uis/                       # 재사용 위젯
    │   ├── login/
    │   ├── settings/
    │   └── ...
    ├── models/                            # Presentation 전용 모델
    └── widgets/                           # 공유 UI 컴포넌트
```

## 2. Dependencies (pubspec.yaml)

```yaml
# State Management
flutter_riverpod: ^3.0.3
riverpod: ^3.2.0

# HTTP
dio: ^5.4.0

# Routing
go_router: ^17.1.0

# Code Generation (Freezed)
freezed: ^3.2.5              # dev
freezed_annotation: ^3.0.0
json_serializable: ^6.7.1    # dev
json_annotation: ^4.8.1
build_runner: ^2.4.7          # dev

# Local Storage
hive_ce: ^2.19.3
hive_ce_flutter: ^2.3.4

# Firebase
firebase_core: ^4.4.0
firebase_auth: ^6.1.4
firebase_messaging: ^16.1.1
cloud_firestore: ^6.1.2

# UI
cached_network_image, flutter_svg, shimmer, photo_view, image_picker 등
```

## 3. 핵심 Boilerplate Patterns

---

### 3-1. Router (GoRouter)

`config/router.dart` — 선언적 라우팅, auth guard 없이 SplashScreen에서 인증 상태 체크 후 분기.

```dart
final router = GoRouter(
  initialLocation: '/splash',
  routes: [
    GoRoute(path: '/splash', builder: (ctx, state) => SplashScreen()),
    GoRoute(path: '/login',  builder: (ctx, state) => LoginScreen()),
    GoRoute(path: '/main',   builder: (ctx, state) => MainApp()),
    GoRoute(
      path: '/feedback',
      builder: (ctx, state) => ChatScreen(group: state.extra as Group),
    ),
    // extra 파라미터로 객체 전달
  ],
);
```

---

### 3-2. HTTP Client (Dio + AuthInterceptor)

`core/http/http_client.dart` — Riverpod Provider로 Dio 싱글턴 제공.

```dart
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://api.hero-ai.kr',
    connectTimeout: Duration(seconds: 30),
    receiveTimeout: Duration(seconds: 30),
    headers: {'Content-Type': 'application/json'},
  ));
  dio.interceptors.add(AuthInterceptor(
    localDataSource: ref.watch(authLocalDataSourceProvider),
    remoteDataSource: AuthRemoteDataSourceImpl(refreshDio),
  ));
  return dio;
});
```

`core/interceptors/auth_interceptor.dart` — 핵심 동작:
1. **onRequest**: `Authorization: Bearer {accessToken}` 헤더 주입
2. **onError (401)**: refreshToken으로 토큰 갱신 시도
3. **큐잉**: refresh 진행 중 들어온 요청은 대기열에 추가, 완료 후 일괄 재시도
4. **실패 시**: 토큰 클리어 + 대기열 전체 reject

---

### 3-3. Provider (Riverpod)

#### 단순 상태 (NotifierProvider)
```dart
// presentation/providers/tab_provider.dart
final selectedTabProvider = NotifierProvider<SelectedTabNotifier, int>(
  SelectedTabNotifier.new,
);

class SelectedTabNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void selectTab(int index) => state = index;
}
```

#### 복합 상태 (AuthNotifier)
```dart
// presentation/providers/auth_provider.dart
final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // 초기화 시 저장된 토큰 확인
    if (ref.read(authRepositoryProvider).getAccessToken() != null) {
      _loadMe();
    }
    return const AuthState();
  }

  Future<void> login(...) async {
    state = state.copyWith(isLoading: true);
    try {
      await ref.read(authRepositoryProvider).login(...);
      await _loadMe();
    } catch (e) {
      state = state.copyWith(error: e.toString(), isLoading: false);
    }
  }
}
```

#### 파생 Provider (Computed)
```dart
final selectedStudentProvider = Provider<AuthStudent?>((ref) {
  final students = ref.watch(studentsProvider);
  final index = ref.watch(selectedStudentIndexProvider);
  return students.isEmpty ? null : students[index];
});
```

#### 비동기 + 파라미터 (FutureProvider.family)
```dart
final updateStudentProvider = FutureProvider.family.autoDispose<void, UpdateStudentParams>(
  (ref, params) async {
    await ref.read(studentRepositoryProvider).updateStudent(...);
    await ref.read(authProvider.notifier).refreshMe();
  },
);
```

**규칙**: 싱글턴(Repository 등)은 `ref.read()`, 상태 변화 감지는 `ref.watch()`.

---

### 3-4. Repository

`data/repositories/` — Remote/Local DataSource를 조합하고 Firebase 등 부가 로직 처리.

```dart
class AuthRepository {
  final AuthRemoteDataSource remoteDataSource;
  final AuthLocalDataSource localDataSource;

  Future<AuthResponse> login(LoginRequest request) async {
    final response = await remoteDataSource.login(request);
    await localDataSource.saveTokens(response.accessToken, response.refreshToken);
    await _registerFcmToken();
    await _signInToFirebase();
    return response;
  }

  Future<GetMe> getMe() async {
    return await remoteDataSource.getMe();
  }
}
```

---

### 3-5. DataSource

#### Remote (Dio HTTP)
```dart
// data/datasources/remote/auth_remote_datasource.dart
abstract class AuthRemoteDataSource {
  Future<GetMe> getMe();
  Future<AuthResponse> login(LoginRequest request);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final Dio dio;
  AuthRemoteDataSourceImpl(this.dio);

  @override
  Future<GetMe> getMe() async {
    final response = await dio.get('/v1/auth/me');
    return GetMe.fromJson(response.data);
  }

  @override
  Future<AuthResponse> login(LoginRequest request) async {
    final response = await dio.post('/v1/auth/parent/login', data: request.toJson());
    return AuthResponse.fromJson(response.data);
  }
}
```

#### Local (Hive)
```dart
// data/datasources/local/auth_local_datasource.dart
class AuthLocalDataSourceImpl implements AuthLocalDataSource {
  Box<String> get _tokensBox => Hive.box<String>(HiveBoxes.authTokens);

  String? getAccessToken() => _tokensBox.get(AuthStorageKeys.accessToken);

  Future<void> saveTokens(String accessToken, String? refreshToken) async {
    await _tokensBox.put(AuthStorageKeys.accessToken, accessToken);
    if (refreshToken != null) {
      await _tokensBox.put(AuthStorageKeys.refreshToken, refreshToken);
    }
  }

  Future<void> clearTokens() async => await _tokensBox.clear();
}
```

---

### 3-6. Service

UseCase 패턴 대신 Service로 횡단 관심사 처리. Riverpod Provider로 주입.

```dart
// S3 업로드
final s3UploadServiceProvider = Provider<S3UploadService>((ref) {
  return S3UploadService(ref.read(dioProvider));
});

// Firebase 채팅
final firebaseChatServiceProvider = Provider<FeedbackChatService>((ref) {
  return FeedbackChatService(FirebaseFirestore.instance);
});
```

---

### 3-7. DI (di_providers.dart — 중앙 집중)

모든 DataSource, Repository, Service Provider를 한 파일에서 정의.

```dart
// presentation/providers/di_providers.dart

// DataSources
final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>((ref) =>
  AuthRemoteDataSourceImpl(ref.read(dioProvider)),
);
final authLocalDataSourceProvider = Provider<AuthLocalDataSource>((ref) =>
  AuthLocalDataSourceImpl(),
);

// Repositories
final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(
  remoteDataSource: ref.read(authRemoteDataSourceProvider),
  localDataSource: ref.read(authLocalDataSourceProvider),
));

// Services
final s3UploadServiceProvider = Provider<S3UploadService>((ref) =>
  S3UploadService(ref.read(dioProvider)),
);
```

**의존성 흐름**: `Screen → Provider → Repository → DataSource → Dio/Hive`

---

### 3-8. Bottom Tab Navigation

`app.dart` — IndexedStack으로 탭 전환 시 상태 유지.

```dart
class MainApp extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(selectedTabProvider);
    return Scaffold(
      body: IndexedStack(
        index: selectedIndex,
        children: [HomeScreen(), ProgramScreen(), ReportScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (i) => ref.read(selectedTabProvider.notifier).selectTab(i),
        items: [/* 홈, 프로그램, 리포트, 설정 */],
      ),
    );
  }
}
```

---

### 3-9. Data Model (Freezed)

```dart
import 'package:freezed_annotation/freezed_annotation.dart';
part 'auth_student.freezed.dart';
part 'auth_student.g.dart';

@freezed
abstract class AuthStudent with _$AuthStudent {
  const factory AuthStudent({
    required int id,
    required String name,
    Gender? gender,
    String? height,
  }) = _AuthStudent;

  factory AuthStudent.fromJson(Map<String, dynamic> json) =>
      _$AuthStudentFromJson(json);
}
```

모델 수정 후 반드시 실행:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

---

### 3-10. Screen 작성 패턴

```dart
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);        // 상태 변화 감지
    final repo = ref.read(authRepositoryProvider);    // 1회성 읽기

    return Scaffold(
      body: authState.isLoading
        ? CircularProgressIndicator()
        : ListView(...),
    );
  }
}
```

---

## 새 기능 추가 체크리스트

1. `data/models/` — Freezed 모델 생성 → `build_runner` 실행
2. `data/datasources/remote/` — abstract 인터페이스 + Impl (Dio)
3. `data/datasources/local/` — (필요 시) Hive LocalDataSource
4. `data/repositories/` — DataSource 조합 Repository
5. `presentation/providers/di_providers.dart` — Provider 등록
6. `presentation/providers/` — NotifierProvider 또는 FutureProvider
7. `presentation/screens/feature/` — Screen + `uis/` 위젯
8. `config/router.dart` — GoRoute 추가

---

## 연관 문서

- [ARCHITECTURE.md](ARCHITECTURE.md) — 관상 엔진 아키텍처 (Track 1/2/3)
- [BUSINESS.md](BUSINESS.md) — 비즈니스 로직 (metric, attribute, archetype)
- [SUPABASE_PLAN.md](SUPABASE_PLAN.md) — Supabase 연동 계획
