import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'firebase_functions_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CreditService {
  static final CreditService _instance = CreditService._internal();
  factory CreditService() => _instance;
  CreditService._internal();

  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseFunctionsService _functionsService = FirebaseFunctionsService();


  // 사용자 크레딧 잔액 확인 (Firebase Functions 우선, Firestore fallback)
  Future<int> getUserCredits() async {
    if (!_authService.isLoggedIn) {
      if (kDebugMode) print('❌ CreditService: 로그인되지 않은 사용자');
      return 0;
    }

    try {
      // 1. Firebase Functions를 통한 크레딧 조회 시도
      if (kDebugMode) print('💰 CreditService: Firebase Functions로 크레딧 조회 시도');
      
      final idToken = await _authService.getIdToken();
      if (idToken == null) {
        if (kDebugMode) print('⚠️ CreditService: ID 토큰 없음, Firestore로 fallback');
        final credits = await _firestoreService.getUserCredits();
        if (kDebugMode) print('💰 CreditService: Firestore 크레딧 조회: $credits');
        return credits;
      }
      
      final functionsResult = await _functionsService.getCredits(idToken: idToken);
      
      if (functionsResult['success']) {
        final data = functionsResult['data'] as Map<String, dynamic>;
        final credits = data['credits'] as int? ?? 0;
        if (kDebugMode) print('✅ CreditService: Firebase Functions 크레딧 조회 성공: $credits');
        return credits;
      }
      
      // 2. Firebase Functions 실패 시 Firestore로 fallback
      if (kDebugMode) print('⚠️ CreditService: Firebase Functions 실패, Firestore로 fallback');
      
      final credits = await _firestoreService.getUserCredits();
      if (kDebugMode) print('💰 CreditService: Firestore 크레딧 조회: $credits');
      return credits;
    } catch (e) {
      if (kDebugMode) print('❌ CreditService: 크레딧 조회 실패: $e');
      return 0;
    }
  }

  // 주의: 크레딧 차감과 충전은 Firebase Functions에서 처리됩니다.
  // 클라이언트에서 직접 호출하면 안됩니다.



  // checkCredits Firebase Function 호출 (Firebase Functions 서비스 사용)
  Future<Map<String, dynamic>> checkCredits(double videoDurationInSeconds) async {
    if (!_authService.isLoggedIn) {
      throw Exception('로그인이 필요합니다.');
    }

    try {
      if (kDebugMode) print('🔍 CreditService: checkCredits 호출 - $videoDurationInSeconds초');
      
      final idToken = await _authService.getIdToken();
      if (idToken == null) {
        throw Exception('ID 토큰을 가져올 수 없습니다.');
      }
      
      final result = await _functionsService.checkCredits(videoDurationInSeconds, idToken: idToken);
      
      if (result['success']) {
        final data = result['data'] as Map<String, dynamic>;
        if (kDebugMode) {
          print('✅ CreditService: checkCredits 성공');
          print('   - 현재 크레딧: ${data['currentCredits']}');
          print('   - 필요 크레딧: ${data['requiredCredits']}');
          print('   - 작업 가능: ${data['canPerform']}');
          print('   - 메시지: ${data['message']}');
        }
        return data;
      } else {
        throw Exception('checkCredits 실패: ${result['error']}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ CreditService: checkCredits 오류: $e');
      rethrow;
    }
  }
}
