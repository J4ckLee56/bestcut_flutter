import 'dart:convert';
import 'dart:math' as math;
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

  /// GPT를 사용한 챕터 분석
  Future<Map<String, dynamic>> analyzeChapterWithGPT({
    required int chapterIndex,
    required List<Map<String, dynamic>> segments,
    required String idToken,
    String? previousChapterSummary,
    String? nextChapterPreview,
  }) async {
    try {
      if (kDebugMode) {
        print('🤖 FirebaseFunctionsService: analyzeChapterWithGPT 호출 - 챕터 $chapterIndex');
      }

      final headers = _getHeaders(idToken);
      
      // 세그먼트 데이터 준비
      final segmentsText = segments.map((s) {
        return '[${s['id']}] ${s['startSec']}s-${s['endSec']}s: ${s['text']}';
      }).join('\n');

      // 프롬프트 구성
      final systemPrompt = '''당신은 비디오 콘텐츠 분석 전문가입니다. 주어진 세그먼트들을 분석하여 구조화된 정보를 제공해주세요.

응답은 반드시 다음 JSON 형식으로만 제공해주세요:
{
  "chapter_index": $chapterIndex,
  "main_topic": "이 챕터의 주요 주제 (명확하고 구체적으로)",
  "key_points": ["핵심 포인트 1", "핵심 포인트 2", "핵심 포인트 3"],
  "important_range": {
    "start_segment_id": 가장 중요한 내용이 시작하는 세그먼트 ID,
    "end_segment_id": 가장 중요한 내용이 끝나는 세그먼트 ID,
    "reason": "이 범위를 선택한 이유"
  },
  "exclude_segments": [제외할 세그먼트 ID 목록],
  "repetition_groups": [
    {
      "segments": [반복되는 세그먼트 ID들],
      "keep": 유지할 세그먼트 ID,
      "reason": "선택 이유"
    }
  ],
  "summary": "이 챕터의 핵심 내용을 2-3문장으로 요약"
}

중요 사항:
- main_topic은 명확하고 구체적인 주제여야 합니다 (예: "북한의 대외 정책 변화").
- important_range는 챕터 내에서 가장 핵심적인 내용이 담긴 연속된 구간을 선택해야 합니다.
- exclude_segments는 중요도가 낮거나 불필요한 세그먼트만 포함해야 합니다.
- 반복되는 내용이 있다면 가장 명확하고 완전한 표현만 유지하세요.''';

      String userPrompt = '다음은 비디오의 챕터 $chapterIndex 세그먼트들입니다:\n\n$segmentsText';
      
      if (previousChapterSummary != null) {
        userPrompt += '\n\n이전 챕터 요약: $previousChapterSummary';
      }
      
      if (nextChapterPreview != null) {
        userPrompt += '\n\n다음 챕터 미리보기: $nextChapterPreview';
      }
      
      userPrompt += '\n\n위 세그먼트들을 분석하여 JSON 형식으로 정보를 제공해주세요.';

      final messages = [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ];

      final response = await http.post(
        Uri.parse(FirebaseFunctionsUrls.chatProxy),
        headers: headers,
        body: jsonEncode({'messages': messages}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['content'] as String;
        
        // JSON 파싱 시도
        try {
          // JSON 코드 블록 제거
          String jsonStr = content.trim();
          if (jsonStr.startsWith('```json')) {
            jsonStr = jsonStr.substring(7);
          }
          if (jsonStr.startsWith('```')) {
            jsonStr = jsonStr.substring(3);
          }
          if (jsonStr.endsWith('```')) {
            jsonStr = jsonStr.substring(0, jsonStr.length - 3);
          }
          jsonStr = jsonStr.trim();
          
          final result = jsonDecode(jsonStr) as Map<String, dynamic>;
          if (kDebugMode) {
            print('✅ FirebaseFunctionsService: analyzeChapterWithGPT 성공');
          }
          return {'success': true, 'data': result};
        } catch (e) {
          if (kDebugMode) {
            print('⚠️ FirebaseFunctionsService: JSON 파싱 실패, 원본 반환: $e');
          }
          return {'success': true, 'data': {'raw_content': content}};
        }
      } else {
        if (kDebugMode) {
          print('❌ FirebaseFunctionsService: analyzeChapterWithGPT 실패 - ${response.statusCode}');
        }
        return {'success': false, 'error': response.body};
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ FirebaseFunctionsService: analyzeChapterWithGPT 오류 - $e');
      }
      return {'success': false, 'error': e.toString()};
    }
  }

  /// GPT를 사용한 챕터 분할
  Future<Map<String, dynamic>> segmentChaptersWithGPT({
    required List<Map<String, dynamic>> segments,
    required String idToken,
    int desiredChapterCount = 6,
  }) async {
    try {
      if (kDebugMode) {
        print('🤖 FirebaseFunctionsService: segmentChaptersWithGPT 호출');
      }

      final headers = _getHeaders(idToken);
      
      // 세그먼트 데이터 준비 (청크 크기 제한: 최대 200개)
      final int maxSegmentsPerRequest = 200;
      final List<List<Map<String, dynamic>>> segmentChunks = [];
      
      for (int i = 0; i < segments.length; i += maxSegmentsPerRequest) {
        final end = math.min(i + maxSegmentsPerRequest, segments.length);
        segmentChunks.add(segments.sublist(i, end));
      }

      final List<Map<String, dynamic>> allChapters = [];

      for (int chunkIdx = 0; chunkIdx < segmentChunks.length; chunkIdx++) {
        final chunk = segmentChunks[chunkIdx];
        final segmentsText = chunk.map((s) {
          return '[${s['id']}] ${s['startSec']}s-${s['endSec']}s: ${s['text']}';
        }).join('\n');

        final systemPrompt = '''당신은 비디오 콘텐츠 분석 전문가입니다. 주어진 세그먼트들을 분석하여 내용 전환점을 파악하고 챕터로 분할해주세요.

응답은 반드시 다음 JSON 형식으로만 제공해주세요:
{
  "chapters": [
    {
      "chapter_index": 1,
      "start_segment_id": 시작 세그먼트 ID,
      "end_segment_id": 끝 세그먼트 ID,
      "main_topic": "이 챕터의 주요 주제 (명확하고 구체적으로)",
      "key_points": ["핵심 포인트 1", "핵심 포인트 2"]
    },
    ...
  ]
}

중요 사항:
- 내용의 주제나 화제가 바뀌는 지점을 정확히 파악하여 챕터로 분할하세요.
- 각 챕터는 명확한 주제를 가져야 합니다.
- 챕터 수는 ${desiredChapterCount}개 정도를 목표로 하되, 내용에 따라 조정 가능합니다.
- main_topic은 명확하고 구체적이어야 합니다 (예: "북한의 대외 정책 변화", "남북 관계의 현황과 전망").''';

        String userPrompt = '다음은 비디오의 세그먼트들입니다:\n\n$segmentsText';
        
        if (chunkIdx > 0) {
          userPrompt += '\n\n이전 청크의 마지막 챕터 정보를 참고하여 연속성을 유지하세요.';
        }
        
        userPrompt += '\n\n위 세그먼트들을 분석하여 챕터로 분할하고 JSON 형식으로 정보를 제공해주세요.';

        final messages = [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ];

        final response = await http.post(
          Uri.parse(FirebaseFunctionsUrls.chatProxy),
          headers: headers,
          body: jsonEncode({'messages': messages}),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final content = data['content'] as String;
          
          try {
            String jsonStr = content.trim();
            if (jsonStr.startsWith('```json')) {
              jsonStr = jsonStr.substring(7);
            }
            if (jsonStr.startsWith('```')) {
              jsonStr = jsonStr.substring(3);
            }
            if (jsonStr.endsWith('```')) {
              jsonStr = jsonStr.substring(0, jsonStr.length - 3);
            }
            jsonStr = jsonStr.trim();
            
            final result = jsonDecode(jsonStr) as Map<String, dynamic>;
            if (result['chapters'] != null) {
              final chapters = List<Map<String, dynamic>>.from(result['chapters'] as List);
              // 청크 오프셋 보정
              final chunkStartId = chunk.first['id'] as int;
              for (final chapter in chapters) {
                final startId = chapter['start_segment_id'] as int;
                final endId = chapter['end_segment_id'] as int;
                // 실제 세그먼트 ID로 매핑 필요 (청크 내 인덱스가 아닌)
                allChapters.add(chapter);
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('⚠️ FirebaseFunctionsService: JSON 파싱 실패: $e');
            }
          }
        }
      }

      if (kDebugMode) {
        print('✅ FirebaseFunctionsService: segmentChaptersWithGPT 성공 - ${allChapters.length}개 챕터');
      }
      return {'success': true, 'data': {'chapters': allChapters}};
    } catch (e) {
      if (kDebugMode) {
        print('❌ FirebaseFunctionsService: segmentChaptersWithGPT 오류 - $e');
      }
      return {'success': false, 'error': e.toString()};
    }
  }
}
