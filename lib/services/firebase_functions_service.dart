import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../utils/constants.dart';

/// Firebase Functions 호출을 위한 서비스
class FirebaseFunctionsService {
  static final FirebaseFunctionsService _instance = FirebaseFunctionsService._internal();
  factory FirebaseFunctionsService() => _instance;
  FirebaseFunctionsService._internal();

  /// HTTP 요청 헤더 생성 (Firebase ID 토큰 포함)
  Map<String, String> _getHeaders(String idToken) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    };
  }

  /// 로그인 로깅
  Future<Map<String, dynamic>> logLogin({String? email, required String idToken}) async {
    try {
      if (kDebugMode) print('🔐 FirebaseFunctionsService: logLogin 호출');
      
      final headers = _getHeaders(idToken);
      final response = await http.post(
        Uri.parse(FirebaseFunctionsUrls.logLogin),
        headers: headers,
        body: jsonEncode({'email': email}),
      );

      if (response.statusCode == 200) {
        if (kDebugMode) print('✅ FirebaseFunctionsService: logLogin 성공');
        return {'success': true, 'data': jsonDecode(response.body)};
      } else {
        if (kDebugMode) print('❌ FirebaseFunctionsService: logLogin 실패 - ${response.statusCode}');
        return {'success': false, 'error': response.body};
      }
    } catch (e) {
      if (kDebugMode) print('❌ FirebaseFunctionsService: logLogin 오류 - $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 이메일 인증 상태 확인
  Future<Map<String, dynamic>> checkEmailVerified({required String idToken}) async {
    try {
      if (kDebugMode) print('📧 FirebaseFunctionsService: checkEmailVerified 호출');
      
      final headers = _getHeaders(idToken);
      final response = await http.get(
        Uri.parse(FirebaseFunctionsUrls.checkEmailVerified),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (kDebugMode) print('✅ FirebaseFunctionsService: checkEmailVerified 성공 - ${data['email_verified']}');
        return {'success': true, 'data': data};
      } else {
        if (kDebugMode) print('❌ FirebaseFunctionsService: checkEmailVerified 실패 - ${response.statusCode}');
        return {'success': false, 'error': response.body};
      }
    } catch (e) {
      if (kDebugMode) print('❌ FirebaseFunctionsService: checkEmailVerified 오류 - $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 업데이트 정보 조회
  Future<Map<String, dynamic>> getUpdateInfo({String platform = 'mac'}) async {
    try {
      if (kDebugMode) print('📱 FirebaseFunctionsService: getUpdateInfo 호출 - $platform');
      
      final response = await http.get(
        Uri.parse('${FirebaseFunctionsUrls.getUpdateInfo}?platform=$platform'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (kDebugMode) print('✅ FirebaseFunctionsService: getUpdateInfo 성공');
        return {'success': true, 'data': data};
      } else {
        if (kDebugMode) print('❌ FirebaseFunctionsService: getUpdateInfo 실패 - ${response.statusCode}');
        return {'success': false, 'error': response.body};
      }
    } catch (e) {
      if (kDebugMode) print('❌ FirebaseFunctionsService: getUpdateInfo 오류 - $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 크레딧 조회
  Future<Map<String, dynamic>> getCredits({required String idToken}) async {
    try {
      if (kDebugMode) print('💰 FirebaseFunctionsService: getCredits 호출');
      
      final headers = _getHeaders(idToken);
      final response = await http.get(
        Uri.parse(FirebaseFunctionsUrls.getCredits),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (kDebugMode) print('✅ FirebaseFunctionsService: getCredits 성공 - ${data['credits']}');
        return {'success': true, 'data': data};
      } else {
        if (kDebugMode) print('❌ FirebaseFunctionsService: getCredits 실패 - ${response.statusCode}');
        return {'success': false, 'error': response.body};
      }
    } catch (e) {
      if (kDebugMode) print('❌ FirebaseFunctionsService: getCredits 오류 - $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 크레딧 차감
  Future<Map<String, dynamic>> deductCredits(int cost, {required String idToken}) async {
    try {
      if (kDebugMode) print('💸 FirebaseFunctionsService: deductCredits 호출 - $cost');
      
      final headers = _getHeaders(idToken);
      final response = await http.post(
        Uri.parse(FirebaseFunctionsUrls.deductCredits),
        headers: headers,
        body: jsonEncode({'cost': cost}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (kDebugMode) print('✅ FirebaseFunctionsService: deductCredits 성공 - ${data['credits']}');
        return {'success': true, 'data': data};
      } else {
        if (kDebugMode) print('❌ FirebaseFunctionsService: deductCredits 실패 - ${response.statusCode}');
        return {'success': false, 'error': response.body};
      }
    } catch (e) {
      if (kDebugMode) print('❌ FirebaseFunctionsService: deductCredits 오류 - $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 크레딧 확인 (비디오 길이 기반)
  Future<Map<String, dynamic>> checkCredits(double duration, {required String idToken}) async {
    try {
      if (kDebugMode) print('🔍 FirebaseFunctionsService: checkCredits 호출 - $duration');
      
      final headers = _getHeaders(idToken);
      final response = await http.post(
        Uri.parse(FirebaseFunctionsUrls.checkCredits),
        headers: headers,
        body: jsonEncode({'duration': duration}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (kDebugMode) print('✅ FirebaseFunctionsService: checkCredits 성공');
        return {'success': true, 'data': data};
      } else {
        if (kDebugMode) print('❌ FirebaseFunctionsService: checkCredits 실패 - ${response.statusCode}');
        return {'success': false, 'error': response.body};
      }
    } catch (e) {
      if (kDebugMode) print('❌ FirebaseFunctionsService: checkCredits 오류 - $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// 액션 로깅 (음성인식 + 요약 통합)
  Future<Map<String, dynamic>> logAction({
    required String actionId,
    required bool success,
    required String idToken,
    int? creditCost,
    int? remainingCredits,
    int? processingTime,
    Map<String, dynamic>? transcribeMeta,
    Map<String, dynamic>? summarizeMeta,
  }) async {
    try {
      if (kDebugMode) print('📝 FirebaseFunctionsService: logAction 호출 - $actionId');
      
      final headers = _getHeaders(idToken);
      final body = {
        'actionId': actionId,
        'type': 'transcribe-summarize',
        'success': success,
        'creditCost': creditCost,
        'remainingCredits': remainingCredits,
        'processingTime': processingTime,
        'transcribeMeta': transcribeMeta ?? {},
        'summarizeMeta': summarizeMeta ?? {},
      };

      final response = await http.post(
        Uri.parse(FirebaseFunctionsUrls.logAction),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (kDebugMode) print('✅ FirebaseFunctionsService: logAction 성공');
        return {'success': true, 'data': data};
      } else {
        if (kDebugMode) print('❌ FirebaseFunctionsService: logAction 실패 - ${response.statusCode}');
        return {'success': false, 'error': response.body};
      }
    } catch (e) {
      if (kDebugMode) print('❌ FirebaseFunctionsService: logAction 오류 - $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
