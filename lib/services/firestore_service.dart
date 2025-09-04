import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'auth_service.dart';

class FirestoreService {
  static final FirestoreService _instance = FirestoreService._internal();
  factory FirestoreService() => _instance;
  FirestoreService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();

  // Actions 컬렉션에 작업 기록 저장
  Future<bool> saveAction({
    required String type, // 'transcribe' 또는 'summarize'
    required bool success,
    required int processingTime,
    required int creditCost,
    required int remainingCredits,
    Map<String, dynamic>? transcribeMeta,
    Map<String, dynamic>? summarizeMeta,
  }) async {
    if (!_authService.isLoggedIn) {
      if (kDebugMode) print('❌ FirestoreService: 로그인되지 않은 사용자');
      return false;
    }

    try {
      final actionId = _generateUUID();
      final userId = _authService.currentUser!.uid;
      
      final actionData = {
        'success': success,
        'type': type,
        'actionId': actionId,
        'userId': userId,
        'processingTime': processingTime,
        'remainingCredits': remainingCredits,
        'timestamp': FieldValue.serverTimestamp(),
        'creditCost': creditCost,
      };

      // 타입별 메타데이터 추가
      if (type == 'transcribe' && transcribeMeta != null) {
        actionData['transcribeMeta'] = transcribeMeta;
      } else if (type == 'summarize' && summarizeMeta != null) {
        actionData['summarizeMeta'] = summarizeMeta;
      }

      await _firestore.collection('actions').doc(actionId).set(actionData);
      
      if (kDebugMode) print('✅ FirestoreService: 작업 기록 저장 성공 - $type');
      return true;
    } catch (e) {
      if (kDebugMode) print('❌ FirestoreService: 작업 기록 저장 실패: $e');
      return false;
    }
  }

  // 주의: 크레딧 업데이트는 Firebase Functions에서 처리됩니다.
  // 클라이언트에서 직접 호출하면 안됩니다.

  // 사용자 크레딧 가져오기 (Firebase Functions 사용)
  Future<int> getUserCredits() async {
    if (!_authService.isLoggedIn) {
      if (kDebugMode) print('❌ FirestoreService: 로그인되지 않은 사용자');
      return 0;
    }

    try {
      final idToken = await _authService.getIdToken();
      if (idToken == null) {
        if (kDebugMode) print('❌ FirestoreService: ID 토큰 없음');
        return 0;
      }

      final response = await http.get(
        Uri.parse('https://getcredits-v4kacndtqq-uc.a.run.app'),
        headers: {
          'Authorization': 'Bearer $idToken',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final credits = data['credits'] ?? 0;
        if (kDebugMode) print('✅ FirestoreService: 크레딧 조회 성공: $credits');
        return credits;
      } else {
        if (kDebugMode) print('❌ FirestoreService: 크레딧 조회 실패: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      if (kDebugMode) print('❌ FirestoreService: 크레딧 조회 실패: $e');
      return 0;
    }
  }

  // 앱 업데이트 정보 가져오기
  Future<Map<String, dynamic>?> getUpdateInfo() async {
    try {
      final doc = await _firestore.collection('updates').doc('latest').get();
      
      if (doc.exists) {
        final data = doc.data();
        if (kDebugMode) print('✅ FirestoreService: 업데이트 정보 조회 성공');
        return data;
      }
      
      if (kDebugMode) print('⚠️ FirestoreService: 업데이트 정보가 존재하지 않음');
      return null;
    } catch (e) {
      if (kDebugMode) print('❌ FirestoreService: 업데이트 정보 조회 실패: $e');
      return null;
    }
  }

  // 사용자 작업 내역 가져오기
  Future<List<Map<String, dynamic>>> getUserActions({
    int limit = 10,
    String? type,
  }) async {
    if (!_authService.isLoggedIn) {
      if (kDebugMode) print('❌ FirestoreService: 로그인되지 않은 사용자');
      return [];
    }

    try {
      Query query = _firestore
          .collection('actions')
          .where('userId', isEqualTo: _authService.currentUser!.uid)
          .orderBy('timestamp', descending: true)
          .limit(limit);

      if (type != null) {
        query = query.where('type', isEqualTo: type);
      }

      final snapshot = await query.get();
      final actions = snapshot.docs.map((doc) => {
        'id': doc.id,
        ...doc.data() as Map<String, dynamic>,
      }).toList();

      if (kDebugMode) print('✅ FirestoreService: 작업 내역 조회 성공: ${actions.length}개');
      return actions;
    } catch (e) {
      if (kDebugMode) print('❌ FirestoreService: 작업 내역 조회 실패: $e');
      return [];
    }
  }

  // 사용자 통계 가져오기
  Future<Map<String, dynamic>> getUserStats() async {
    if (!_authService.isLoggedIn) {
      if (kDebugMode) print('❌ FirestoreService: 로그인되지 않은 사용자');
      return {};
    }

    try {
      final userId = _authService.currentUser!.uid;
      
      // 전체 작업 수
      final totalActions = await _firestore
          .collection('actions')
          .where('userId', isEqualTo: userId)
          .get();

      // 성공한 작업 수
      final successfulActions = await _firestore
          .collection('actions')
          .where('userId', isEqualTo: userId)
          .where('success', isEqualTo: true)
          .get();

      // transcribe 작업 수
      final transcribeActions = await _firestore
          .collection('actions')
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'transcribe')
          .get();

      // summarize 작업 수
      final summarizeActions = await _firestore
          .collection('actions')
          .where('userId', isEqualTo: userId)
          .where('type', isEqualTo: 'summarize')
          .get();

      final stats = {
        'totalActions': totalActions.docs.length,
        'successfulActions': successfulActions.docs.length,
        'transcribeActions': transcribeActions.docs.length,
        'summarizeActions': summarizeActions.docs.length,
        'successRate': totalActions.docs.isNotEmpty 
            ? (successfulActions.docs.length / totalActions.docs.length * 100).round()
            : 0,
      };

      if (kDebugMode) print('✅ FirestoreService: 사용자 통계 조회 성공');
      return stats;
    } catch (e) {
      if (kDebugMode) print('❌ FirestoreService: 사용자 통계 조회 실패: $e');
      return {};
    }
  }

  // UUID 생성 (간단한 버전)
  String _generateUUID() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = math.Random().nextInt(1000000);
    return '${timestamp}_${random}';
  }
}

