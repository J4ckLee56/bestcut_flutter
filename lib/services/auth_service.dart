import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // 현재 사용자
  User? get currentUser => _auth.currentUser;
  
  // 로그인 상태 스트림
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // 로그인 상태 확인
  bool get isLoggedIn => currentUser != null;

  // 사용자 정보 가져오기
  Future<Map<String, dynamic>?> getUserData() async {
    if (!isLoggedIn) return null;
    
    try {
      final doc = await _firestore
          .collection('users')
          .doc(currentUser!.uid)
          .get();
      
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ AuthService: 사용자 데이터 가져오기 실패: $e');
      return null;
    }
  }

  // 이메일/비밀번호로 로그인
  Future<Map<String, dynamic>> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      if (kDebugMode) print('🔐 AuthService: 이메일/비밀번호 로그인 시도: $email');
      
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        // 로그인 시간 업데이트
        await _updateLastLogin();
        
        if (kDebugMode) print('✅ AuthService: 로그인 성공: ${credential.user!.email}');
        return {
          'success': true,
          'message': '로그인에 성공했습니다.',
          'user': credential.user,
        };
      } else {
        return {
          'success': false,
          'message': '로그인에 실패했습니다.',
        };
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = '등록되지 않은 이메일입니다.';
          break;
        case 'wrong-password':
          message = '비밀번호가 올바르지 않습니다.';
          break;
        case 'invalid-email':
          message = '이메일 형식이 올바르지 않습니다.';
          break;
        case 'user-disabled':
          message = '비활성화된 계정입니다.';
          break;
        case 'too-many-requests':
          message = '너무 많은 시도로 인해 일시적으로 차단되었습니다.';
          break;
        default:
          message = '로그인 중 오류가 발생했습니다: ${e.message}';
      }
      
      if (kDebugMode) print('❌ AuthService: 로그인 실패: $message');
      return {
        'success': false,
        'message': message,
      };
    } catch (e) {
      if (kDebugMode) print('❌ AuthService: 로그인 중 예상치 못한 오류: $e');
      return {
        'success': false,
        'message': '로그인 중 오류가 발생했습니다: $e',
      };
    }
  }

  // 이메일/비밀번호로 회원가입
  Future<Map<String, dynamic>> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      if (kDebugMode) print('📝 AuthService: 회원가입 시도: $email');
      
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null) {
        // Firestore에 사용자 데이터 생성
        await _createUserDocument(credential.user!);
        
        if (kDebugMode) print('✅ AuthService: 회원가입 성공: ${credential.user!.email}');
        return {
          'success': true,
          'message': '회원가입에 성공했습니다.',
          'user': credential.user,
        };
      } else {
        return {
          'success': false,
          'message': '회원가입에 실패했습니다.',
        };
      }
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'weak-password':
          message = '비밀번호가 너무 약합니다.';
          break;
        case 'email-already-in-use':
          message = '이미 사용 중인 이메일입니다.';
          break;
        case 'invalid-email':
          message = '이메일 형식이 올바르지 않습니다.';
          break;
        default:
          message = '회원가입 중 오류가 발생했습니다: ${e.message}';
      }
      
      if (kDebugMode) print('❌ AuthService: 회원가입 실패: $message');
      return {
        'success': false,
        'message': message,
      };
    } catch (e) {
      if (kDebugMode) print('❌ AuthService: 회원가입 중 예상치 못한 오류: $e');
      return {
        'success': false,
        'message': '회원가입 중 오류가 발생했습니다: $e',
      };
    }
  }

  // 로그아웃
  Future<void> signOut() async {
    try {
      if (kDebugMode) print('🚪 AuthService: 로그아웃 시도');
      await _auth.signOut();
      if (kDebugMode) print('✅ AuthService: 로그아웃 성공');
    } catch (e) {
      if (kDebugMode) print('❌ AuthService: 로그아웃 실패: $e');
    }
  }

  // 비밀번호 재설정
  Future<Map<String, dynamic>> resetPassword(String email) async {
    try {
      if (kDebugMode) print('🔄 AuthService: 비밀번호 재설정 시도: $email');
      
      await _auth.sendPasswordResetEmail(email: email);
      
      if (kDebugMode) print('✅ AuthService: 비밀번호 재설정 이메일 전송 성공');
      return {
        'success': true,
        'message': '비밀번호 재설정 이메일을 전송했습니다.',
      };
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = '등록되지 않은 이메일입니다.';
          break;
        case 'invalid-email':
          message = '이메일 형식이 올바르지 않습니다.';
          break;
        default:
          message = '비밀번호 재설정 중 오류가 발생했습니다: ${e.message}';
      }
      
      if (kDebugMode) print('❌ AuthService: 비밀번호 재설정 실패: $message');
      return {
        'success': false,
        'message': message,
      };
    } catch (e) {
      if (kDebugMode) print('❌ AuthService: 비밀번호 재설정 중 예상치 못한 오류: $e');
      return {
        'success': false,
        'message': '비밀번호 재설정 중 오류가 발생했습니다: $e',
      };
    }
  }

  // Firestore에 사용자 문서 생성
  Future<void> _createUserDocument(User user) async {
    try {
      if (kDebugMode) print('📄 AuthService: 사용자 문서 생성 시도: ${user.uid}');
      
      await _firestore.collection('users').doc(user.uid).set({
        'email': user.email,
        'credits': 1000, // 기본 크레딧 1000
        'createdAt': FieldValue.serverTimestamp(),
        'available': true,
        'lastLogin': FieldValue.serverTimestamp(),
      });
      
      if (kDebugMode) print('✅ AuthService: 사용자 문서 생성 성공');
    } catch (e) {
      if (kDebugMode) print('❌ AuthService: 사용자 문서 생성 실패: $e');
      rethrow;
    }
  }

  // 마지막 로그인 시간 업데이트
  Future<void> _updateLastLogin() async {
    if (!isLoggedIn) return;
    
    try {
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'lastLogin': FieldValue.serverTimestamp(),
      });
      
      if (kDebugMode) print('✅ AuthService: 마지막 로그인 시간 업데이트 성공');
    } catch (e) {
      if (kDebugMode) print('❌ AuthService: 마지막 로그인 시간 업데이트 실패: $e');
    }
  }

  // 사용자 크레딧 가져오기
  Future<int> getUserCredits() async {
    if (!isLoggedIn) return 0;
    
    try {
      final userData = await getUserData();
      return userData?['credits'] ?? 0;
    } catch (e) {
      if (kDebugMode) print('❌ AuthService: 크레딧 가져오기 실패: $e');
      return 0;
    }
  }

  // 사용자 크레딧 업데이트
  Future<bool> updateUserCredits(int newCredits) async {
    if (!isLoggedIn) return false;
    
    try {
      await _firestore.collection('users').doc(currentUser!.uid).update({
        'credits': newCredits,
      });
      
      if (kDebugMode) print('✅ AuthService: 크레딧 업데이트 성공: $newCredits');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ AuthService: 크레딧 업데이트 실패: $e');
      return false;
    }
  }

  // Firebase ID 토큰 가져오기
  Future<String?> getIdToken() async {
    if (!isLoggedIn) return null;
    
    try {
      final idToken = await currentUser!.getIdToken();
      if (kDebugMode) print('✅ AuthService: ID 토큰 가져오기 성공');
      return idToken;
    } catch (e) {
      if (kDebugMode) print('❌ AuthService: ID 토큰 가져오기 실패: $e');
      return null;
    }
  }
}

