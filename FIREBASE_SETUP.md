# 🔥 Firebase 연동 설정 가이드

기존 베스트컷 파이썬 버전의 Firestore 서버와 Flutter 앱을 연동하기 위한 설정 가이드입니다.

## 📋 필수 요구사항

- Flutter SDK 3.8.1 이상
- Firebase 프로젝트 (기존 베스트컷 서버와 동일한 프로젝트)
- Android Studio / Xcode (플랫폼별 빌드용)

## 🚀 설치 단계

### 1. 의존성 설치
```bash
flutter pub get
```

### 2. Firebase 프로젝트 설정

#### A. Firebase Console에서 설정
1. [Firebase Console](https://console.firebase.google.com/)에 접속
2. 기존 베스트컷 프로젝트 선택 (또는 새로 생성)
3. 프로젝트 설정 → 일반 → 내 앱에서 앱 추가

#### B. Android 설정
1. `android/app/google-services.json` 파일을 실제 Firebase 프로젝트에서 다운로드한 파일로 교체
2. `android/app/build.gradle.kts`에 Google Services 플러그인이 추가되어 있는지 확인
3. `android/build.gradle.kts`에 Google Services 클래스패스가 추가되어 있는지 확인

#### C. iOS 설정 (필요시)
1. `ios/Runner/GoogleService-Info.plist` 파일을 실제 Firebase 프로젝트에서 다운로드한 파일로 교체

### 3. Firebase 초기화 확인
`lib/main.dart`에서 Firebase가 올바르게 초기화되었는지 확인:
```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // 이 줄이 있어야 함
  // ... 나머지 코드
}
```

## 📱 사용 방법

### 기본 사용법
```dart
import 'package:bestcut_flutter/services/firebase_service.dart';

final firebaseService = FirebaseService();

// 사용자 로그인
await firebaseService.signInWithEmailAndPassword(email, password);

// 사용자 데이터 가져오기
final userData = await firebaseService.getUserData(userId);

// 작업 내역 추가
await firebaseService.addAction(actionData);
```

### 데이터 모델 사용
```dart
import 'package:bestcut_flutter/models/user_model.dart';
import 'package:bestcut_flutter/models/action_model.dart';

// Firestore 데이터를 모델로 변환
final user = UserModel.fromFirestore(data, documentId);
final action = ActionModel.fromFirestore(data, documentId);
```

## 🗄️ 데이터베이스 구조

### 컬렉션
- **users**: 사용자 계정 정보 (크레딧, 이메일 등)
- **actions**: 작업 내역 (전사, 요약, 내보내기)
- **surveys**: 사용자 설문조사
- **updates**: 앱 업데이트 정보

### 주요 필드
- `userId`: 사용자 식별자
- `type`: 작업 유형 (transcribe, summarize, export)
- `credits`: 사용자 크레딧
- `timestamp`: 작업 수행 시간
- `success`: 작업 성공 여부

## 🔧 문제 해결

### 일반적인 오류
1. **Firebase 초기화 실패**: `google-services.json` 파일 경로 확인
2. **권한 오류**: Firestore 보안 규칙 확인
3. **빌드 실패**: 의존성 버전 호환성 확인

### 디버깅
```dart
// Firebase 연결 상태 확인
print('Firebase 초기화 상태: ${Firebase.apps.isNotEmpty}');

// Firestore 연결 테스트
try {
  await FirebaseFirestore.instance.collection('test').get();
  print('Firestore 연결 성공');
} catch (e) {
  print('Firestore 연결 실패: $e');
}
```

## 📚 추가 리소스

- [Flutter Firebase 공식 문서](https://firebase.flutter.dev/)
- [Firestore 보안 규칙 가이드](https://firebase.google.com/docs/firestore/security/get-started)
- [Firebase 인증 가이드](https://firebase.google.com/docs/auth)

## 🤝 지원

문제가 발생하거나 추가 도움이 필요한 경우:
1. Firebase Console에서 프로젝트 설정 확인
2. Flutter 의존성 버전 호환성 확인
3. 플랫폼별 빌드 설정 확인 