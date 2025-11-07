import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../models/app_state.dart';
import '../models/whisper_segment.dart';
import '../models/theme_group.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'credit_service.dart';
import 'firebase_functions_service.dart';

// 취소 예외 클래스
class CancellationException implements Exception {
  final String message;
  CancellationException(this.message);
  
  @override
  String toString() => message;
}

class AIService {
  final AppState appState;
  final BuildContext context;
  bool _isCancelled = false; // 작업 취소 플래그
  Completer<void>? _currentOperationCompleter; // 현재 작업을 제어하는 Completer
  Process? _whisperProcess; // whisper.cpp 프로세스 추적
  http.Client? _httpClient; // HTTP 요청 취소를 위한 클라이언트
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final CreditService _creditService = CreditService();
  final FirebaseFunctionsService _functionsService = FirebaseFunctionsService();

  static const double _kMinimumWordDuration = 0.05; // 50ms
  static const double _kGapTolerance = 1e-6;
  static const double _kMinimumFfmpegSilenceDuration = 0.3;
  static const double _kFfmpegSilenceMargin = 0.1; // FFmpeg 무음 결과 좌우 여유 (초)
  static const double _kFfmpegBoundaryRespectTolerance = 0.005; // 5ms 이내면 조정 생략
  AIService(this.appState, this.context);

  double _floorToCentisecond(double value) => (value * 100).floorToDouble() / 100.0;

  double _ceilToCentisecond(double value) => (value * 100).ceilToDouble() / 100.0;

  double _roundToCentisecond(double value) => (value * 100).roundToDouble() / 100.0;

  // 무음을 WordSegment로 추가/병합 (새로운 방식)
  WordSegment? _addOrMergeSilenceAsWord(
    List<WordSegment> target,
    double start,
    double end, {
    double gapTolerance = _kGapTolerance,
  }) {
    final double normalizedStart = _floorToCentisecond(start);
    final double normalizedEnd = _ceilToCentisecond(end);

    if (normalizedEnd - normalizedStart <= gapTolerance) {
      return null;
    }

    // 기존 무음과 병합 가능한지 확인
    for (int i = 0; i < target.length; i++) {
      final existing = target[i];
      if (!existing.isSilence) continue; // 단어는 건너뛰기
      
      final bool overlaps =
          normalizedEnd >= existing.startSec - gapTolerance &&
          normalizedStart <= existing.endSec + gapTolerance;

      if (overlaps) {
        final double mergedStart = math.min(existing.startSec, normalizedStart);
        final double mergedEnd = math.max(existing.endSec, normalizedEnd);
        final mergedSegment = WordSegment(
          index: existing.index,
          word: '',
          startSec: mergedStart,
          endSec: mergedEnd,
          score: 1.0,
          isSilence: true,
        );
        target[i] = mergedSegment;
        return mergedSegment;
      }
    }

    // 새 무음 추가
    final newSegment = WordSegment(
      index: target.length,
      word: '',
      startSec: normalizedStart,
      endSec: normalizedEnd,
      score: 1.0,
      isSilence: true,
    );
    target.add(newSegment);
    return newSegment;
  }
  
  // 구버전 호환용 (SilenceSegment 기반) - 점진적 마이그레이션용
  SilenceSegment? _addOrMergeSilence(
    List<SilenceSegment> target,
    double start,
    double end, {
    double gapTolerance = _kGapTolerance,
  }) {
    final double normalizedStart = _floorToCentisecond(start);
    final double normalizedEnd = _ceilToCentisecond(end);

    if (normalizedEnd - normalizedStart <= gapTolerance) {
      return null;
    }

    for (int i = 0; i < target.length; i++) {
      final existing = target[i];
      final bool overlaps =
          normalizedEnd >= existing.startSec - gapTolerance &&
          normalizedStart <= existing.endSec + gapTolerance;

      if (overlaps) {
        final double mergedStart = math.min(existing.startSec, normalizedStart);
        final double mergedEnd = math.max(existing.endSec, normalizedEnd);
        final mergedSegment = SilenceSegment(
          startSec: mergedStart,
          endSec: mergedEnd,
          duration: mergedEnd - mergedStart,
        );
        target[i] = mergedSegment;
        return mergedSegment;
      }
    }

    final newSegment = SilenceSegment(
      startSec: normalizedStart,
      endSec: normalizedEnd,
      duration: normalizedEnd - normalizedStart,
    );
    target.add(newSegment);
    return newSegment;
  }

  List<SilenceSegment> _extractSilenceSegments(List<WordSegment> words) {
    return [
      for (final word in words)
        if (word.isSilence)
          SilenceSegment(
            startSec: word.startSec,
            endSec: word.endSec,
            duration: word.endSec - word.startSec,
          ),
    ];
  }

  // CreditService getter
  CreditService get creditService => _creditService;

  // 통합 액션 로깅 (Firebase Functions 호출)
  Future<void> _logAction({
    required String actionId,
    required bool success,
    int? creditCost,
    int? remainingCredits,
    int? processingTime,
    Map<String, dynamic>? transcribeMeta,
    Map<String, dynamic>? summarizeMeta,
  }) async {
    try {
      if (kDebugMode) print('📝 AIService: 통합 액션 로깅 시도: $actionId');
      
      final idToken = await _authService.getIdToken();
      if (idToken == null) {
        if (kDebugMode) print('⚠️ AIService: ID 토큰 없음, 액션 로깅 건너뜀');
        return;
      }
      
      final result = await _functionsService.logAction(
        actionId: actionId,
        success: success,
        idToken: idToken,
        creditCost: creditCost,
        remainingCredits: remainingCredits,
        processingTime: processingTime,
        transcribeMeta: transcribeMeta,
        summarizeMeta: summarizeMeta,
      );
      
      if (result['success']) {
        if (kDebugMode) print('✅ AIService: 통합 액션 로깅 성공');
      } else {
        if (kDebugMode) print('⚠️ AIService: 통합 액션 로깅 실패: ${result['error']}');
      }
    } catch (e) {
      if (kDebugMode) print('❌ AIService: 통합 액션 로깅 오류: $e');
      // 로깅 실패는 AI 작업 성공에 영향을 주지 않음
    }
  }

  // HTTP 클라이언트 초기화
  http.Client _getHttpClient() {
    if (_httpClient == null) {
      _httpClient = http.Client();
    }
    return _httpClient!;
  }

  // 작업 취소
  void cancelOperation() {
    if (kDebugMode) print('❌ AIService: 작업 취소 요청됨');
    _isCancelled = true;
    appState.isOperationCancelled = true;
    
    // whisper.cpp 프로세스 강제 종료
    if (_whisperProcess != null) {
      try {
        if (kDebugMode) print('❌ AIService: whisper.cpp 프로세스 강제 종료 (PID: ${_whisperProcess!.pid})');
        _whisperProcess!.kill();
        _whisperProcess = null;
      } catch (e) {
        if (kDebugMode) print('❌ AIService: 프로세스 종료 실패: $e');
      }
    }
    
    // HTTP 요청 취소
    if (_httpClient != null) {
      try {
        if (kDebugMode) print('❌ AIService: HTTP 요청 취소');
        _httpClient!.close();
        _httpClient = null;
      } catch (e) {
        if (kDebugMode) print('❌ AIService: HTTP 요청 취소 실패: $e');
      }
    }
    
    // 현재 진행 중인 작업을 즉시 완료 처리
    if (_currentOperationCompleter != null && !_currentOperationCompleter!.isCompleted) {
      if (kDebugMode) print('❌ AIService: 현재 작업 Completer 완료 처리');
      _currentOperationCompleter!.complete();
    }
  }

  // 작업 취소 상태 확인
  bool get isCancelled => _isCancelled;

  // 작업 취소 상태 리셋
  void resetCancellation() {
    if (kDebugMode) print('🔄 AIService: 취소 상태 리셋');
    _isCancelled = false;
    appState.isOperationCancelled = false;
    
    // 프로세스 참조 정리
    _whisperProcess = null;
    
    // HTTP 클라이언트 정리
    _httpClient = null;
    
    // 새로운 작업을 위한 Completer 생성
    _currentOperationCompleter = Completer<void>();
  }

  // 작업 완료 처리
  void _completeOperation() {
    if (_currentOperationCompleter != null && !_currentOperationCompleter!.isCompleted) {
      _currentOperationCompleter!.complete();
    }
  }

  // 취소 체크 및 예외 발생
  void _checkCancellation() {
    if (_isCancelled || appState.isOperationCancelled) {
      if (kDebugMode) print('❌ AIService: 작업이 취소됨 - 예외 발생');
      throw CancellationException('작업이 취소되었습니다.');
    }
  }

  // 인증 체크
  void _checkAuthentication() {
    if (!_authService.isLoggedIn) {
      if (kDebugMode) print('❌ AIService: 로그인되지 않은 사용자 - 작업 차단');
      throw Exception('로그인이 필요합니다. 먼저 로그인해주세요.');
    }
  }

  // AI 기반 고급 챕터 생성
  Future<void> generateAdvancedChapters() async {
    try {
      if (kDebugMode) print('🤖 AIService: AI 기반 고급 챕터 생성 시작');
      
      if (appState.segments.isEmpty) {
        if (kDebugMode) print('❌ AIService: 세그먼트가 없습니다');
        _showErrorSnackBar('세그먼트가 없습니다. 먼저 음성인식을 진행해주세요.');
        return;
      }
      

      
      // OpenAI API를 사용한 고급 챕터 생성
      final themeGroups = await _generateChaptersWithAI();
      
      if (themeGroups.isNotEmpty) {
        // AppState에 고급 챕터 정보 업데이트
        appState.themeGroups = themeGroups;
        if (kDebugMode) print('✅ AIService: AI 기반 고급 챕터 생성 완료 - ${themeGroups.length}개 챕터');
        
        _showSuccessSnackBar('AI가 생성한 고급 챕터 정보가 완성되었습니다. ${themeGroups.length}개 챕터를 생성했습니다.');
      } else {
        _showErrorSnackBar('AI 챕터 생성에 실패했습니다.');
      }
      
    } catch (e) {
      if (kDebugMode) print('❌ AIService: AI 챕터 생성 중 오류: $e');
      _showErrorSnackBar('AI 챕터 생성 중 오류가 발생했습니다: $e');
    } finally {
      
    }
  }
  
  // 음성인식 시작
  Future<void> recognizeSpeech() async {
    print('=== 음성인식 시작 ===');
    
    // 인증 체크
    _checkAuthentication();
    
    // 이미 취소된 상태라면 작업 시작하지 않음
    if (_isCancelled || appState.isOperationCancelled) {
      if (kDebugMode) print('✅ AIService: 이미 취소된 상태 - 음성인식 작업 시작 안함');
      return;
    }
    
    try {
      final currentVideoPath = appState.videoPath;
      final session = appState.recognizeSession;
      if (currentVideoPath == null) {
        print('비디오 경로가 null입니다.');
        return;
      }
      
      print('비디오 경로: $currentVideoPath');
      
      // 기존 세그먼트 데이터 초기화
      appState.isRecognizing = true;
      appState.segments.clear(); // 이전 세그먼트 데이터 삭제
      appState.highlightedSegments.clear(); // 하이라이트된 세그먼트도 초기화
      appState.themeGroups.clear(); // 챕터 요약 박스도 초기화
      appState.currentSegmentIndex = -1; // 현재 세그먼트 인덱스 초기화
      appState.isPreviewMode = false; // 프리뷰 모드 해제
      
      print('기존 세그먼트 데이터 초기화 완료');
      
      // 취소 체크
      _checkCancellation();
      
      final audioPath = '${Directory.systemTemp.path}/extracted_audio.wav';
      print('오디오 추출 경로: $audioPath');
      
      // 오디오 추출 임시 파일 삭제(혹시 남아있을 경우)
      if (File(audioPath).existsSync()) {
        File(audioPath).deleteSync();
        print('기존 오디오 파일 삭제 완료');
      }
      
      // SRT 파일도 삭제하여 캐시 문제 방지
      final srtPath = '$audioPath.srt';
      if (File(srtPath).existsSync()) {
        File(srtPath).deleteSync();
        print('기존 SRT 파일 삭제 완료');
      }
      
      // ffmpeg로 오디오 추출
      print('=== FFmpeg 오디오 추출 시작 ===');
      
      // 취소 체크
      _checkCancellation();
      
      // 앱 내장 FFmpeg 경로 동적 탐지
      String ffmpegPath = _findFfmpegPath();
      
      final env = <String, String>{
        'PATH': '${_getAppResourcesPath()}:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin',
        'DYLD_LIBRARY_PATH': _getAppResourcesPath(),
        'DYLD_FRAMEWORK_PATH': _getAppResourcesPath(),
      };
      print('FFmpeg 경로: $ffmpegPath');
      print('FFmpeg 환경변수: $env');
      
      final result = await Process.run(
        ffmpegPath,
        ['-i', currentVideoPath, '-vn', '-acodec', 'pcm_s16le', '-ar', '16000', '-ac', '1', audioPath],
        environment: env,
        workingDirectory: _getAppResourcesPath(),
      );
      
      print('=== FFmpeg 실행 결과 ===');
      print('Exit Code: ${result.exitCode}');
      print('Stdout: ${result.stdout}');
      print('Stderr: ${result.stderr}');
      
      if (appState.videoPath != currentVideoPath || appState.recognizeSession != session || appState.isOperationCancelled) {
        print('영상이 변경되었거나 작업이 취소되었습니다. 결과 무시.');
        appState.isRecognizing = false;
        return;
      }
      
      if (result.exitCode != 0) {
        print('FFmpeg 오디오 추출 실패');
        appState.isRecognizing = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오디오 추출 실패: ${result.stderr}')),
        );
        return;
      }
      
      print('FFmpeg 오디오 추출 성공');
      
      // 취소 체크
      _checkCancellation();
      
      // 오디오 파일 존재 확인
      if (!File(audioPath).existsSync()) {
        print('오디오 파일이 생성되지 않았습니다.');
        appState.isRecognizing = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오디오 파일 생성 실패')),
        );
        return;
      }
      
      print('오디오 파일 크기: ${File(audioPath).lengthSync()} bytes');
      
      // FFmpeg로 오디오 에너지 프로파일 생성
      print('=== FFmpeg 오디오 에너지 분석 시작 ===');
      final energyProfile = await _analyzeAudioEnergy(audioPath, ffmpegPath, env);
      print('에너지 프레임: ${energyProfile.length}개 (${(energyProfile.length * 0.1).toStringAsFixed(1)}초)');
      
      // FFmpeg silencedetect로 무음 구간 감지
      print('=== FFmpeg 무음 구간 감지 시작 ===');
      final silences = await _detectSilence(audioPath, ffmpegPath, env);
      print('감지된 무음 구간: ${silences.length}개');
      for (final silence in silences) {
        print('  $silence');
      }
      
      // 로컬 Whisper 호출
      print('=== 로컬 Whisper 호출 시작 ===');
      
      final segments = await _callLocalWhisper(audioPath, silences, energyProfile);
      
      if (appState.videoPath != currentVideoPath || appState.recognizeSession != session || appState.isOperationCancelled) {
        print('영상이 변경되었거나 작업이 취소되었습니다. 결과 무시.');
        appState.isRecognizing = false;
        return;
      }
      
