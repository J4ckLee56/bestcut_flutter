import 'package:flutter/foundation.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class CreditService {
  static final CreditService _instance = CreditService._internal();
  factory CreditService() => _instance;
  CreditService._internal();

  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();


  // 사용자 크레딧 잔액 확인 (Firebase Functions 사용)
  Future<int> getUserCredits() async {
    if (!_authService.isLoggedIn) {
      if (kDebugMode) print('❌ CreditService: 로그인되지 않은 사용자');
      return 0;
    }

    try {
      final credits = await _firestoreService.getUserCredits();
      if (kDebugMode) print('💰 CreditService: 현재 크레딧: $credits');
      return credits;
    } catch (e) {
      if (kDebugMode) print('❌ CreditService: 크레딧 조회 실패: $e');
      return 0;
    }
  }

  // 주의: 크레딧 차감과 충전은 Firebase Functions에서 처리됩니다.
  // 클라이언트에서 직접 호출하면 안됩니다.



  // checkCredits Firebase Function 호출
  Future<Map<String, dynamic>> checkCredits(double videoDurationInSeconds) async {
    if (!_authService.isLoggedIn) {
      throw Exception('로그인이 필요합니다.');
    }

    try {
      final idToken = await _authService.getIdToken();
      if (idToken == null) {
        throw Exception('ID 토큰을 가져올 수 없습니다.');
      }

      final response = await http.post(
        Uri.parse('https://us-central1-bestcut-beta.cloudfunctions.net/checkCredits'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'duration': videoDurationInSeconds,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (kDebugMode) {
          print('✅ CreditService: checkCredits 성공');
          print('   - 현재 크레딧: ${data['currentCredits']}');
          print('   - 필요 크레딧: ${data['requiredCredits']}');
          print('   - 작업 가능: ${data['canPerform']}');
          print('   - 메시지: ${data['message']}');
        }
        return data;
      } else {
        throw Exception('checkCredits 실패: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ CreditService: checkCredits 오류: $e');
      rethrow;
    }
  }
}