      if (segments.isNotEmpty) {
        print('로컬 Whisper 성공');
        print('파싱된 세그먼트 수: ${segments.length}');
        
        appState.segments = segments;
        appState.isRecognizing = false;
        print('=== 음성인식 완료 ===');
        
        // 크레딧 차감 및 데이터 저장
        await _handleTranscribeCompletion(segments);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('음성인식이 성공적으로 완료되었습니다. (${segments.length}개 세그먼트)')),
        );
        
        // 음성인식 완료 - 요약은 ProcessingScreen에서 처리
        print('음성인식 완료. 요약은 별도로 진행됩니다.');
      } else {
        print('로컬 Whisper 실패: 세그먼트가 없습니다.');
        appState.isRecognizing = false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로컬 Whisper 인식 실패: 세그먼트가 없습니다')),
        );
      }
      
    } catch (e) {
      if (e is CancellationException) {
        if (kDebugMode) print('✅ AIService: 음성인식 작업이 취소됨');
        appState.isRecognizing = false;
        return; // 취소된 경우 조용히 종료
      }
      
      print('음성인식 작업 중 오류: $e');
      appState.isRecognizing = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('음성인식 작업 중 오류가 발생했습니다: $e')),
      );
    } finally {
      // 작업 완료 처리
      _completeOperation();
    }
  }

  // 내용 요약 시작
  Future<void> summarizeScript() async {
    if (appState.segments.isEmpty) return;
    
    // 이미 요약이 진행 중이면 중복 실행 방지
    if (appState.isSummarizing) {
      if (kDebugMode) print('✅ AIService: 이미 요약이 진행 중 - 중복 실행 방지');
      return;
    }
    
    // 인증 체크
    _checkAuthentication();
    
    // 이미 취소된 상태라면 작업 시작하지 않음
    if (_isCancelled || appState.isOperationCancelled) {
      if (kDebugMode) print('✅ AIService: 이미 취소된 상태 - 요약 작업 시작 안함');
      return;
    }
    
    appState.isSummarizing = true;
    
    try {
      // 진행도 다이얼로그 표시

      // 청크 단위 처리 적용
      print('=== 청크 단위 처리 시작 ===');
      
      // 진행 상황 업데이트
      if (appState.progressStreamController != null && !appState.progressStreamController!.isClosed) {
        appState.progressStreamController!.add('전체 스크립트를 분석 가능한 청크로 나누고 있습니다...');
      }
      
      // 취소 체크
      _checkCancellation();
      
      final chunks = _createChunks(appState.segments);
      print('생성된 청크 수: ${chunks.length}');
      
      // 1단계: 각 청크별 개요 파악
      print('=== STEP 1: 청크별 개요 파악 시작 ===');
      
      // 취소 상태 직접 확인
        if (_isCancelled || appState.isOperationCancelled) {
          if (kDebugMode) print('✅ AIService: STEP 1에서 작업 취소됨');
          appState.isSummarizing = false;
        return;
      }
      
      List<Map<String, dynamic>> chunkOverviews = [];
      for (int i = 0; i < chunks.length; i++) {
        // 취소 상태 직접 확인
          if (_isCancelled || appState.isOperationCancelled) {
            if (kDebugMode) print('✅ AIService: STEP 1 루프에서 작업 취소됨');
            appState.isSummarizing = false;
          return;
        }
        
        print('--- Processing Chunk ${i + 1}/${chunks.length} ---');
        final overview = await _getChunkOverview(chunks[i], i + 1, chunks.length, '', Uri());
        chunkOverviews.add(overview);
      }
      
      // 2단계: 전체 구조 통합
      print('=== STEP 2: 전체 구조 통합 시작 ===');
      
      // 취소 상태 직접 확인
      if (_isCancelled || appState.isOperationCancelled) {
        if (kDebugMode) print('✅ AIService: STEP 2에서 작업 취소됨');
        appState.isSummarizing = false;
        return;
      }
      
      final overallStructure = await _integrateChunkOverviews(chunkOverviews, '', Uri());
      print('=== STEP 2 완료: 전체 구조 통합 ===');
      print('Overall Structure: $overallStructure');

      // 3단계: 주제별로 세그먼트 그룹화
      print('=== STEP 3: 주제별 세그먼트 그룹화 시작 ===');
      
      // 취소 상태 직접 확인
      if (_isCancelled || appState.isOperationCancelled) {
        if (kDebugMode) print('✅ AIService: STEP 3에서 작업 취소됨');
        appState.isSummarizing = false;
        return;
      }
      
      final themeGroups = await _groupSegmentsByTheme(appState.segments, overallStructure);
      print('=== STEP 3 완료: ${themeGroups.length}개 주제 그룹 생성 ===');
      for (int i = 0; i < themeGroups.length; i++) {
        print('Group ${i + 1}: ${themeGroups[i].segments.length} segments)');
      }
      
      appState.themeGroups = themeGroups;

      // 4단계: 각 주제별 세부 요약
      print('=== STEP 4: 주제별 세부 요약 시작 ===');
      
      // 취소 상태 직접 확인
      if (_isCancelled || appState.isOperationCancelled) {
        if (kDebugMode) print('✅ AIService: STEP 4에서 작업 취소됨');
        appState.isSummarizing = false;
        return;
      }
      
      List<int> allSelectedIds = [];
      for (int i = 0; i < themeGroups.length; i++) {
        // 취소 상태 직접 확인
          if (_isCancelled || appState.isOperationCancelled) {
            if (kDebugMode) print('✅ AIService: STEP 4 루프에서 작업 취소됨');
            appState.isSummarizing = false;
          return;
        }
        
        final group = themeGroups[i];
        print('--- Processing Theme Group ${i + 1}: ${group.theme} ---');
        final selectedIds = await _summarizeThemeGroup(group, '', Uri());
        print('Selected IDs for ${group.theme}: $selectedIds');
        allSelectedIds.addAll(selectedIds);
      }

      // 5단계: 중복 제거 및 최종 정리
      print('=== STEP 5: 중복 제거 및 최종 정리 ===');
      
      // 취소 상태 직접 확인
      if (_isCancelled || appState.isOperationCancelled) {
        if (kDebugMode) print('✅ AIService: STEP 5에서 작업 취소됨');
        appState.isSummarizing = false;
        return;
      }
      
      // 중복 제거
      final uniqueSelectedIds = allSelectedIds.toSet().toList();
      print('중복 제거 후 선택된 세그먼트 수: ${uniqueSelectedIds.length}');
      
      // 선택된 세그먼트들을 하이라이트
      appState.highlightedSegments = uniqueSelectedIds;
      
      // 최종 요약 텍스트 생성
      final finalSummary = await _generateFinalSummary(uniqueSelectedIds, '', Uri());
      appState.summary = finalSummary;
      
      print('=== 최종 요약 완료 ===');
      print('선택된 세그먼트 수: ${uniqueSelectedIds.length}');
      print('최종 요약 길이: ${finalSummary.length}');
      
      appState.isSummarizing = false;
      
      // 크레딧 차감 및 데이터 저장
      await _handleSummarizeCompletion(uniqueSelectedIds, finalSummary);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('내용 요약이 성공적으로 완료되었습니다! (${uniqueSelectedIds.length}개 세그먼트 선택)')),
      );
      
    } catch (e) {
      if (e is CancellationException) {
        if (kDebugMode) print('✅ AIService: 요약 작업이 취소됨');
        appState.isSummarizing = false;
        return; // 취소된 경우 조용히 종료
      }
      
      print('요약 작업 중 오류: $e');
      appState.isSummarizing = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('요약 작업 중 오류가 발생했습니다: $e')),
      );
    } finally {
      // 작업 완료 처리
      _completeOperation();
    }
  }

  // TODO: 나머지 헬퍼 메서드들 구현 필요
  // _callLocalWhisper, _createChunks, _getChunkOverview, _integrateChunkOverviews,
  // _groupSegmentsByTheme, _summarizeThemeGroup, _generateFinalSummary,
  

  /// whisper.cpp 호출 함수 (public)
  Future<List<WhisperSegment>> callLocalWhisper(String audioPath, List<SilenceSegment> silences, List<AudioEnergyFrame> energyProfile) async {
    print('=== whisper.cpp 호출 시작 ===');
    
    try {
      // whisper.cpp 실행 파일 경로 설정 (VAD 제거, large-v3-turbo만 사용)
      final projectRoot = _resolveProjectRoot();
      String whisperCliPath;
      String modelPath;

      if (Platform.isMacOS) {
        final projectDir = Directory.current.path;
        print('현재 디렉토리: $projectDir');
        print('프로젝트 루트: $projectRoot');
        whisperCliPath = '$projectRoot/whisper.cpp/build/bin/whisper-cli';
        modelPath = '$projectRoot/whisper.cpp/models/ggml-large-v3-turbo.bin';
      } else if (Platform.isWindows) {
        if (File('$projectRoot\\whisper.cpp\\build\\bin\\whisper-cli.exe').existsSync()) {
          whisperCliPath = '$projectRoot\\whisper.cpp\\build\\bin\\whisper-cli.exe';
          modelPath = '$projectRoot\\whisper.cpp\\models\\ggml-large-v3-turbo.bin';
        } else {
          final exeDir = Directory.current.path;
          whisperCliPath = '$exeDir\\whisper-cli.exe';
          modelPath = '$exeDir\\ggml-large-v3-turbo.bin';
        }
      } else {
        throw UnsupportedError('현재 macOS와 Windows만 지원됩니다.');
      }
      
      print('whisper-cli 경로: $whisperCliPath');
      print('모델 경로: $modelPath');
      
      // whisper.cpp 실행 (VAD 제거, 순수 large-v3-turbo만 사용)
      _whisperProcess = await Process.start(
        whisperCliPath,
        [
          '-m', modelPath,
          '-f', audioPath,
          '-l', 'ko',
          '-osrt',  // SRT 자막 출력
          '-oj',    // JSON 출력
          '-owts',  // 단어 타임스탬프 출력
          '-pp',    // 진행률 출력
          '-ml', '0',        // 세그먼트 최대 길이 제한 해제 (0 = 무제한)
          '-sow',            // 토큰이 아닌 단어 기준으로 분할
          '-wt', '0.01',     // 단어 신뢰도 임계값 (낮을수록 더 많은 단어 포함)
          '-nf',             // 온도 증가를 통한 재시도 방지 (일관된 결과)
        ],
      );
      
      print('=== whisper.cpp 프로세스 시작됨 (PID: ${_whisperProcess!.pid}) ===');
      
      // 프로세스 완료 대기
      final exitCode = await _whisperProcess!.exitCode;
      
      print('=== whisper.cpp 실행 결과 ===');
      print('Exit Code: $exitCode');
      
      if (exitCode != 0) {
        throw StateError('whisper.cpp 실행 실패: Exit Code $exitCode');
      }
      
      // SRT 파일에서 세그먼트 파싱
      // SRT 파일 경로 (whisper.cpp는 .wav.srt로 저장)
      final srtPath = '$audioPath.srt';
      if (!File(srtPath).existsSync()) {
        throw StateError('SRT 파일이 생성되지 않았습니다: $srtPath');
      }
      
      final srtContent = File(srtPath).readAsStringSync();
      final baseSegments = _parseSrtToSegments(srtContent);

      List<WhisperSegment> enrichedSegments = baseSegments;
      try {
        enrichedSegments = await _alignSegmentsWithWhisperX(
          audioPath: audioPath,
          baseSegments: baseSegments,
          projectRoot: projectRoot,
        );
      } catch (alignError) {
        if (kDebugMode) print('WhisperX 정렬 중 오류: $alignError');
      }

      print('whisper.cpp 성공: ${enrichedSegments.length}개 세그먼트 (단어 포함=${enrichedSegments.isNotEmpty && enrichedSegments.first.words.isNotEmpty})');
      
      // 에너지 프로파일 기반 단어·무음 정규화 단계
      print('=== 에너지 기반 단어·무음 타임라인 정규화 시작 ===');
      final normalizedSegments = _refineWordBoundariesWithEnergy(enrichedSegments, energyProfile);
      print('에너지 기반 단어·무음 타임라인 정규화 완료');

      print('=== FFmpeg 무음 구간 병합 시작 ===');
      final ffmpegMergedSegments = _mergeDetectedSilences(normalizedSegments, silences);
      print('FFmpeg 무음 구간 병합 완료 (감지된 무음 ${silences.length}개)');

      final continuityFixedSegments = _ensureContinuousWordTimeline(ffmpegMergedSegments);
      print('단어 타임라인 연속성 보정 완료');

      // 세그먼트 재조합 (짧은 세그먼트 병합)
      print('=== 세그먼트 재조합 시작 ===');
      final recombinedSegments = _recombineSegments(continuityFixedSegments);

      return recombinedSegments;
      
    } catch (e) {
      print('whisper.cpp 호출 중 오류: $e');
      rethrow;
    }
  }

  // whisper.cpp 호출 함수 (private - 내부용)
  Future<List<WhisperSegment>> _callLocalWhisper(String audioPath, List<SilenceSegment> silences, List<AudioEnergyFrame> energyProfile) async {
    return callLocalWhisper(audioPath, silences, energyProfile);
  }

  // SRT 파일을 WhisperSegment로 파싱하는 함수
  List<WhisperSegment> _parseSrtToSegments(String srtContent) {
    final List<WhisperSegment> segments = [];
    final lines = srtContent.split('\n');
    
    int currentId = 1;
    String? currentStart;
    String? currentEnd;
    String currentText = '';
    
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      
      if (line.isEmpty) {
        // 세그먼트 완료
        if (currentStart != null && currentEnd != null && currentText.isNotEmpty) {
          segments.add(WhisperSegment(
            id: currentId,
            startSec: double.parse(currentStart!),
            endSec: double.parse(currentEnd!),
            text: currentText.trim(),
          ));
          currentId++;
        }
        
        // 다음 세그먼트 준비
        currentStart = null;
        currentEnd = null;
        currentText = '';
        continue;
      }
      
      // 타임스탬프 라인 확인 (00:00:00,000 --> 00:00:05,000 형식)
      if (line.contains(' --> ')) {
        final parts = line.split(' --> ');
        if (parts.length == 2) {
          currentStart = _srtTimeToSeconds(parts[0].trim()).toString();
          currentEnd = _srtTimeToSeconds(parts[1].trim()).toString();
        }
        continue;
      }
      
      // 숫자가 아닌 라인은 텍스트로 처리
      if (int.tryParse(line) == null && !line.contains(' --> ')) {
        if (currentText.isNotEmpty) {
          currentText += ' ';
        }
        currentText += line;
      }
    }
    
    // 마지막 세그먼트 처리
    if (currentStart != null && currentEnd != null && currentText.isNotEmpty) {
      segments.add(WhisperSegment(
        id: currentId,
        startSec: double.parse(currentStart!),
        endSec: double.parse(currentEnd!),
        text: currentText.trim(),
      ));
    }
    
    return segments;
  }


  Future<List<WhisperSegment>> _alignSegmentsWithWhisperX({
    required String audioPath,
    required List<WhisperSegment> baseSegments,
    required String projectRoot,
  }) async {
    _checkCancellation();
    
    print('=== WhisperX 단어 정렬 시작 ===');

    final whisperJsonPath = '$audioPath.json';
    if (!File(whisperJsonPath).existsSync()) {
      print('⚠️ Whisper JSON 파일이 없어 정렬을 건너뜁니다: $whisperJsonPath');
      return baseSegments;
    }

    final originalScriptPath = '$projectRoot/tools/audio_pipeline/align_with_whisperx.py';
    if (!File(originalScriptPath).existsSync()) {
      if (kDebugMode) print('WhisperX 스크립트를 찾을 수 없어 정렬을 건너뜁니다: $originalScriptPath');
      return baseSegments;
    }

    final pythonExec = _findPythonExecutable(projectRoot);
    if (pythonExec == null) {
      if (kDebugMode) print('Python 실행 파일을 찾을 수 없습니다. 정렬을 건너뜁니다.');
      return baseSegments;
    }

    final sandboxTempDir = await Directory.systemTemp.createTemp('whisperx_align_');
    final tempScriptPath = '${sandboxTempDir.path}/align_with_whisperx.py';
    try {
      await File(originalScriptPath).copy(tempScriptPath);
    } catch (e) {
      if (kDebugMode) print('WhisperX 스크립트 복사 실패: $e');
      return baseSegments;
    }

    final alignedJsonPath = '$audioPath.aligned.json';
    final alignedVttPath = '$audioPath.aligned.vtt';

    final env = Map<String, String>.from(Platform.environment);
    final cacheDir = Directory('$projectRoot/hf_cache');
    if (cacheDir.existsSync()) {
      env['XDG_CACHE_HOME'] = cacheDir.path;
      env['HF_HOME'] = '${cacheDir.path}/huggingface';
      final hubCache = '${cacheDir.path}/huggingface/hub';
      env['HF_HUB_CACHE'] = hubCache;
      env['HUGGINGFACE_HUB_CACHE'] = hubCache;
      env['HF_DATASETS_CACHE'] = '${cacheDir.path}/datasets';
      env['TRANSFORMERS_CACHE'] = '${cacheDir.path}/transformers';
      env['HF_HUB_OFFLINE'] = '1';
      env['TRANSFORMERS_OFFLINE'] = '1';
    }

    try {
      final ffmpegPath = _findFfmpegPath();
      final ffmpegDir = File(ffmpegPath).parent.path;
      final existingPath = env['PATH'] ?? Platform.environment['PATH'] ?? '';
      env['PATH'] = '$ffmpegDir:$existingPath';
      env['FFMPEG_PATH'] = ffmpegPath;

      final resourcesPath = _getAppResourcesPath();
      final existingDyld = env['DYLD_LIBRARY_PATH'] ?? Platform.environment['DYLD_LIBRARY_PATH'] ?? '';
      final existingFramework = env['DYLD_FRAMEWORK_PATH'] ?? Platform.environment['DYLD_FRAMEWORK_PATH'] ?? '';
      env['DYLD_LIBRARY_PATH'] = [resourcesPath, existingDyld].where((e) => e.isNotEmpty).join(':');
      env['DYLD_FRAMEWORK_PATH'] = [resourcesPath, existingFramework].where((e) => e.isNotEmpty).join(':');
    } catch (_) {
      // ignore if ffmpeg path is not available here
    }

    final args = <String>[
      tempScriptPath,
      '--audio', audioPath,
      '--whisper-json', whisperJsonPath,
      '--output-json', alignedJsonPath,
      '--output-vtt', alignedVttPath,
      '--language', 'ko',
      '--device', 'cpu',
    ];
    if (cacheDir.existsSync()) {
      args.addAll(['--model-cache', cacheDir.path, '--align-model', 'kresnik/wav2vec2-large-xlsr-korean']);
    }

    ProcessResult result;
    try {
      result = await Process.run(
        pythonExec,
        args,
        workingDirectory: sandboxTempDir.path,
        environment: env,
      );
    } finally {
      try {
        sandboxTempDir.deleteSync(recursive: true);
      } catch (_) {}
    }

    _checkCancellation();

    if (result.exitCode != 0) {
      print('❌ WhisperX 정렬 실패 (${result.exitCode})');
      if (kDebugMode) {
        print('   stderr: ${result.stderr}');
        print('   stdout: ${result.stdout}');
      }
      return baseSegments;
    }
    
    print('✅ WhisperX Python 스크립트 실행 성공');
    if (kDebugMode && result.stdout.toString().isNotEmpty) {
      print('   stdout: ${result.stdout}');
    }

    final alignedFile = File(alignedJsonPath);
    if (!alignedFile.existsSync()) {
      print('⚠️ WhisperX 정렬 결과 파일을 찾을 수 없습니다: $alignedJsonPath');
      return baseSegments;
    }

    try {
      final data = jsonDecode(alignedFile.readAsStringSync());
      final segmentsData = data['segments'];
      if (segmentsData is! List) {
        if (kDebugMode) print('WhisperX 정렬 데이터 형식이 올바르지 않습니다.');
        return baseSegments;
      }

      final List<WhisperSegment> alignedSegments = [];
      for (int i = 0; i < segmentsData.length; i++) {
        final seg = segmentsData[i];
        if (seg is! Map<String, dynamic>) continue;

        final fallback = _segmentAt(baseSegments, i);
        final start = _asDouble(seg['start'], fallback: fallback?.startSec ?? 0.0);
        final end = _asDouble(seg['end'], fallback: fallback?.endSec ?? start);
        final rawText = (seg['text'] as String?)?.trim();

        final wordsData = seg['words'] as List<dynamic>? ?? const [];
        final List<WordSegment> wordSegments = [];
        double scoreSum = 0;
        int index = 0;
        for (final item in wordsData) {
          if (item is! Map<String, dynamic>) continue;
          final wordText = (item['word'] as String?)?.trim();
          if (wordText == null || wordText.isEmpty) continue;
          final wordStart = _asDouble(item['start'], fallback: start);
          final wordEnd = _asDouble(item['end'], fallback: end);
          final score = _asDouble(item['score'], fallback: 1.0);
          scoreSum += score;
          wordSegments.add(WordSegment(
            index: index,
            word: wordText,
            startSec: wordStart,
            endSec: wordEnd,
            score: score,
          ));
          index++;
        }

        double adjustedStart = start;
        double adjustedEnd = end;
        if (wordSegments.isNotEmpty) {
          adjustedStart = wordSegments.first.startSec;
          adjustedEnd = wordSegments.last.endSec;
        }

        final reconstructedText = wordSegments.isNotEmpty
            ? _reconstructTextFromWords(wordSegments)
            : null;

        final text = reconstructedText?.isNotEmpty == true
            ? reconstructedText!
            : (rawText?.isNotEmpty == true
                ? rawText!
                : fallback?.text ?? '');

        final confidence = wordSegments.isEmpty
            ? (seg['avg_logprob'] is num
                ? (seg['avg_logprob'] as num).toDouble()
                : fallback?.confidence ?? 1.0)
            : scoreSum / wordSegments.length;

        alignedSegments.add(WhisperSegment(
          id: fallback?.id ?? (alignedSegments.length + 1),
          startSec: adjustedStart,
          endSec: adjustedEnd,
          text: text,
          confidence: confidence,
          isSummary: fallback?.isSummary,
          words: wordSegments.isNotEmpty ? wordSegments : (fallback?.words ?? const []),
        ));
      }

      if (alignedSegments.isEmpty) {
        if (kDebugMode) print('WhisperX 정렬 결과가 비어 있습니다.');
        return baseSegments;
      }

      alignedSegments.sort((a, b) => a.startSec.compareTo(b.startSec));
      
      // 단어 정렬 통계
      int totalWords = 0;
      for (final seg in alignedSegments) {
        totalWords += seg.words.length;
      }
      print('✅ WhisperX 단어 정렬 완료: ${alignedSegments.length}개 세그먼트, $totalWords개 단어');
      
      return alignedSegments;
    } catch (e) {
      print('❌ WhisperX 정렬 JSON 파싱 실패: $e');
      return baseSegments;
    }
  }

  double _asDouble(dynamic value, {required double fallback}) {
    if (value == null) return fallback;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      final normalized = value.replaceAll(',', '.');
      final parsed = double.tryParse(normalized);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  WhisperSegment? _segmentAt(List<WhisperSegment> segments, int index) {
    if (index < 0 || index >= segments.length) return null;
    return segments[index];
  }

  String _resolveProjectRoot() {
    final envRoot = Platform.environment['BESTCUT_PROJECT_ROOT'];
    if (envRoot != null && File('$envRoot/pubspec.yaml').existsSync()) {
      return envRoot;
    }

    final current = Directory.current.path;
    if (File('$current/pubspec.yaml').existsSync()) {
      return current;
    }

    final executableDir = File(Platform.resolvedExecutable).parent;
    final candidates = <String>{
      current,
      executableDir.path,
      executableDir.parent.path,
      '/Users/ihuijae/Desktop/Flutter_Workspace/bestcut_flutter',
    };

    for (final path in candidates) {
      if (path.isEmpty) continue;
      if (File('$path/pubspec.yaml').existsSync()) {
        return path;
      }
    }

    return current;
  }

  String? _findPythonExecutable(String projectRoot) {
    final candidates = <String>[
      '$projectRoot/venv_whisperx/bin/python3',
      '$projectRoot/venv_whisperx/bin/python',
      'python3',
    ];

    for (final candidate in candidates) {
      if (candidate.contains('/')) {
        if (File(candidate).existsSync()) {
          return candidate;
        }
      } else {
        // 명령어 형태는 그대로 반환 (PATH 활용)
        return candidate;
      }
    }

    return null;
  }



  // 청크 단위 처리를 위한 메서드들
  List<List<WhisperSegment>> _createChunks(List<WhisperSegment> segments) {
    const int maxSegmentsPerChunk = 300; // 각 청크당 최대 세그먼트 수
    const int overlapSize = 30; // 오버랩 크기 (10% 정도)
    
    List<List<WhisperSegment>> chunks = [];
    int startIndex = 0;
    
    while (startIndex < segments.length) {
      int endIndex = (startIndex + maxSegmentsPerChunk).clamp(0, segments.length);
      
      // 마지막 청크가 아닌 경우 오버랩 적용
      if (endIndex < segments.length) {
        endIndex = (endIndex + overlapSize).clamp(0, segments.length);
      }
      
      chunks.add(segments.sublist(startIndex, endIndex));
      
      // 다음 청크 시작점 (오버랩 고려)
      if (endIndex < segments.length) {
        startIndex = endIndex - overlapSize;
      } else {
        break;
      }
    }
    
    return chunks;
  }

  Future<Map<String, dynamic>> _getChunkOverview(List<WhisperSegment> chunkSegments, int chunkIndex, int totalChunks, String apiKey, Uri uri) async {
    // 취소 상태 직접 확인
    if (_isCancelled || appState.isOperationCancelled) {
      if (kDebugMode) print('✅ AIService: _getChunkOverview에서 작업 취소됨');
      throw CancellationException('작업이 취소되었습니다.');
    }
    
    final formatted = chunkSegments.map((s) => {
      'id': s.id,
      'start': s.startSec,
      'end': s.endSec,
      'text': s.text,
    }).toList();

    final overviewPrompt = '''
다음은 영상의 ${chunkIndex}번째 청크 (전체 ${totalChunks}개 중)입니다.
이 청크의 주요 내용과 구조를 분석해주세요.

**청크 정보:**
- 청크 번호: ${chunkIndex}/${totalChunks}
- 세그먼트 수: ${chunkSegments.length}개
- 시간 범위: ${_formatTimeToHMS(chunkSegments.first.startSec)} ~ ${_formatTimeToHMS(chunkSegments.last.endSec)}

**분석 요청사항:**
1. 이 청크의 주요 주제와 핵심 내용
2. 청크 내 논리적 구조 (시작, 전개, 마무리)
3. 다른 청크와의 연결성 (이전/다음 청크와의 관계)
4. 중요한 키워드나 개념

**반드시 JSON 형식으로 반환:**
{
  "chunk_index": ${chunkIndex},
  "main_topic": "이 청크의 주요 주제",
  "key_points": ["핵심 포인트1", "핵심 포인트2", "핵심 포인트3"],
  "structure": {
    "start": "시작 부분의 특징",
    "development": "전개 부분의 특징", 
    "end": "마무리 부분의 특징"
  },
  "connection": {
    "previous": "이전 청크와의 연결점",
    "next": "다음 청크와의 연결점"
  },
  "important_segments": [1, 5, 12, 23]
}

청크 세그먼트:
${jsonEncode(formatted)}
''';

    // chatProxy 호출로 변경
    final chatProxyUrl = 'https://chatproxy-v4kacndtqq-uc.a.run.app';
    final idToken = await _authService.getIdToken();
    
    if (idToken == null) {
      throw StateError('인증 토큰을 가져올 수 없습니다. 로그인 상태를 확인해주세요.');
    }
    
    final body = jsonEncode({
      'messages': [
        {'role': 'system', 'content': 'You are an expert at analyzing video content structure and identifying key segments.'},
        {'role': 'user', 'content': overviewPrompt},
      ],
    });

    final response = await _getHttpClient().post(
      Uri.parse(chatProxyUrl),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw StateError('청크 개요 파악 실패: ${response.statusCode}');
    }

    final responseData = jsonDecode(response.body);
    final content = responseData['content'] as String;
    
    try {
      // ```json 코드 블록 제거
      final cleanContent = _removeJsonCodeBlock(content);
      return jsonDecode(cleanContent) as Map<String, dynamic>;
    } catch (e) {
      print('청크 개요 JSON 파싱 실패: $e');
      return {
        'chunk_index': chunkIndex,
        'main_topic': '청크 ${chunkIndex}',
        'key_points': ['내용 분석 실패'],
        'structure': {'start': '', 'development': '', 'end': ''},
        'connection': {'previous': '', 'next': ''},
        'important_segments': [],
      };
    }
  }

  Future<String> _integrateChunkOverviews(List<Map<String, dynamic>> chunkOverviews, String apiKey, Uri uri) async {
    // 취소 상태 직접 확인
    if (_isCancelled || appState.isOperationCancelled) {
      if (kDebugMode) print('✅ AIService: _integrateChunkOverviews에서 작업 취소됨');
      throw CancellationException('작업이 취소되었습니다.');
    }
    
    final integrationPrompt = '''
다음은 영상의 각 청크별 분석 결과입니다. 
이를 바탕으로 전체 영상의 구조와 주제를 통합 분석해주세요.

**청크 분석 결과:**
${chunkOverviews.map((overview) => '''
청크 ${overview['chunk_index']}:
- 주제: ${overview['main_topic']}
- 핵심 포인트: ${(overview['key_points'] as List).join(', ')}
- 연결점: 이전(${overview['connection']['previous']}) / 다음(${overview['connection']['next']})
''').join('\n')}

**통합 분석 요청사항:**
1. 전체 영상의 주요 주제와 목적
2. 전체 구조 (도입부, 전개부, 결론부)
3. 주제별 그룹화 (5개 그룹으로 나누기)
4. 각 주제 그룹의 핵심 내용과 세그먼트 범위

**반드시 JSON 형식으로 반환:**
{
  "main_topic": "전체 영상의 주요 주제",
  "purpose": "영상의 목적",
  "overall_structure": {
    "introduction": "도입부 특징",
    "development": "전개부 특징",
    "conclusion": "결론부 특징"
  },
  "structure": [
    {
      "theme": "주제1",
      "description": "이 주제의 핵심 내용",
      "start_segment_id": 1,
      "end_segment_id": 50
    }
  ]
}
''';

    // chatProxy 호출로 변경
    final chatProxyUrl = 'https://chatproxy-v4kacndtqq-uc.a.run.app';
    final idToken = await _authService.getIdToken();
    
    if (idToken == null) {
      throw StateError('인증 토큰을 가져올 수 없습니다. 로그인 상태를 확인해주세요.');
    }
    
    final body = jsonEncode({
      'messages': [
        {'role': 'system', 'content': 'You are an expert at integrating and synthesizing information from multiple sources.'},
        {'role': 'user', 'content': integrationPrompt},
      ],
    });

    final response = await _getHttpClient().post(
      Uri.parse(chatProxyUrl),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw StateError('청크 통합 실패: ${response.statusCode}');
    }

    final responseData = jsonDecode(response.body);
    final content = responseData['content'] as String;
    
    try {
      // ```json 코드 블록 제거
      final cleanContent = _removeJsonCodeBlock(content);
      final result = jsonDecode(cleanContent) as Map<String, dynamic>;
      return jsonEncode(result);
    } catch (e) {
      print('통합 분석 JSON 파싱 실패: $e');
      return content; // 원본 텍스트 반환
    }
  }

  Future<List<ThemeGroup>> _groupSegmentsByTheme(List<WhisperSegment> segments, String overallStructure) async {
    // 취소 상태 직접 확인
    if (_isCancelled || appState.isOperationCancelled) {
      if (kDebugMode) print('✅ AIService: _groupSegmentsByTheme에서 작업 취소됨');
      throw CancellationException('작업이 취소되었습니다.');
    }
    
    if (segments.isEmpty) {
      print('세그먼트가 비어있어 그룹화를 건너뜁니다.');
      return [];
    }
    
    try {
      // JSON 파싱 시도
      final overview = jsonDecode(overallStructure) as Map<String, dynamic>;
      final structure = overview['structure'] as List<dynamic>;
      List<ThemeGroup> groups = [];

      // 구조 정보로 그룹 생성 (ID 대신 인덱스 사용)
      for (final group in structure) {
        final startIndex = (group['start_segment_id'] as int) - 1; // 1-based를 0-based로 변환
        final endIndex = (group['end_segment_id'] as int); // 1-based
        final theme = group['theme'] as String;

        // 인덱스 범위 확인 및 조정
        final safeStartIndex = startIndex.clamp(0, segments.length - 1);
        final safeEndIndex = endIndex.clamp(0, segments.length);
        
        if (safeStartIndex < safeEndIndex && safeStartIndex < segments.length) {
          final groupSegments = segments.sublist(safeStartIndex, safeEndIndex);
          
          groups.add(ThemeGroup(
            theme: theme,
            segments: groupSegments,
          ));
          
          print('그룹 생성: $theme (${groupSegments.length}개 세그먼트) - 인덱스 ${safeStartIndex}~${safeEndIndex-1}');
        } else {
          print('⚠️ 그룹 생성 실패: $theme - 인덱스 범위 오류 (${safeStartIndex}~${safeEndIndex-1})');
        }
      }

      return groups;
    } catch (e) {
      print('주제별 그룹화 실패: $e');
      // 실패 시 기본 그룹화 (5개 그룹으로 균등 분할)
      return _createDefaultGroups(segments);
    }
  }

  // 기본 그룹화 (실패 시 사용)
  List<ThemeGroup> _createDefaultGroups(List<WhisperSegment> segments) {
    List<ThemeGroup> groups = [];
    final groupSize = (segments.length / 5).ceil();
    
    for (int i = 0; i < 5; i++) {
      final startIndex = i * groupSize;
      final endIndex = ((i + 1) * groupSize).clamp(0, segments.length);
      
      if (startIndex < segments.length) {
        final groupSegments = segments.sublist(startIndex, endIndex);
        groups.add(ThemeGroup(
          theme: '주제 ${i + 1}',
          segments: groupSegments,
        ));
      }
    }
    
    return groups;
  }

  // 시간을 HH:MM:SS 형식으로 포맷
  String _formatTimeToHMS(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).floor();
    
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  Future<List<int>> _summarizeThemeGroup(ThemeGroup group, String apiKey, Uri uri) async {
    try {
      // 주제별 핵심 세그먼트 선택 (시간 기반)
      List<int> selectedIds = [];
      
      if (group.segments.length <= 3) {
        // 3개 이하면 모두 선택
        selectedIds = group.segments.map((s) => s.id).toList();
      } else {
        // 3개 초과면 시간 간격으로 균등 선택
        final interval = group.segments.length / 3;
        for (int i = 0; i < 3; i++) {
          final index = (i * interval).round();
          if (index < group.segments.length) {
            selectedIds.add(group.segments[index].id);
          }
        }
      }
      
      print('주제 "${group.theme}"에서 ${selectedIds.length}개 세그먼트 선택됨: $selectedIds');
      return selectedIds;
    } catch (e) {
      print('주제별 요약 실패: $e');
      return [];
    }
  }

  Future<String> _generateFinalSummary(List<int> selectedIds, String apiKey, Uri uri) async {
    try {
      if (selectedIds.isEmpty) {
        return '선택된 세그먼트가 없습니다.';
      }
      
      // 선택된 세그먼트들의 텍스트를 결합
      final selectedSegments = appState.segments.where((s) => selectedIds.contains(s.id)).toList();
      final combinedText = selectedSegments.map((s) => s.text).join(' ');
      
      // 간단한 요약 생성 (실제로는 AI API 호출)
      return '선택된 ${selectedSegments.length}개 세그먼트의 핵심 내용을 요약한 결과입니다.';
    } catch (e) {
      print('최종 요약 생성 실패: $e');
      return '요약 생성 중 오류가 발생했습니다.';
    }
  }

  // 그룹 크기 검증 및 수정
  Future<List<Map<String, dynamic>>> _validateAndFixGroupSizes(
    List<dynamic> structure, 
    List<WhisperSegment> segments, 
    double totalDuration
  ) async {
    List<Map<String, dynamic>> result = [];
    final maxLastGroupRatio = 0.4; // 마지막 그룹은 전체의 40% 이하
    
    // 1. 기본 검증 및 수정
    for (int i = 0; i < structure.length; i++) {
      final group = structure[i];
      int startId = group['start_segment_id'] as int;
      int endId = group['end_segment_id'] as int;
      
      // 세그먼트 ID 범위 검증 및 보정
      startId = math.max(1, math.min(startId, segments.length));
      endId = math.max(startId, math.min(endId, segments.length));
      
      print('그룹 ${i + 1}: 원본 범위 (${group['start_segment_id']}-${group['end_segment_id']}) → 보정 범위 ($startId-$endId)');
      
      result.add({
        'start_segment_id': startId,
        'end_segment_id': endId,
        'theme': group['theme'],
        'description': group['description'],
      });
    }
    
    // 2. 마지막 그룹 크기 검증
    if (result.isNotEmpty) {
      final lastGroup = result.last;
      final lastGroupSize = lastGroup['end_segment_id'] - lastGroup['start_segment_id'] + 1;
      final totalSegments = segments.length;
      final lastGroupRatio = lastGroupSize / totalSegments;
      
      print('마지막 그룹 크기: $lastGroupSize/$totalSegments (${(lastGroupRatio * 100).toStringAsFixed(1)}%)');
      
      if (lastGroupRatio > maxLastGroupRatio) {
        print('마지막 그룹이 너무 큽니다. 재분할을 시작합니다.');
        result = await _redistributeGroups(result, segments, totalDuration);
      }
    }
    
    return result;
  }

  List<WhisperSegment> _mergeDetectedSilences(
    List<WhisperSegment> segments,
    List<SilenceSegment> detectedSilences,
  ) {
    if (detectedSilences.isEmpty) {
      return segments;
    }

    final List<SilenceSegment> normalizedSilences = [];
    for (final silence in detectedSilences) {
      final double normalizedStart = _floorToCentisecond(silence.startSec);
      final double normalizedEnd = _ceilToCentisecond(silence.endSec);
      if (normalizedEnd - normalizedStart <= _kGapTolerance) {
        continue;
      }
      normalizedSilences.add(SilenceSegment(
        startSec: normalizedStart,
        endSec: normalizedEnd,
        duration: normalizedEnd - normalizedStart,
      ));
    }

    if (normalizedSilences.isEmpty) {
      return segments;
    }

    final List<List<WordSegment>> wordsPerSegment = [
      for (final segment in segments) List<WordSegment>.from(segment.words)
    ];

    final List<List<SilenceSegment>> silencesPerSegment = [
      for (int i = 0; i < segments.length; i++) <SilenceSegment>[],
    ];

    final List<_WordPointer> pointers = [];
    final Map<_WordPointer, int> pointerPositions = {};
    for (int segIdx = 0; segIdx < segments.length; segIdx++) {
      final words = wordsPerSegment[segIdx];
      for (int wordIdx = 0; wordIdx < words.length; wordIdx++) {
        final pointer = _WordPointer(segIdx, wordIdx);
        pointerPositions[pointer] = pointers.length;
        pointers.add(pointer);
      }
    }

    _WordPointer? findPreviousWord(double time) {
      _WordPointer? candidate;
      for (final pointer in pointers) {
        final word = wordsPerSegment[pointer.segmentIndex][pointer.wordIndex];
        if (word.endSec <= time + _kGapTolerance) {
          if (candidate == null) {
            candidate = pointer;
            continue;
          }
          final currentCandidate =
              wordsPerSegment[candidate.segmentIndex][candidate.wordIndex];
          if (word.endSec > currentCandidate.endSec) {
            candidate = pointer;
          }
        }
      }
      return candidate;
    }

    _WordPointer? findNextWord(double time) {
      _WordPointer? candidate;
      for (final pointer in pointers) {
        final word = wordsPerSegment[pointer.segmentIndex][pointer.wordIndex];
        if (word.startSec >= time - _kGapTolerance) {
          if (candidate == null) {
            candidate = pointer;
            continue;
          }
          final currentCandidate =
              wordsPerSegment[candidate.segmentIndex][candidate.wordIndex];
          if (word.startSec < currentCandidate.startSec) {
            candidate = pointer;
          }
        }
      }
      return candidate;
    }

    for (final silence in normalizedSilences) {
      double finalSilenceStart = _roundToCentisecond(silence.startSec);
      double finalSilenceEnd = _roundToCentisecond(silence.endSec);

      final prevRef = findPreviousWord(finalSilenceStart);
      final int prevIndex = prevRef != null ? pointerPositions[prevRef]! : -1;
      _WordPointer? nextRef = (prevIndex + 1 < pointers.length) ? pointers[prevIndex + 1] : null;
      nextRef ??= findNextWord(finalSilenceEnd);

      if (prevRef != null) {
        final prevWord = wordsPerSegment[prevRef.segmentIndex][prevRef.wordIndex];
        
        double desiredEnd = _roundToCentisecond(finalSilenceStart);

        final double delta = (desiredEnd - prevWord.endSec).abs();
        if (delta <= _kFfmpegBoundaryRespectTolerance) {
          desiredEnd = prevWord.endSec;
          finalSilenceStart = desiredEnd;

          if (kDebugMode) {
            print('   ✓ FFmpeg 무음: 이전 단어 "${prevWord.word}" 종료 유지 ${prevWord.endSec.toStringAsFixed(2)}s (차이 ${delta.toStringAsFixed(3)}s)');
          }
        } else {
          final double minAllowedEnd = prevWord.startSec + _kMinimumWordDuration;
          if (desiredEnd < minAllowedEnd) {
            desiredEnd = _roundToCentisecond(minAllowedEnd);
          }
          if (desiredEnd > finalSilenceEnd - _kGapTolerance) {
            desiredEnd = _roundToCentisecond(math.max(finalSilenceStart, finalSilenceEnd - _kGapTolerance));
          }
          if (desiredEnd > prevWord.endSec + _kGapTolerance) {
            desiredEnd = _roundToCentisecond(desiredEnd);
          }

          final updatedPrev = WordSegment(
            index: prevWord.index,
            word: prevWord.word,
            startSec: prevWord.startSec,
            endSec: desiredEnd,
            score: prevWord.score,
          );
          wordsPerSegment[prevRef.segmentIndex][prevRef.wordIndex] = updatedPrev;
          finalSilenceStart = desiredEnd;

          if (kDebugMode) {
            print('   ↔ FFmpeg 무음 적용: 이전 단어 "${prevWord.word}" 종료 ${prevWord.endSec.toStringAsFixed(2)}s → ${desiredEnd.toStringAsFixed(2)}s');
          }
        }
      } else {
        finalSilenceStart = _roundToCentisecond(finalSilenceStart);
      }

      if (nextRef != null) {
        final nextWord = wordsPerSegment[nextRef.segmentIndex][nextRef.wordIndex];
        
        double desiredStart = _roundToCentisecond(finalSilenceEnd);

        final double delta = (desiredStart - nextWord.startSec).abs();
        if (delta <= _kFfmpegBoundaryRespectTolerance) {
          desiredStart = nextWord.startSec;
          finalSilenceEnd = desiredStart;

          if (kDebugMode) {
            print('   ✓ FFmpeg 무음: 다음 단어 "${nextWord.word}" 시작 유지 ${nextWord.startSec.toStringAsFixed(2)}s (차이 ${delta.toStringAsFixed(3)}s)');
          }
        } else {
          final double maxAllowedStart = nextWord.endSec - _kMinimumWordDuration;
          if (desiredStart < finalSilenceStart) {
            desiredStart = finalSilenceStart;
          }
          if (desiredStart > maxAllowedStart) {
            desiredStart = _roundToCentisecond(maxAllowedStart);
          }
          if (nextWord.endSec - desiredStart < _kMinimumWordDuration) {
            desiredStart = _roundToCentisecond(nextWord.endSec - _kMinimumWordDuration);
          }
          if (desiredStart < finalSilenceStart) {
            desiredStart = finalSilenceStart;
          }

          final updatedNext = WordSegment(
            index: nextWord.index,
            word: nextWord.word,
            startSec: desiredStart,
            endSec: nextWord.endSec,
            score: nextWord.score,
          );
          wordsPerSegment[nextRef.segmentIndex][nextRef.wordIndex] = updatedNext;
          finalSilenceEnd = desiredStart;

          if (kDebugMode) {
            print('   ↔ FFmpeg 무음 적용: 다음 단어 "${nextWord.word}" 시작 ${nextWord.startSec.toStringAsFixed(2)}s → ${desiredStart.toStringAsFixed(2)}s');
          }
        }
      } else {
        finalSilenceEnd = _roundToCentisecond(finalSilenceEnd);
      }

      final double finalSilenceDuration = finalSilenceEnd - finalSilenceStart;
      if (finalSilenceDuration <= _kGapTolerance) {
        continue;
      }

      if (finalSilenceDuration < _kMinimumFfmpegSilenceDuration) {
        if (prevRef != null) {
          final prevWord = wordsPerSegment[prevRef.segmentIndex][prevRef.wordIndex];
          final updatedPrev = WordSegment(
            index: prevWord.index,
            word: prevWord.word,
            startSec: prevWord.startSec,
            endSec: finalSilenceEnd,
            score: prevWord.score,
          );
          wordsPerSegment[prevRef.segmentIndex][prevRef.wordIndex] = updatedPrev;
        }

        if (nextRef != null) {
          final nextWord = wordsPerSegment[nextRef.segmentIndex][nextRef.wordIndex];
          double mergedStart = _roundToCentisecond(finalSilenceEnd);
          if (mergedStart > nextWord.endSec - _kMinimumWordDuration) {
            mergedStart = _roundToCentisecond(nextWord.endSec - _kMinimumWordDuration);
          }
          if (mergedStart < nextWord.startSec) {
            mergedStart = nextWord.startSec;
          }
          final alignedNext = WordSegment(
            index: nextWord.index,
            word: nextWord.word,
            startSec: mergedStart,
            endSec: nextWord.endSec,
            score: nextWord.score,
          );
          wordsPerSegment[nextRef.segmentIndex][nextRef.wordIndex] = alignedNext;
        }

        if (kDebugMode) {
          print('   ↔ FFmpeg 무음 제거(짧음): ${finalSilenceDuration.toStringAsFixed(2)}s');
        }

        continue;
      }

      int targetSegmentIndex;
      if (prevRef != null) {
        targetSegmentIndex = prevRef.segmentIndex;
      } else if (nextRef != null) {
        targetSegmentIndex = nextRef.segmentIndex;
      } else {
        targetSegmentIndex = segments.indexWhere(
          (segment) => finalSilenceStart <= segment.endSec + _kGapTolerance,
        );
        if (targetSegmentIndex == -1) {
          targetSegmentIndex = segments.length - 1;
        }
      }
      _addOrMergeSilence(silencesPerSegment[targetSegmentIndex], finalSilenceStart, finalSilenceEnd);
    }

    final List<WhisperSegment> result = [];
    for (int segIdx = 0; segIdx < segments.length; segIdx++) {
      final words = wordsPerSegment[segIdx];
      final silences = silencesPerSegment[segIdx];
      
      // silences를 WordSegment로 변환하여 words에 통합
      final List<WordSegment> combinedWords = List<WordSegment>.from(words);
      for (final silence in silences) {
        combinedWords.add(WordSegment(
          index: combinedWords.length, // 임시 인덱스
          word: '',
          startSec: silence.startSec,
          endSec: silence.endSec,
          score: 1.0,
          isSilence: true,
        ));
      }
      
      // 시간순 정렬
      combinedWords.sort((a, b) => a.startSec.compareTo(b.startSec));
      
      // 인덱스 재조정
      for (int i = 0; i < combinedWords.length; i++) {
        combinedWords[i] = combinedWords[i].copyWith(index: i);
      }

      double segmentStart = segments[segIdx].startSec;
      double segmentEnd = segments[segIdx].endSec;
      if (combinedWords.isNotEmpty) {
        segmentStart = combinedWords.first.startSec;
        segmentEnd = combinedWords.last.endSec;
      }

      result.add(segments[segIdx].copyWith(
        words: combinedWords,
        startSec: segmentStart,
        endSec: segmentEnd,
      ));
    }

    return result;
  }

  // 그룹 재분배
  Future<List<Map<String, dynamic>>> _redistributeGroups(
    List<Map<String, dynamic>> groups, 
    List<WhisperSegment> segments, 
    double totalDuration
  ) async {
    if (groups.length < 2) return groups;
    
    List<Map<String, dynamic>> result = List.from(groups);
    final lastGroup = result.last;
    final secondLastGroup = result[result.length - 2];
    
    // 마지막 그룹을 두 그룹으로 분할
    final lastGroupStart = lastGroup['start_segment_id'] as int;
    final lastGroupEnd = lastGroup['end_segment_id'] as int;
    final midPoint = (lastGroupStart + lastGroupEnd) ~/ 2;
    
    // 마지막 그룹을 두 개로 분할
    result[result.length - 2] = {
      'start_segment_id': secondLastGroup['start_segment_id'],
      'end_segment_id': midPoint - 1,
      'theme': secondLastGroup['theme'],
      'description': secondLastGroup['description'],
    };
    
    result[result.length - 1] = {
      'start_segment_id': midPoint,
      'end_segment_id': lastGroupEnd,
      'theme': lastGroup['theme'],
      'description': lastGroup['description'],
    };
    
    print('마지막 그룹 재분할 완료: ${lastGroupStart}-${lastGroupEnd} → ${lastGroupStart}-${midPoint-1}, ${midPoint}-${lastGroupEnd}');
    
    return result;
  }

  // 의미 기반 경계 조정
  Future<List<Map<String, dynamic>>> _refineGroupBoundaries(
    List<Map<String, dynamic>> groups, 
    List<WhisperSegment> segments
  ) async {
    List<Map<String, dynamic>> result = List.from(groups);
    
    for (int i = 0; i < result.length; i++) {
      final group = result[i];
      final startId = group['start_segment_id'] as int;
      final endId = group['end_segment_id'] as int;
      
      // 시작 경계 조정: 문장이 완성되는 지점 찾기
      int adjustedStartId = startId;
      if (startId > 1) {
        final startSegment = segments.firstWhere((s) => s.id == startId);
        if (!_isCompleteSentence(startSegment.text)) {
          // 이전 세그먼트로 경계 이동
          adjustedStartId = math.max(1, startId - 1);
          print('그룹 ${i + 1} 시작 경계 조정: $startId → $adjustedStartId');
        }
      }
      
      // 끝 경계 조정: 문장이 완성되는 지점 찾기
      int adjustedEndId = endId;
      if (endId < segments.length) {
        final endSegment = segments.firstWhere((s) => s.id == endId);
        if (!_isCompleteSentence(endSegment.text)) {
          // 다음 세그먼트로 경계 이동
          adjustedEndId = math.min(segments.length, endId + 1);
          print('그룹 ${i + 1} 끝 경계 조정: $endId → $adjustedEndId');
        }
      }
      
      result[i] = {
        'start_segment_id': adjustedStartId,
        'end_segment_id': adjustedEndId,
        'theme': group['theme'],
        'description': group['description'],
      };
    }
    
    return result;
  }

  // 문장 완성 여부 확인
  bool _isCompleteSentence(String text) {
    return text.endsWith('니다') || text.endsWith('요') || 
           text.endsWith('.') || text.endsWith('!') || text.endsWith('?') ||
           text.endsWith('다') || text.endsWith('어') || text.endsWith('아');
  }




  
  // AI 기반 챕터 생성 핵심 로직
  Future<List<ThemeGroup>> _generateChaptersWithAI() async {
    try {
      if (kDebugMode) print('🤖 AIService: AI 챕터 생성 핵심 로직 시작');
      
      
      // 세그먼트 데이터 준비
      final segments = appState.segments;
      final formatted = segments.map((s) => {
        'id': s.id,
        'start': s.startSec,
        'end': s.endSec,
        'text': s.text,
      }).toList();
      
      final totalDuration = segments.last.endSec - segments.first.startSec;
      final totalMinutes = (totalDuration / 60).round();
      
      // AI 프롬프트 생성
      final prompt = '''
당신은 영상 구조 분석 전문가입니다. 주어진 ${segments.length}개 세그먼트 (총 ${totalMinutes}분)를 분석하여 의미있는 챕터를 생성해주세요.

**분석 요청사항:**
1. **주제별 그룹화**: 내용의 흐름과 주제 변화를 고려한 자연스러운 구분
2. **의미있는 제목**: 각 챕터의 핵심 내용을 담은 구체적이고 차별화된 제목
3. **시간 배분**: 각 챕터가 적절한 시간을 가지도록 균형있게 분할
4. **논리적 흐름**: 챕터 간의 연결성과 전체적인 스토리 구조

**세그먼트 데이터:**
${jsonEncode(formatted)}

**반드시 JSON 형식으로 반환:**
{
  "chapters": [
    {
      "theme": "구체적이고 차별화된 제목 (15자 내외)",
      "description": "이 챕터의 주요 내용과 의미 (30-50자)",
      "start_segment_id": 시작ID(숫자),
      "end_segment_id": 끝ID(숫자),
      "key_points": ["핵심 포인트1", "핵심 포인트2", "핵심 포인트3"]
    }
  ]
}

**제목 생성 기준:**
- "챕터1", "주제1" 같은 일반적 표현 금지
- 해당 챕터의 핵심 키워드나 행동을 포함
- 예: "PC방 창업 소개", "시장 분석", "창업 전략" 등
''';
      
      // chatProxy 호출로 변경
      final chatProxyUrl = 'https://chatproxy-v4kacndtqq-uc.a.run.app';
      final idToken = await _authService.getIdToken();
      
      if (idToken == null) {
        throw StateError('인증 토큰을 가져올 수 없습니다. 로그인 상태를 확인해주세요.');
      }
      
      final body = jsonEncode({
        'messages': [
          {'role': 'system', 'content': 'You are an expert at analyzing video structure and creating meaningful chapters.'},
          {'role': 'user', 'content': prompt},
        ],
      });
      
      final response = await _getHttpClient().post(
        Uri.parse(chatProxyUrl),
        headers: {
          'Authorization': 'Bearer $idToken',
          'Content-Type': 'application/json',
        },
        body: body,
      );
      
      if (response.statusCode != 200) {
        throw StateError('AI API 요청 실패: ${response.statusCode}');
      }
      
      final responseData = jsonDecode(response.body);
      final content = responseData['content'] as String;
      final result = jsonDecode(content) as Map<String, dynamic>;
      final chapters = result['chapters'] as List<dynamic>;
      
      // ThemeGroup 리스트로 변환
      final themeGroups = chapters.map((chapter) {
        final startId = chapter['start_segment_id'] as int;
        final endId = chapter['end_segment_id'] as int;
        
        final chapterSegments = segments.where((s) => 
          s.id >= startId && s.id <= endId
        ).toList();
        
        return ThemeGroup(
          theme: chapter['theme'],
          segments: chapterSegments,
          summary: chapter['description'],
        );
      }).toList();
      
      if (kDebugMode) print('✅ AIService: AI 챕터 생성 완료 - ${themeGroups.length}개 챕터');
      return themeGroups;
      
    } catch (e) {
      if (kDebugMode) print('❌ AIService: AI 챕터 생성 중 오류: $e');
      return [];
    }
  }
  
  // 영상 개요 분석 (AI API 사용)
  Future<Map<String, dynamic>> getVideoOverview(List<WhisperSegment> segments) async {
    final formatted = segments.map((s) => {
      'id': s.id,
      'start': s.startSec,
      'end': s.endSec,
      'text': s.text
    }).toList();

    final totalDuration = segments.last.endSec;
    final totalMinutes = (totalDuration / 60).round();
    
    final targetGroupCount = _calculateOptimalGroupCount(totalDuration);
    final avgGroupDuration = totalDuration / targetGroupCount;
    
    final overviewPrompt = '''
당신은 영상 구조 분석 전문가입니다. 주어진 ${segments.length}개 세그먼트 (총 ${totalMinutes}분)를 정확히 ${targetGroupCount}개 그룹으로 분할하세요.

**🚨 절대 준수 사항 🚨**
1. **반드시 ${targetGroupCount}개 그룹**: 더 많지도 적지도 않게
2. **각 그룹 목표 시간**: ${avgGroupDuration.round()}초 내외 (±30초)
3. **마지막 그룹 제한**: 전체의 40% 이하 (${(totalDuration * 0.4).round()}초 이하)
4. **첫 번째 그룹**: 반드시 1번 세그먼트부터 시작
5. **마지막 그룹**: 반드시 ${segments.length}번 세그먼트로 끝

**시간 배분 목표 (${totalMinutes}분 영상):**
${List.generate(targetGroupCount, (i) {
  final start = (i * avgGroupDuration).round();
  final end = ((i + 1) * avgGroupDuration).round();
  final startMin = start ~/ 60;
  final startSec = start % 60;
  final endMin = end ~/ 60;
  final endSec = end % 60;
  return '- 구간${i + 1}: ${startMin}:${startSec.toString().padLeft(2, '0')} - ${endMin}:${endSec.toString().padLeft(2, '0')} (약 ${avgGroupDuration.round()}초)';
}).join('\n')}

**분할 전략:**
1. 각 구간의 세그먼트 ID 범위를 시간 기준으로 1차 계산
2. 주제 변화 지점과 문장 완결성을 분석하여 경계 조정
3. 완전한 문장으로 끝나고 시작하도록 세밀하게 조정
4. 모든 구간이 의미적으로 완결된 주제를 담도록 보장

**경계 조정 기준:**
- 문장이 완전히 끝나는 지점에서 구간 종료 ("다", "요", "습니다" 등)
- 새로운 주제가 명확히 시작되는 지점에서 구간 시작
- 화자 변경, 활동 전환, 설명 단락 등을 고려한 자연스러운 구분점

**JSON 반환 (정확히 ${targetGroupCount}개):**
{
  "main_topic": "영상의 주요 주제",
  "purpose": "영상의 목적",
  "structure": [
    {
      "theme": "구체적이고 차별화된 제목 (10자 내외)",
      "description": "이 구간만의 고유한 내용과 의미 (20-30자)",
      "start_segment_id": 시작ID(숫자),
      "end_segment_id": 끝ID(숫자)
    }
  ]
}
**제목 생성 기준:**
- 각 구간마다 서로 다른 고유한 제목
- "구간1", "주제1" 같은 일반적 표현 금지
- 해당 구간의 핵심 키워드나 행동을 포함
- 예: "감정 읽기 연습", "신호등 활동법", "이야기 만들기" 등

세그먼트 데이터:
${jsonEncode(formatted)}
''';

    print('=== OVERVIEW PROMPT ===');
    print(overviewPrompt);

    // chatProxy 호출로 변경
    final chatProxyUrl = 'https://chatproxy-v4kacndtqq-uc.a.run.app';
    final idToken = await _authService.getIdToken();
    
    if (idToken == null) {
      throw StateError('인증 토큰을 가져올 수 없습니다. 로그인 상태를 확인해주세요.');
    }
    
    final body = jsonEncode({
      'messages': [
        {'role': 'system', 'content': 'You are an expert at analyzing video structure and content flow.'},
        {'role': 'user', 'content': overviewPrompt},
      ],
    });

    print('=== OVERVIEW API REQUEST ===');
    print('Request Body: $body');

    final response = await _getHttpClient().post(
      Uri.parse(chatProxyUrl),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    print('=== OVERVIEW API RESPONSE ===');
    print('Status Code: ${response.statusCode}');
    print('Response Body: ${response.body}');

    if (response.statusCode != 200) {
      throw StateError('개요 파악 실패: ${response.statusCode}');
    }

    final responseData = jsonDecode(response.body);
    final content = responseData['content'] as String;
    print('=== PARSED OVERVIEW CONTENT ===');
    print(content);

    // JSON 파싱 시도
    try {
      // ```json 코드 블록 제거
      final cleanContent = _removeJsonCodeBlock(content);
      return jsonDecode(cleanContent) as Map<String, dynamic>;
    } catch (e) {
      print('JSON 파싱 실패, 텍스트에서 구조 추출 시도: $e');
      return _parseOverviewFromText(content, segments);
    }
  }

  // 백업 파싱 로직
  Map<String, dynamic> _parseOverviewFromText(String text, List<WhisperSegment> segments) {
    print('=== 백업 파싱 로직 시작: 개선된 시간 기반 분할 ===');
    
    if (segments.isEmpty) {
      return {
        'main_topic': '빈 영상',
        'purpose': '내용 없음',
        'structure': [],
      };
    }

    // 1. 전체 영상 길이 계산
    final totalDuration = segments.last.endSec;
    print('전체 영상 길이: ${totalDuration.toStringAsFixed(2)}초');
    
    // 2. 개선된 그룹화 전략
    List<Map<String, dynamic>> structure = _createImprovedTimeBasedGroups(segments, totalDuration);
    
    print('생성된 구조: ${structure.length}개 그룹');
    for (int i = 0; i < structure.length; i++) {
      final group = structure[i];
      print('그룹 ${i + 1}: ${group['theme']} (${group['start_segment_id']} - ${group['end_segment_id']})');
    }

    return {
      'main_topic': '영상 요약',
      'purpose': '영상 내용의 핵심 요약',
      'structure': structure,
    };
  }

  // 개선된 시간 기반 그룹 생성
  List<Map<String, dynamic>> _createImprovedTimeBasedGroups(List<WhisperSegment> segments, double totalDuration) {
    // 1. 영상 길이에 따른 적응적 그룹 수 결정
    int targetGroupCount = _calculateOptimalGroupCount(totalDuration);
    print('목표 그룹 수: $targetGroupCount (영상 길이: ${totalDuration.toStringAsFixed(2)}초)');
    
    // 2. 시간 기반 균등 분할 + 의미 단위 조정
    List<Map<String, dynamic>> groups = [];
    
    // 목표 그룹 지속시간 계산
    final targetGroupDuration = totalDuration / targetGroupCount;
    print('목표 그룹당 시간: ${targetGroupDuration.toStringAsFixed(2)}초');
    
    int currentSegmentIndex = 0;
    
    for (int groupIndex = 0; groupIndex < targetGroupCount; groupIndex++) {
      final isLastGroup = (groupIndex == targetGroupCount - 1);
      
      // 목표 끝 시간 계산
      final targetEndTime = (groupIndex + 1) * targetGroupDuration;
      
      int startId = currentSegmentIndex + 1;
      int endId;
      
      if (isLastGroup) {
        // 마지막 그룹은 반드시 끝까지
        endId = segments.length;
      } else {
        // 목표 시간에 가장 가까운 의미 있는 구분점 찾기
        endId = _findOptimalBreakPoint(segments, currentSegmentIndex, targetEndTime);
      }
      
      // 실제 시간 계산 (안전한 인덱스 접근)
      final safeStartIndex = math.max(0, math.min(currentSegmentIndex, segments.length - 1));
      final safeEndIndex = math.max(0, math.min(endId - 1, segments.length - 1));
      final actualStartTime = segments[safeStartIndex].startSec;
      final actualEndTime = segments[safeEndIndex].endSec;
      final actualDuration = actualEndTime - actualStartTime;
      
      groups.add({
        'theme': _generateThemeName(groupIndex + 1, actualStartTime, actualEndTime, actualDuration),
        'description': _generateThemeDescription(groupIndex + 1, actualDuration, targetGroupCount),
        'start_segment_id': startId,
        'end_segment_id': endId,
      });
      
      print('그룹 ${groupIndex + 1}: ${actualStartTime.toStringAsFixed(1)}s - ${actualEndTime.toStringAsFixed(1)}s (${actualDuration.toStringAsFixed(1)}s)');
      
      currentSegmentIndex = endId;
      
      // 모든 세그먼트를 처리했으면 종료
      if (currentSegmentIndex >= segments.length) {
        break;
      }
    }
    
    return groups;
  }

  // 최적 그룹 수 계산
  int _calculateOptimalGroupCount(double totalDuration) {
    // 영상 길이에 따른 적응적 그룹 수 (더 균등한 분할을 위해 조정)
    if (totalDuration <= 120) return 2;          // 2분 이하: 2개
    if (totalDuration <= 240) return 3;          // 4분 이하: 3개  
    if (totalDuration <= 360) return 4;          // 6분 이하: 4개
    if (totalDuration <= 480) return 5;          // 8분 이하: 5개
    if (totalDuration <= 600) return 6;          // 10분 이하: 6개
    if (totalDuration <= 900) return 7;          // 15분 이하: 7개
    if (totalDuration <= 1200) return 8;         // 20분 이하: 8개
    if (totalDuration <= 1800) return 9;         // 30분 이하: 9개
    if (totalDuration <= 3600) return 10;        // 60분 이하: 10개
    return ((totalDuration / 360).ceil()).clamp(10, 15); // 긴 영상: 6분당 1그룹, 최대 15개
  }

  // 최적 구분점 찾기
  int _findOptimalBreakPoint(List<WhisperSegment> segments, int startIndex, double targetTime) {
    // 목표 시간 근처에서 의미 있는 구분점 찾기
    
    // 1. 목표 시간에 가장 가까운 세그먼트 찾기
    int targetIndex = startIndex;
    double minTimeDiff = double.infinity;
    
    for (int i = startIndex; i < segments.length; i++) {
      final timeDiff = (segments[i].endSec - targetTime).abs();
      if (timeDiff < minTimeDiff) {
        minTimeDiff = timeDiff;
        targetIndex = i;
      } else {
        break; // 시간이 멀어지기 시작하면 중단
      }
    }
    
    // 2. 목표 지점 근처에서 의미적 구분점 찾기 (±10초 범위)
    final searchRange = 10.0; // 10초 범위
    final searchStart = targetTime - searchRange;
    final searchEnd = targetTime + searchRange;
    
    // 검색 범위 내 세그먼트들에서 구분점 패턴 찾기
    for (int i = startIndex; i < segments.length; i++) {
      final segment = segments[i];
      if (segment.endSec < searchStart) continue;
      if (segment.startSec > searchEnd) break;
      
      // 의미적 구분점 패턴 확인
      if (_isNaturalBreakPoint(segment.text)) {
        print('의미적 구분점 발견: ID ${segment.id}, 시간: ${segment.endSec}s, 텍스트: "${segment.text}"');
        return i + 1;
      }
    }
    
    // 3. 의미적 구분점이 없으면 목표 시간에 가장 가까운 지점 사용
    return targetIndex + 1;
  }

  // 자연스러운 구분점 판단
  bool _isNaturalBreakPoint(String text) {
    final cleanText = text.trim().toLowerCase();
    
    // 마무리 패턴
    final endingPatterns = [
      '그렇습니다', '이상입니다', '마무리', '정리하면', '요약하면',
      '결론적으로', '마지막으로', '끝으로', '이제', '다음으로',
      '그럼', '자', '그래서', '따라서', '그러면', '이제는',
      '계속해서', '이어서', '다음은', '다음에는'
    ];
    
    // 새로운 주제 시작 패턴
    final startingPatterns = [
      '이번에는', '다음은', '그리고', '또한', '한편', '그런데',
      '그 다음', '이제는', '계속해서', '이어서', '다음으로'
    ];
    
    // 문장 끝 패턴 (완결성)
    final completionPatterns = [
      '.', '!', '?', '습니다', '입니다', '어요', '아요', '에요',
      '죠', '네요', '거예요', '것 같아요', '것입니다'
    ];
    
    // 패턴 검사
    for (final pattern in endingPatterns) {
      if (cleanText.contains(pattern)) return true;
    }
    
    for (final pattern in startingPatterns) {
      if (cleanText.contains(pattern)) return true;
    }
    
    for (final pattern in completionPatterns) {
      if (cleanText.endsWith(pattern)) return true;
    }
    
    return false;
  }

  // 테마 이름 생성
  String _generateThemeName(int groupIndex, double startTime, double endTime, double duration) {
    final startMin = (startTime / 60).floor();
    final startSec = (startTime % 60).round();
    final endMin = (endTime / 60).floor();
    final endSec = (endTime % 60).round();
    
    return '구간 $groupIndex (${startMin}:${startSec.toString().padLeft(2, '0')} - ${endMin}:${endSec.toString().padLeft(2, '0')})';
  }

  // 테마 설명 생성
  String _generateThemeDescription(int groupIndex, double duration, int totalGroups) {
    final minutes = (duration / 60);
    if (minutes < 1) {
      return '${duration.round()}초 분량의 ${groupIndex}번째 주요 구간';
    } else {
      return '${minutes.toStringAsFixed(1)}분 분량의 ${groupIndex}번째 주요 구간';
    }
  }

  // FFmpeg 경로 찾기
  String _findFfmpegPath() {
    // 1. 앱 번들의 Resources 폴더 (배포/빌드 버전)
    final appResourcesPath = _getAppResourcesPath();
    final appFfmpegPath = '$appResourcesPath/ffmpeg';
    
    if (kDebugMode) print('🔍 앱 번들 Resources 경로: $appResourcesPath');
    
    if (File(appFfmpegPath).existsSync()) {
      if (kDebugMode) print('✅ 앱 번들 FFmpeg 발견: $appFfmpegPath');
      return appFfmpegPath;
    }
    
    // 2. 프로젝트 폴더의 FFmpeg (개발 중 - Hot Reload용)
    final projectFfmpegPath = '/Users/ihuijae/Desktop/Flutter_Workspace/bestcut_flutter/ffmpeg/macos/ffmpeg';
    if (File(projectFfmpegPath).existsSync()) {
      if (kDebugMode) print('✅ 프로젝트 FFmpeg 발견 (개발 모드): $projectFfmpegPath');
      return projectFfmpegPath;
    }
    
    // Resources 폴더 내용 확인 (디버깅용)
    if (kDebugMode) {
      try {
        final dir = Directory(appResourcesPath);
        if (dir.existsSync()) {
          final files = dir.listSync();
          print('📁 Resources 폴더 파일들:');
          for (final file in files) {
            print('   - ${file.path.split('/').last}');
          }
        }
      } catch (e) {
        print('❌ Resources 폴더 접근 오류: $e');
      }
    }
    
    // 3. FFmpeg를 찾을 수 없음
    if (kDebugMode) print('❌ FFmpeg를 찾을 수 없습니다.');
    throw Exception('FFmpeg를 찾을 수 없습니다. 앱 번들에 FFmpeg가 포함되어 있는지 확인하세요.');
  }
  
  // 앱 Resources 경로 가져오기
  String _getAppResourcesPath() {
    // 앱의 실행 파일 경로를 기준으로 Resources 경로 찾기
    final executablePath = Platform.resolvedExecutable;
    
    // 실행 파일 경로에서 MacOS를 Resources로 변경
    // 예: /path/to/app.app/Contents/MacOS/bestcut_flutter -> /path/to/app.app/Contents/Resources
    return executablePath.replaceAll('/MacOS/bestcut_flutter', '/Resources');
  }

  // Python으로 오디오 에너지 프로파일 생성 (100ms 간격)
  Future<List<AudioEnergyFrame>> _analyzeAudioEnergy(String audioPath, String ffmpegPath, Map<String, String> env) async {
    print('📊 Python 오디오 에너지 분석 실행 중...');
    
    final projectRoot = _resolveProjectRoot();
    final pythonExec = _findPythonExecutable(projectRoot);
    
    if (pythonExec == null) {
      print('⚠️ Python 실행 파일을 찾을 수 없어 에너지 분석을 건너뜁니다.');
      return [];
    }

    final scriptPath = '$projectRoot/tools/audio_pipeline/analyze_audio_energy.py';
    if (!File(scriptPath).existsSync()) {
      print('⚠️ 에너지 분석 스크립트를 찾을 수 없어 건너뜁니다: $scriptPath');
      return [];
    }

    final energyJsonPath = '$audioPath.energy.json';

    final result = await Process.run(
      pythonExec,
      [
        scriptPath,
        '--audio', audioPath,
        '--output-json', energyJsonPath,
        '--frame-length', '0.1',  // 100ms 프레임
        '--silence-threshold', '-40.0',
      ],
      environment: env,
    );

    if (result.exitCode != 0) {
      print('⚠️ 에너지 분석 실패 (${result.exitCode}): ${result.stderr}');
      return [];
    }

    if (kDebugMode) {
      print('Python 출력: ${result.stdout}');
    }

    // JSON 파일 읽기
    final energyFile = File(energyJsonPath);
    if (!energyFile.existsSync()) {
      print('⚠️ 에너지 프로파일 파일을 찾을 수 없습니다.');
      return [];
    }

    try {
      final data = jsonDecode(energyFile.readAsStringSync());
      final framesData = data['frames'] as List<dynamic>;
      
      final frames = framesData.map((item) {
        final map = item as Map<String, dynamic>;
        return AudioEnergyFrame(
          timeSec: (map['timeSec'] as num).toDouble(),
          rmsLevel: (map['rmsLevel'] as num).toDouble(),
        );
      }).toList();

      print('✅ 에너지 프레임 ${frames.length}개 생성 완료');
      if (frames.isNotEmpty) {
        print('  첫 프레임: ${frames.first}');
        print('  마지막 프레임: ${frames.last}');
      }
      
      return frames;
    } catch (e) {
      print('⚠️ 에너지 프로파일 JSON 파싱 실패: $e');
      return [];
    }
  }

  // FFmpeg silencedetect로 무음 구간 감지
  Future<List<SilenceSegment>> _detectSilence(String audioPath, String ffmpegPath, Map<String, String> env) async {
    print('🔇 FFmpeg silencedetect 실행 중...');
    
    final result = await Process.run(
      ffmpegPath,
      [
        '-i', audioPath,
        '-af', 'silencedetect=n=-30dB:d=0.3', // -30dB 이하, 0.3초 이상
        '-f', 'null',
        '-'
      ],
      environment: env,
      workingDirectory: _getAppResourcesPath(),
    );

    final List<SilenceSegment> silences = [];
    final output = result.stderr as String;

    // silence_start와 silence_end 파싱
    final startRegex = RegExp(r'silence_start: ([\d.]+)');
    final endRegex = RegExp(r'silence_end: ([\d.]+) \| silence_duration: ([\d.]+)');

    double? currentStart;
    
    for (final line in output.split('\n')) {
      final startMatch = startRegex.firstMatch(line);
      if (startMatch != null) {
        currentStart = double.parse(startMatch.group(1)!);
        continue;
      }

      final endMatch = endRegex.firstMatch(line);
      if (endMatch != null && currentStart != null) {
        final end = double.parse(endMatch.group(1)!);
        final rawDuration = double.parse(endMatch.group(2)!);

        final double adjustedStart = (currentStart + _kFfmpegSilenceMargin).clamp(0.0, double.infinity);
        final double adjustedEnd = math.max(adjustedStart, end - _kFfmpegSilenceMargin);
        final double adjustedDuration = adjustedEnd - adjustedStart;

        if (adjustedDuration > 0) {
          silences.add(SilenceSegment(
            startSec: adjustedStart,
            endSec: adjustedEnd,
            duration: adjustedDuration,
          ));
        } else if (kDebugMode) {
          print('⚠️ FFmpeg 무음 구간이 너무 짧아 스킵: start=${currentStart.toStringAsFixed(2)} end=${end.toStringAsFixed(2)} (raw ${rawDuration.toStringAsFixed(2)}s)');
        }

        currentStart = null;
      }
    }

    print('✅ 무음 구간 ${silences.length}개 감지 완료');
    return silences;
  }


  // 에너지 프로파일에서 실제 단어 시작 지점 찾기 (적극적 조정)
  double _findActualWordStart(
    double approximateStart, 
    List<AudioEnergyFrame> energyProfile,
    double? previousWordEnd,  // 이전 단어 끝 시간
  ) {
    // 보수적 탐색: 단어 시작 앞부분 확장 (앞부분 잘림 방지)
    const double searchBefore = 0.2;  // 앞으로 200ms (확장: 단어 시작이 늦게 잡히는 문제 해결)
    const double searchAfter = 0.2;   // 뒤로 200ms
    const double voiceThreshold = -40.0; // -40dB 이상은 음성

    // 이전 단어와 겹치지 않도록 최소 시작 시간 설정
    final minStart = previousWordEnd ?? 0.0;
    final searchStart = (approximateStart - searchBefore).clamp(minStart, double.infinity);
    final searchEnd = approximateStart + searchAfter;

    // 탐색 범위 내의 프레임들
    final relevantFrames = energyProfile.where((frame) =>
      frame.timeSec >= searchStart && frame.timeSec <= searchEnd
    ).toList();

    if (relevantFrames.isEmpty) return approximateStart;

    // 음성이 시작되는 첫 지점 찾기
    for (final frame in relevantFrames) {
      if (frame.rmsLevel >= voiceThreshold) {
        return frame.timeSec.clamp(minStart, double.infinity);
      }
    }

    return approximateStart; // 찾지 못하면 원래 값 유지
  }

  // 에너지 프로파일에서 실제 단어 끝 지점 찾기 (적극적 조정)
  double _findActualWordEnd(
    double approximateEnd, 
    List<AudioEnergyFrame> energyProfile,
    double? nextWordStart,  // 다음 단어 시작 시간
  ) {
    // 보수적 탐색: 탐색 범위 축소 (WhisperX 타이밍 신뢰)
    const double searchBefore = 0.1;  // 앞으로 100ms (축소)
    const double searchAfter = 0.05;  // 뒤로 50ms (축소)
    const double voiceThreshold = -40.0; // -40dB 이상은 음성

    // 다음 단어와 겹치지 않도록 최대 끝 시간 설정
    final maxEnd = nextWordStart ?? double.infinity;
    final searchStart = approximateEnd - searchBefore;
    final searchEnd = (approximateEnd + searchAfter).clamp(0.0, maxEnd);

    // 탐색 범위 내의 프레임들 (역순으로)
    final relevantFrames = energyProfile.where((frame) =>
      frame.timeSec >= searchStart && frame.timeSec <= searchEnd
    ).toList().reversed.toList();

    if (relevantFrames.isEmpty) return approximateEnd;

    // 음성이 끝나는 지점 찾기 (마지막 음성 프레임)
    for (final frame in relevantFrames) {
      if (frame.rmsLevel >= voiceThreshold) {
        return frame.timeSec.clamp(0.0, maxEnd);
      }
    }

    return approximateEnd; // 찾지 못하면 원래 값 유지
  }

  // 에너지 프로파일 기반 단어 경계 미세 조정 (적극적)
  List<WhisperSegment> _refineWordBoundariesWithEnergy(
    List<WhisperSegment> segments,
    List<AudioEnergyFrame> energyProfile,
  ) {
    if (energyProfile.isEmpty) {
      if (kDebugMode) print('⚠️ 에너지 프로파일이 비어있어 조정을 건너뜁니다.');
      return segments;
    }

    const double minimumWordDuration = _kMinimumWordDuration;
    const double gapTolerance = _kGapTolerance;
    final List<WhisperSegment> result = [];
    double? lastWordEndInPreviousSegment;  // 이전 세그먼트의 마지막 토큰 끝 시간
    final List<SilenceSegment> integratedSilences = [];

    for (final segment in segments) {
      if (segment.words.isEmpty) {
        result.add(segment);
        lastWordEndInPreviousSegment = segment.endSec;
        continue;
      }

      final refinedWords = <WordSegment>[];

      final double segmentStartRounded = _floorToCentisecond(segment.startSec);
      final double segmentEndRounded = _ceilToCentisecond(segment.endSec);

      for (int i = 0; i < segment.words.length; i++) {
        final word = segment.words[i];

        final double approximateStart = word.startSec;
        final double approximateEnd = word.endSec;

        final double baselineStart = lastWordEndInPreviousSegment ?? segmentStartRounded;
        final double previousTokenEnd = refinedWords.isNotEmpty
            ? refinedWords.last.endSec
            : baselineStart;

        final double actualStart = _findActualWordStart(
          approximateStart,
          energyProfile,
          refinedWords.isNotEmpty ? refinedWords.last.endSec : lastWordEndInPreviousSegment,
        );
        final double actualEnd = _findActualWordEnd(
          approximateEnd,
          energyProfile,
          i < segment.words.length - 1 ? segment.words[i + 1].startSec : null,
        );

        // actualStart 사용 (에너지 기반 조정 적용)
        double normalizedStart = _floorToCentisecond(actualStart);
        
        // 첫 단어: 이전 세그먼트 끝 또는 세그먼트 시작 이후여야 함
        if (refinedWords.isEmpty) {
          if (lastWordEndInPreviousSegment != null) {
            normalizedStart = math.max(normalizedStart, lastWordEndInPreviousSegment!);
          } else {
            normalizedStart = math.max(normalizedStart, segmentStartRounded);
          }
        } else {
          // 이후 단어: 이전 단어 끝 이후여야 함 (연속성 보장)
          normalizedStart = math.max(normalizedStart, previousTokenEnd);
        }
        
        // 간격이 있으면 무음으로 기록
        if (refinedWords.isNotEmpty && normalizedStart > previousTokenEnd + gapTolerance) {
          final double gapStart = previousTokenEnd;
          final double gapEnd = normalizedStart;
          if (gapEnd - gapStart > gapTolerance) {
            integratedSilences.add(SilenceSegment(
              startSec: gapStart,
              endSec: gapEnd,
              duration: gapEnd - gapStart,
            ));
          }
          if (kDebugMode) {
            print('   ↔ 단어 간 여유 제거: ${gapStart.toStringAsFixed(2)}s ~ ${gapEnd.toStringAsFixed(2)}s → ${gapStart.toStringAsFixed(2)}s (무음 통합)');
          }
        }

        double normalizedEnd = _ceilToCentisecond(actualEnd);
        if (normalizedEnd < normalizedStart + minimumWordDuration) {
          normalizedEnd = normalizedStart + minimumWordDuration;
        }

        if (i == segment.words.length - 1 && normalizedEnd < segmentEndRounded - gapTolerance) {
          final double gapStart = normalizedEnd;
          final double gapEnd = segmentEndRounded;
          if (gapEnd - gapStart > gapTolerance) {
            integratedSilences.add(SilenceSegment(
              startSec: gapStart,
              endSec: gapEnd,
              duration: gapEnd - gapStart,
            ));
          }
          if (kDebugMode) {
            print('   ↔ 세그먼트 말미 여유: ${gapStart.toStringAsFixed(2)}s ~ ${gapEnd.toStringAsFixed(2)}s → ${gapEnd.toStringAsFixed(2)}s (무음 통합)');
          }
          normalizedEnd = gapEnd;
        } else {
          normalizedEnd = math.min(normalizedEnd, segmentEndRounded);
        }
        
        // 조정 로그 출력
        if (kDebugMode) {
          final startChanged = (normalizedStart - approximateStart).abs() > 0.01;
          final endChanged = (normalizedEnd - approximateEnd).abs() > 0.01;
          if (startChanged || endChanged) {
            print('  🔧 단어 #${i + 1} "${word.word}": '
                '${approximateStart.toStringAsFixed(2)}-${approximateEnd.toStringAsFixed(2)}s → '
                '${normalizedStart.toStringAsFixed(2)}-${normalizedEnd.toStringAsFixed(2)}s '
                '(prev=${previousTokenEnd.toStringAsFixed(2)})');
          } else {
            print('   ✓ 단어 #${i + 1} "${word.word}": '
                '${approximateStart.toStringAsFixed(2)}-${approximateEnd.toStringAsFixed(2)}s → '
                '${normalizedStart.toStringAsFixed(2)}-${normalizedEnd.toStringAsFixed(2)}s');
          }
        }

        refinedWords.add(WordSegment(
          index: word.index,
          word: word.word,
          startSec: normalizedStart,
          endSec: normalizedEnd,
          score: word.score,
        ));

        // 다음 토큰과의 간격 정보 (무음 기록 없음)
        final double nextApproximateStart =
            (i < segment.words.length - 1) ? segment.words[i + 1].startSec : segmentEndRounded;
        final double nextStartCandidate = _floorToCentisecond(nextApproximateStart);
        if (normalizedEnd + gapTolerance < nextStartCandidate && i < segment.words.length - 1) {
          final double gapStart = normalizedEnd;
          final double gapEnd = nextStartCandidate;
          if (gapEnd - gapStart > gapTolerance) {
            integratedSilences.add(SilenceSegment(
              startSec: gapStart,
              endSec: gapEnd,
              duration: gapEnd - gapStart,
            ));
          }
          if (kDebugMode) {
            print('   ↔ 단어 간 여유 제거: ${gapStart.toStringAsFixed(2)}s ~ ${gapEnd.toStringAsFixed(2)}s → ${gapStart.toStringAsFixed(2)}s (무음 통합)');
          }
          normalizedEnd = gapStart;
        }
      }
      double segmentStartForCopy = refinedWords.first.startSec;
      double segmentEndForCopy = refinedWords.last.endSec;

      result.add(segment.copyWith(
        words: refinedWords,
        startSec: segmentStartForCopy,
        endSec: segmentEndForCopy,
      ));

      lastWordEndInPreviousSegment = segmentEndForCopy;
    }

    if (kDebugMode && integratedSilences.isNotEmpty) {
      print('총 ${integratedSilences.length}개의 에너지 기반 무음을 단어에 통합했습니다.');
    }
    return result;
  }

  // SRT 시간을 초 단위로 변환
  double _srtTimeToSeconds(String srtTime) {
    final parts = srtTime.split(':');
    if (parts.length == 3) {
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      final seconds = double.parse(parts[2].replaceAll(',', '.'));
      return hours * 3600 + minutes * 60 + seconds;
    }
    return 0.0;
  }

  // 유틸리티 메서드들
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // 음성인식 완료 처리 (크레딧 차감 및 데이터 저장)
  Future<void> _handleTranscribeCompletion(List<WhisperSegment> segments) async {
    try {
      if (!_authService.isLoggedIn) {
        if (kDebugMode) print('❌ AIService: 로그인되지 않은 사용자 - 데이터 저장 건너뜀');
        return;
      }

      final videoPath = appState.videoPath;
      if (videoPath == null) {
        if (kDebugMode) print('❌ AIService: 비디오 경로가 없음 - 데이터 저장 건너뜀');
        return;
      }

      // 비디오 길이 계산
      final videoController = appState.videoController;
      if (videoController == null || !videoController.value.isInitialized) {
        if (kDebugMode) print('❌ AIService: 비디오 컨트롤러가 초기화되지 않음 - 데이터 저장 건너뜀');
        return;
      }

      final videoDuration = videoController.value.duration.inSeconds.toDouble();
      
      // 음성인식은 크레딧 차감하지 않음 (전체 과정 완료 시에만 차감)
      // 현재 크레딧 조회
      final remainingCredits = await _creditService.getUserCredits();

      // transcribe 메타데이터 생성
      final transcribeMeta = {
        'videoLength': videoDuration,
        'duration': videoDuration,
        'videoId': _generateVideoId(videoPath),
        'speechRate': segments.length / videoDuration, // 초당 세그먼트 수
        'modelSize': 'large-v3-turbo',
        'segmentCount': segments.length,
      };

      // 음성인식 단계에서는 개별 로깅하지 않음 (전체 완료 시에만 통합 로깅)

      if (kDebugMode) print('✅ AIService: 음성인식 데이터 저장 완료');
    } catch (e) {
      if (kDebugMode) print('❌ AIService: 음성인식 데이터 저장 실패: $e');
    }
  }

  // 내용 요약 완료 처리 (크레딧 차감 및 데이터 저장)
  Future<void> _handleSummarizeCompletion(List<int> selectedIds, String summary) async {
    try {
      if (!_authService.isLoggedIn) {
        if (kDebugMode) print('❌ AIService: 로그인되지 않은 사용자 - 데이터 저장 건너뜀');
        return;
      }

      final videoPath = appState.videoPath;
      if (videoPath == null) {
        if (kDebugMode) print('❌ AIService: 비디오 경로가 없음 - 데이터 저장 건너뜀');
        return;
      }

      // 비디오 길이 계산
      final videoController = appState.videoController;
      if (videoController == null || !videoController.value.isInitialized) {
        if (kDebugMode) print('❌ AIService: 비디오 컨트롤러가 초기화되지 않음 - 데이터 저장 건너뜀');
        return;
      }

      final videoDuration = videoController.value.duration.inSeconds.toDouble();
      
      // 요약도 크레딧 차감하지 않음 (전체 과정 완료 시에만 차감)
      // 현재 크레딧 조회
      final remainingCredits = await _creditService.getUserCredits();

      // summarize 메타데이터 생성
      final summarizeMeta = {
        'segmentCount': selectedIds.length,
        'speechRate': appState.segments.length / videoDuration, // 초당 세그먼트 수
        'summaryLength': videoDuration * (selectedIds.length / appState.segments.length), // 요약된 비디오 길이
        'apiCost': 0.0, // OpenAI API 비용 (실제로는 계산해야 함)
        'tokenUsage': {
          'in': 0, // 입력 토큰 수 (실제로는 계산해야 함)
          'out': 0, // 출력 토큰 수 (실제로는 계산해야 함)
        },
        'videoId': _generateVideoId(videoPath),
      };

      // 요약 단계에서는 개별 로깅하지 않음 (전체 완료 시에만 통합 로깅)

      if (kDebugMode) print('✅ AIService: 내용 요약 데이터 저장 완료');
    } catch (e) {
      if (kDebugMode) print('❌ AIService: 내용 요약 데이터 저장 실패: $e');
    }
  }

  // 전체 과정 완료 시 크레딧 차감 (음성인식 + 요약)
  Future<void> handleCompleteProcessing() async {
    try {
      if (!_authService.isLoggedIn) {
        if (kDebugMode) print('❌ AIService: 로그인되지 않은 사용자 - 크레딧 차감 건너뜀');
        return;
      }

      final videoPath = appState.videoPath;
      if (videoPath == null) {
        if (kDebugMode) print('❌ AIService: 비디오 경로가 없음 - 크레딧 차감 건너뜀');
        return;
      }

      // 비디오 길이 계산
      final videoController = appState.videoController;
      if (videoController == null || !videoController.value.isInitialized) {
        if (kDebugMode) print('❌ AIService: 비디오 컨트롤러가 초기화되지 않음 - 크레딧 차감 건너뜀');
        return;
      }

      final videoDuration = videoController.value.duration.inSeconds.toDouble();
      
      // Firebase Functions를 통한 서버 사이드 크레딧 차감
      final idToken = await _authService.getIdToken();
      if (idToken == null) {
        if (kDebugMode) print('❌ AIService: ID 토큰 없음 - 크레딧 차감 건너뜀');
        return;
      }

      // 크레딧 차감 (비디오 길이 기반)
      // 0초~29초: 1크레딧, 30초부터 60초 단위로 증가
      int creditCost;
      if (videoDuration <= 29) {
        creditCost = 1; // 0초~29초
      } else {
        creditCost = ((videoDuration - 30) / 60).floor() + 1; // 30초부터 60초 단위
      }
      
      final deductResult = await _functionsService.deductCredits(
        creditCost,
        idToken: idToken,
      );

      if (!deductResult['success']) {
        if (kDebugMode) print('❌ AIService: 서버 크레딧 차감 실패: ${deductResult['error']}');
        return;
      }

      final responseData = deductResult['data'] as Map<String, dynamic>;
      final remainingCredits = responseData['credits'] as int;

      // 전체 과정 완료 메타데이터 생성
      final completeMeta = {
        'videoLength': videoDuration,
        'duration': videoDuration,
        'videoId': _generateVideoId(videoPath),
        'segmentCount': appState.segments.length,
        'selectedSegmentCount': appState.highlightedSegments.length,
        'processingType': 'transcribe_and_summarize',
        'speechRate': appState.segments.length / videoDuration, // 초당 세그먼트 수
        'modelSize': 'large-v3-turbo',
        'totalProcessingTime': DateTime.now().millisecondsSinceEpoch,
      };

      // FirestoreService 로깅은 제거됨 - Firebase Functions에서 통합 로깅 처리

      // Firebase Functions 통합 액션 로깅 추가 (음성인식 + 요약 완료)
      final actionId = 'complete_${DateTime.now().millisecondsSinceEpoch}';
      // creditCost는 위에서 계산된 값 사용
      
      final transcribeMetaData = {
        'success': true,
        'videoLength': videoDuration,
        'duration': videoDuration,
        'videoId': _generateVideoId(videoPath),
        'segmentCount': appState.segments.length,
        'speechRate': appState.segments.length / videoDuration,
        'modelSize': 'large-v3-turbo',
        'processingType': 'transcribe',
      };
      
      final summarizeMetaData = {
        'success': true,
        'segmentCount': appState.segments.length,
        'selectedSegmentCount': appState.highlightedSegments.length,
        'processingType': 'summarize',
        'totalProcessingTime': DateTime.now().millisecondsSinceEpoch,
      };
      
      if (kDebugMode) {
        print('🔍 AIService: 전송할 데이터 확인');
        print('  - actionId: $actionId');
        print('  - creditCost: $creditCost');
        print('  - transcribeMeta: $transcribeMetaData');
        print('  - summarizeMeta: $summarizeMetaData');
      }
      
      await _logAction(
        actionId: actionId,
        success: true,
        creditCost: creditCost,
        remainingCredits: remainingCredits,
        processingTime: DateTime.now().millisecondsSinceEpoch,
        transcribeMeta: transcribeMetaData,
        summarizeMeta: summarizeMetaData,
      );

      if (kDebugMode) print('✅ AIService: 전체 과정 완료 - 크레딧 차감 완료');
    } catch (e) {
      if (kDebugMode) print('❌ AIService: 전체 과정 완료 크레딧 차감 실패: $e');
    }
  }

  // 비디오 ID 생성 (간단한 해시)
  String _generateVideoId(String videoPath) {
    return videoPath.hashCode.abs().toString();
  }

  // JSON 코드 블록 제거 함수
  String _removeJsonCodeBlock(String content) {
    // ```json으로 시작하고 ```로 끝나는 코드 블록 제거
    final jsonBlockPattern = RegExp(r'```json\s*\n?(.*?)\n?```', dotAll: true);
    final match = jsonBlockPattern.firstMatch(content);
    
    if (match != null) {
      return match.group(1)?.trim() ?? content;
    }
    
    // ```json이 없으면 원본 반환
    return content.trim();
  }

  String? _reconstructTextFromWords(List<WordSegment> words) {
    if (words.isEmpty) return null;
    final buffer = StringBuffer();
    for (var i = 0; i < words.length; i++) {
      final token = words[i].word.trim();
      if (token.isEmpty) continue;

      if (buffer.isEmpty) {
        buffer.write(token);
        continue;
      }

      if (_shouldAttachWithoutSpace(token)) {
        buffer.write(token);
      } else if (_isSuffixPunctuation(token)) {
        buffer.write(token);
      } else {
        buffer.write(' ');
        buffer.write(token);
      }
    }

    return buffer.toString().replaceAll(' ,', ',').replaceAll(' .', '.').trim();
  }

  bool _shouldAttachWithoutSpace(String token) {
    const prefixes = ['%', "'", '"', ')', '}', ']', '…'];
    return prefixes.contains(token);
  }

  bool _isSuffixPunctuation(String token) {
    if (token.length > 2) return false;
    const suffixes = ['.', ',', '!', '?', ')', ']', '}', ':', ';', '…'];
    return suffixes.contains(token);
  }

  bool _hasSilenceCoveringGap(
    List<SilenceSegment> silences,
    double gapStart,
    double gapEnd,
  ) {
    for (final silence in silences) {
      if (silence.endSec <= gapStart + _kGapTolerance) {
        continue;
      }
      if (silence.startSec >= gapEnd - _kGapTolerance) {
        break;
      }
      final bool coversStart = silence.startSec <= gapStart + _kGapTolerance;
      final bool coversEnd = silence.endSec >= gapEnd - _kGapTolerance;
      if (coversStart && coversEnd) {
        return true;
      }
    }
    return false;
  }

  List<WhisperSegment> _ensureContinuousWordTimeline(
    List<WhisperSegment> segments,
  ) {
    final List<SilenceSegment> allSilences = [];
    for (final segment in segments) {
      allSilences.addAll(_extractSilenceSegments(segment.words));
    }
    allSilences.sort((a, b) => a.startSec.compareTo(b.startSec));

    final List<WhisperSegment> adjustedSegments = [];
    double? lastWordEnd;

    for (final segment in segments) {
      if (segment.words.isEmpty) {
        adjustedSegments.add(segment);
        continue;
      }

      final List<WordSegment> adjustedWords = [];

      for (int i = 0; i < segment.words.length; i++) {
        final word = segment.words[i];
        double start = word.startSec;

        if (lastWordEnd != null) {
          if (start < lastWordEnd! - _kGapTolerance) {
            start = lastWordEnd!;
          } else if (start - lastWordEnd! > _kGapTolerance &&
              !_hasSilenceCoveringGap(allSilences, lastWordEnd!, start)) {
            start = lastWordEnd!;
          }
        }

        double end = word.endSec;
        if (end < start + _kMinimumWordDuration) {
          end = start + _kMinimumWordDuration;
        }

        final adjustedWord = WordSegment(
          index: word.index,
          word: word.word,
          startSec: start,
          endSec: end,
          score: word.score,
        );
        adjustedWords.add(adjustedWord);
        lastWordEnd = end;
      }

      adjustedSegments.add(segment.copyWith(
        words: adjustedWords,
        startSec: adjustedWords.first.startSec,
        endSec: math.max(segment.endSec, adjustedWords.last.endSec),
      ));
    }

    return adjustedSegments;
  }

  // ============================================================================
  // 세그먼트 재조합 관련 함수들
  // ============================================================================

  /// 문장 완결성 체크 (완결되면 true, 불완전하면 false)
  bool _hasCompleteSentence(String text) {
    final trimmed = text.trim();
    
    // 1. 명확한 문장 부호
    if (trimmed.endsWith('.') || trimmed.endsWith('?') || trimmed.endsWith('!')) {
      return true;
    }
    
    // 2. 명확히 불완전한 경우 (연결어미)
    final connectiveEndings = [
      '는데', '은데', '지만', '아서', '어서', '면', '으면',
      '니까', '나', '거든', '고', '는지', '을지',
      ',', '~', '...', '…',
    ];
    
    for (final ending in connectiveEndings) {
      if (trimmed.endsWith(ending)) {
        return false; // 확실히 불완전
      }
    }
    
    // 3. 완결 종결어미
    final completionEndings = [
      // 평서형
      '습니다', '니다', '입니다', '합니다', '됩니다', '있습니다', '없습니다',
      '였습니다', '었습니다', '았습니다',
      '해요', '지요', '죠', '네요',
      '어요', '아요', '여요', '해', '어', '아',
      
      // 의문형
      '습니까', '니까', '나요', '까요', '을까요',
      
      // 명령형
      '세요', '으세요', '하세요', '십시오',
      
      // 청유형
      '시다', '읍시다', '자', '자요',
      
      // 감탄형
      '구나', '구먼', '로구나', '로군',
    ];
    
    for (final ending in completionEndings) {
      if (trimmed.endsWith(ending)) {
        return true; // 완결
      }
    }
    
    // 4. 독립 완결 표현
    final standaloneComplete = [
      '네', '예', '아니요', '아니오', 
      '감사합니다', '알겠습니다', '좋습니다', '그렇습니다', '맞습니다',
      '안녕하세요', '안녕히가세요', '감사해요', '고맙습니다',
    ];
    
    if (standaloneComplete.contains(trimmed)) {
      return true;
    }
    
    // 5. 조사로 끝나면 불완전
    final particles = ['는', '을', '를', '이', '가', '의', '에', '와', '과', '도', '만'];
    for (final particle in particles) {
      if (trimmed.endsWith(particle)) {
        return false;
      }
    }
    
    // 6. 기본값: 짧은 문장은 불완전으로 간주 (안전)
    return trimmed.length >= 5; // 5글자 이상은 완결로 간주
  }

  /// 여러 세그먼트를 하나로 병합
  WhisperSegment _mergeSegments(List<WhisperSegment> segments) {
    if (segments.isEmpty) throw ArgumentError('빈 세그먼트 리스트');
    if (segments.length == 1) return segments.first;
    
    // 시작/종료 시간
    final startSec = segments.first.startSec;
    final endSec = segments.last.endSec;
    
    // 텍스트 병합
    final mergedText = segments.map((s) => s.text.trim()).join(' ');
    
    // 단어 병합
    final mergedWords = <WordSegment>[];
    for (final seg in segments) {
      mergedWords.addAll(seg.words);
    }
    
    // confidence 평균 계산
    final avgConfidence = segments
      .map((s) => s.confidence)
      .reduce((a, b) => a + b) / segments.length;
    
    return WhisperSegment(
      id: segments.first.id, // ID는 나중에 재할당
      startSec: startSec,
      endSec: endSec,
      text: mergedText,
      confidence: avgConfidence,
      words: mergedWords,
    );
  }

  /// 세그먼트 끝 무음 길이 계산
  double _getTrailingSilenceDuration(WhisperSegment segment) {
    // 마지막 토큰이 무음인지 확인
    if (segment.words.isEmpty) return 0.0;
    
    final lastToken = segment.words.last;
    if (!lastToken.isSilence) return 0.0;
    
    // 세그먼트 끝에서 0.1초 이내에 시작하는 무음만 "끝 무음"으로 간주
    if (segment.endSec - lastToken.startSec <= 0.1) {
      return lastToken.duration;
    }
    return 0.0;
  }

  /// 다음 세그먼트 내에서 적절한 무음 분할점 찾기
  int? _findSilenceSplitPoint(WhisperSegment segment, {double minSilenceDuration = 0.3}) {
    // 세그먼트 내 단어들과 무음들을 시간순으로 정렬하여 분석
    if (segment.words.length < 3) return null; // 너무 짧으면 분할 안 함
    
    // 긴 무음 찾기 (words에 포함되어 있음)
    for (int i = 1; i < segment.words.length - 1; i++) {
      final token = segment.words[i];
      
      // 무음이고 충분히 긴 경우
      if (token.isSilence && token.duration >= minSilenceDuration) {
        // 분할 후 양쪽 세그먼트가 최소 1개 이상의 단어를 가지는지 확인
        // (무음 이전에 최소 1개, 무음 이후에 최소 1개의 단어 필요)
        final wordsBeforeSilence = segment.words.sublist(0, i).where((w) => !w.isSilence).length;
        final wordsAfterSilence = segment.words.sublist(i + 1).where((w) => !w.isSilence).length;
        
        if (wordsBeforeSilence >= 1 && wordsAfterSilence >= 1) {
          return i; // 이 무음 뒤에서 분할 (무음은 첫 번째 세그먼트에 포함)
        }
      }
    }
    
    return null;
  }

  /// 세그먼트를 특정 단어 인덱스에서 분할
  List<WhisperSegment> _splitSegmentAtWord(WhisperSegment segment, int splitWordIndex) {
    final firstWords = segment.words.sublist(0, splitWordIndex + 1);
    final secondWords = segment.words.sublist(splitWordIndex + 1);
    
    // 인덱스 재조정
    for (int i = 0; i < firstWords.length; i++) {
      firstWords[i] = firstWords[i].copyWith(index: i);
    }
    for (int i = 0; i < secondWords.length; i++) {
      secondWords[i] = secondWords[i].copyWith(index: i);
    }
    
    // text는 단어만 (무음 제외)
    final firstText = firstWords.where((w) => !w.isSilence).map((w) => w.word).join(' ');
    final secondText = secondWords.where((w) => !w.isSilence).map((w) => w.word).join(' ');
    
    final firstSegment = WhisperSegment(
      id: segment.id,
      startSec: segment.startSec,
      endSec: firstWords.last.endSec,
      text: firstText,
      confidence: segment.confidence,
      words: firstWords,
    );
    
    final secondSegment = WhisperSegment(
      id: segment.id + 1,
      startSec: secondWords.first.startSec,
      endSec: segment.endSec,
      text: secondText,
      confidence: segment.confidence,
      words: secondWords,
    );
    
    return [firstSegment, secondSegment];
  }

  /// 세그먼트 재조합 (분할 → 병합)
  List<WhisperSegment> _recombineSegments(List<WhisperSegment> segments) {
    if (segments.isEmpty) return segments;
    
    if (kDebugMode) {
      print('=== 세그먼트 재조합 시작 (${segments.length}개) ===');
    }
    
    // ========================================
    // Step 1: 무음 기반 분할 (모든 세그먼트가 무음으로 끝나도록)
    // ========================================
    final List<WhisperSegment> splitSegments = [];
    for (final segment in segments) {
      splitSegments.addAll(_splitSegmentBySilence(segment));
    }
    
    if (kDebugMode) {
      final splitSilenceCount = splitSegments.where((s) => _getTrailingSilenceDuration(s) > 0.05).length;
      print('✂️ 분할 완료: ${segments.length}개 → ${splitSegments.length}개 (무음으로 끝남: $splitSilenceCount/${splitSegments.length})');
    }
    
    // ========================================
    // Step 2: 의미 기반 병합 (짧은 세그먼트 통합)
    // ========================================
    final List<WhisperSegment> result = [];
    int i = 0;
    
    while (i < splitSegments.length) {
      final current = splitSegments[i];
      final wordCount = current.words.length;
      final text = current.text.trim();
      final duration = current.endSec - current.startSec;
      final hasTrailingSilence = _getTrailingSilenceDuration(current) > 0.05;
      
      bool shouldMergeWithPrev = false;
      String mergeReason = '';
      
      // 이전 세그먼트가 있는지 확인
      if (result.isNotEmpty) {
        final prevDuration = result.last.endSec - result.last.startSec;
        final mergedDuration = prevDuration + duration;
        
        // 병합 후 5초 초과 여부 확인
        final wouldExceedMaxDuration = mergedDuration > 5.0;
        
        // 우선순위 1: 무음으로 끝나지 않는 세그먼트 (무조건 병합 시도)
        if (!hasTrailingSilence) {
          if (!wouldExceedMaxDuration) {
            shouldMergeWithPrev = true;
            mergeReason = '무음없음';
          }
        }
        // 우선순위 2: 단어 1개 세그먼트
        else if (wordCount == 1 && !_hasCompleteSentence(text)) {
          final prevHasSilence = _getTrailingSilenceDuration(result.last) > 0.05;
          if (prevHasSilence && !wouldExceedMaxDuration) {
            shouldMergeWithPrev = true;
            mergeReason = '단어1개';
          }
        }
        // 우선순위 3: 짧은 시간 세그먼트
        else if (duration < 1.0 && !_hasCompleteSentence(text)) {
          final prevHasSilence = _getTrailingSilenceDuration(result.last) > 0.05;
          if (prevHasSilence && !wouldExceedMaxDuration) {
            shouldMergeWithPrev = true;
            mergeReason = '짧은시간';
          }
        }
      }
      
      if (shouldMergeWithPrev) {
        final prevSegment = result.removeLast();
        final merged = _mergeSegments([prevSegment, current]);
        result.add(merged);
        
        if (kDebugMode) {
          final preview = merged.text.length > 50 
            ? '${merged.text.substring(0, 50)}...' 
            : merged.text;
          print('📦 병합($mergeReason): #${prevSegment.id}+#${current.id} → "$preview" (${(merged.endSec - merged.startSec).toStringAsFixed(1)}s)');
        }
      } else {
        result.add(current);
      }
      
      i++;
    }
    
    if (kDebugMode) {
      print('📦 병합 완료: ${splitSegments.length}개 → ${result.length}개');
    }
    
    // ========================================
    // Step 3: ID 재할당 및 최종 통계
    // ========================================
    for (int i = 0; i < result.length; i++) {
      result[i] = result[i].copyWith(id: i + 1);
    }
    
    final endingSilenceCount = result.where((s) => _getTrailingSilenceDuration(s) > 0.05).length;
    final endingSilencePercent = (endingSilenceCount / result.length * 100).toStringAsFixed(1);
    
    if (kDebugMode) {
      print('=== 세그먼트 재조합 완료: ${segments.length}개 → ${result.length}개 (${result.length - segments.length >= 0 ? '+' : ''}${result.length - segments.length}) ===');
      print('🔇 무음으로 끝나는 세그먼트: $endingSilenceCount/${result.length} ($endingSilencePercent%)');
    }
    
    return result;
  }
  
  /// 세그먼트를 무음 기준으로 재귀적으로 분할
  List<WhisperSegment> _splitSegmentBySilence(WhisperSegment segment) {
    final hasTrailingSilence = _getTrailingSilenceDuration(segment) > 0.05;
    
    // 이미 무음으로 끝나면 그대로 반환
    if (hasTrailingSilence) {
      return [segment];
    }
    
    // 내부에서 긴 무음(0.3초 이상) 찾기
    final splitPoint = _findSilenceSplitPoint(segment, minSilenceDuration: 0.3);
    
    if (splitPoint == null) {
      // 분할점 없음 → 그대로 반환 (무음 없이 유지)
      return [segment];
    }
    
    // 분할 실행
    final splitSegments = _splitSegmentAtWord(segment, splitPoint);
    
    // 두 번째 세그먼트를 재귀적으로 처리
    final result = <WhisperSegment>[splitSegments[0]];
    result.addAll(_splitSegmentBySilence(splitSegments[1]));
    
    return result;
  }

}

// 시간 구간 타입
enum _RegionType {
  silence,  // 무음 구간
  speech,   // 발화 구간
}

// 시간 구간 표현 클래스
class _TimeRegion {
  final _RegionType type;
  final double startSec;
  final double endSec;
  
  // 무음 데이터
  final SilenceSegment? silenceData;
  
  // 발화 데이터
  final WordSegment? wordData;
  final int? originalSegmentId;
  final String? originalSegmentText;
  
  _TimeRegion({
    required this.type,
    required this.startSec,
    required this.endSec,
    this.silenceData,
    this.wordData,
    this.originalSegmentId,
    this.originalSegmentText,
  });
}

class _WordPointer {
  final int segmentIndex;
  final int wordIndex;

  const _WordPointer(this.segmentIndex, this.wordIndex);
}
