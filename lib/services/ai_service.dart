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

  AIService(this.appState, this.context);

  // CreditService getter
  CreditService get creditService => _creditService;

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
      print('🤖 AIService: AI 기반 고급 챕터 생성 시작');
      
      if (appState.segments.isEmpty) {
        print('❌ AIService: 세그먼트가 없습니다');
        _showErrorSnackBar('세그먼트가 없습니다. 먼저 음성인식을 진행해주세요.');
        return;
      }
      

      
      // OpenAI API를 사용한 고급 챕터 생성
      final themeGroups = await _generateChaptersWithAI();
      
      if (themeGroups.isNotEmpty) {
        // AppState에 고급 챕터 정보 업데이트
        appState.themeGroups = themeGroups;
        print('✅ AIService: AI 기반 고급 챕터 생성 완료 - ${themeGroups.length}개 챕터');
        
        _showSuccessSnackBar('AI가 생성한 고급 챕터 정보가 완성되었습니다. ${themeGroups.length}개 챕터를 생성했습니다.');
      } else {
        _showErrorSnackBar('AI 챕터 생성에 실패했습니다.');
      }
      
    } catch (e) {
      print('❌ AIService: AI 챕터 생성 중 오류: $e');
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
      print('✅ AIService: 이미 취소된 상태 - 음성인식 작업 시작 안함');
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
      
      // 로컬 Whisper 호출
      print('=== 로컬 Whisper 호출 시작 ===');
      
      final segments = await _callLocalWhisper(audioPath);
      
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
        print('✅ AIService: 음성인식 작업이 취소됨');
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
      print('✅ AIService: 이미 요약이 진행 중 - 중복 실행 방지');
      return;
    }
    
    // 인증 체크
    _checkAuthentication();
    
    // 이미 취소된 상태라면 작업 시작하지 않음
    if (_isCancelled || appState.isOperationCancelled) {
      print('✅ AIService: 이미 취소된 상태 - 요약 작업 시작 안함');
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
        print('✅ AIService: STEP 1에서 작업 취소됨');
        appState.isSummarizing = false;
        return;
      }
      
      List<Map<String, dynamic>> chunkOverviews = [];
      for (int i = 0; i < chunks.length; i++) {
        // 취소 상태 직접 확인
        if (_isCancelled || appState.isOperationCancelled) {
          print('✅ AIService: STEP 1 루프에서 작업 취소됨');
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
        print('✅ AIService: STEP 2에서 작업 취소됨');
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
        print('✅ AIService: STEP 3에서 작업 취소됨');
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
        print('✅ AIService: STEP 4에서 작업 취소됨');
        appState.isSummarizing = false;
        return;
      }
      
      List<int> allSelectedIds = [];
      for (int i = 0; i < themeGroups.length; i++) {
        // 취소 상태 직접 확인
        if (_isCancelled || appState.isOperationCancelled) {
          print('✅ AIService: STEP 4 루프에서 작업 취소됨');
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
        print('✅ AIService: STEP 5에서 작업 취소됨');
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
        print('✅ AIService: 요약 작업이 취소됨');
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
  Future<List<WhisperSegment>> callLocalWhisper(String audioPath) async {
    print('=== whisper.cpp 호출 시작 ===');
    
    try {
      // whisper.cpp 실행 파일 경로 설정 (VAD 제거, large-v3-turbo만 사용)
      String whisperCliPath;
      String modelPath;
      
      if (Platform.isMacOS) {
        // 개발 중에는 프로젝트 디렉토리 사용, 배포 시에는 앱 번들 내부 사용
        final projectDir = Directory.current.path;
        print('현재 디렉토리: $projectDir');
        
        // 개발 환경에서는 절대 경로 사용
        final projectRoot = '/Users/ihuijae/Desktop/Flutter_Workspace/bestcut_flutter';
        whisperCliPath = '$projectRoot/whisper.cpp/build/bin/whisper-cli';
        modelPath = '$projectRoot/whisper.cpp/models/ggml-large-v3-turbo.bin';
        print('개발 환경 경로 사용');
      } else if (Platform.isWindows) {
        final projectDir = Directory.current.path;
        final projectRoot = 'C:\\Users\\ihuijae\\Desktop\\Flutter_Workspace\\bestcut_flutter';
        if (File('$projectRoot\\whisper.cpp\\build\\bin\\whisper-cli.exe').existsSync()) {
          // 개발 환경
          whisperCliPath = '$projectRoot\\whisper.cpp\\build\\bin\\whisper-cli.exe';
          modelPath = '$projectRoot\\whisper.cpp\\models\\ggml-large-v3-turbo.bin';
        } else {
          // 배포 환경
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
      final segments = _parseSrtToSegments(srtContent);
      
      // 위스퍼 결과물을 그대로 사용 (보정 기능 제거)
      print('whisper.cpp 성공: ${segments.length}개 세그먼트 (원본 그대로 사용)');
      
      return segments;
      
    } catch (e) {
      print('whisper.cpp 호출 중 오류: $e');
      rethrow;
    }
  }

  // whisper.cpp 호출 함수 (private - 내부용)
  Future<List<WhisperSegment>> _callLocalWhisper(String audioPath) async {
    return callLocalWhisper(audioPath);
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
                  currentStart = _srtTimeToSeconds(parts[0].trim()).toStringAsFixed(2);
        currentEnd = _srtTimeToSeconds(parts[1].trim()).toStringAsFixed(2);
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
      print('✅ AIService: _getChunkOverview에서 작업 취소됨');
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
      print('✅ AIService: _integrateChunkOverviews에서 작업 취소됨');
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
      print('✅ AIService: _groupSegmentsByTheme에서 작업 취소됨');
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
      print('🤖 AIService: AI 챕터 생성 핵심 로직 시작');
      
      
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
      
      print('✅ AIService: AI 챕터 생성 완료 - ${themeGroups.length}개 챕터');
      return themeGroups;
      
    } catch (e) {
      print('❌ AIService: AI 챕터 생성 중 오류: $e');
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
    // 1. 앱 내장 FFmpeg 시도
    final appResourcesPath = _getAppResourcesPath();
    final appFfmpegPath = '$appResourcesPath/ffmpeg';
    
    // Resources 폴더 내용 확인
    print('🔍 Resources 폴더 내용 확인: $appResourcesPath');
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
    
    if (File(appFfmpegPath).existsSync()) {
      print('✅ 앱 내장 FFmpeg 발견: $appFfmpegPath');
      return appFfmpegPath;
    }
    
    // 2. 시스템 FFmpeg 시도 (App Sandbox에서는 제한적)
    final systemPaths = ['/usr/local/bin/ffmpeg', '/opt/homebrew/bin/ffmpeg'];
    for (final path in systemPaths) {
      if (File(path).existsSync()) {
        print('✅ 시스템 FFmpeg 발견: $path');
        // App Sandbox에서는 시스템 FFmpeg 사용이 제한될 수 있음
        print('⚠️ App Sandbox 환경에서 시스템 FFmpeg 사용 시도');
        return path;
      }
    }
    
    // 3. 기본값 (오류 발생 시 사용자에게 알림)
    print('❌ FFmpeg를 찾을 수 없습니다. 시스템에 설치되어 있는지 확인하세요.');
    return '/usr/local/bin/ffmpeg';
  }
  
  // 앱 Resources 경로 가져오기
  String _getAppResourcesPath() {
    // 앱의 실행 파일 경로를 기준으로 Resources 경로 찾기
    final executablePath = Platform.resolvedExecutable;
    
    // 실행 파일 경로에서 MacOS를 Resources로 변경
    // 예: /path/to/app.app/Contents/MacOS/bestcut_flutter -> /path/to/app.app/Contents/Resources
    return executablePath.replaceAll('/MacOS/bestcut_flutter', '/Resources');
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

      // Firestore에 작업 기록 저장
      await _firestoreService.saveAction(
        type: 'transcribe',
        success: true,
        processingTime: DateTime.now().millisecondsSinceEpoch, // 실제로는 작업 시작 시간부터 계산해야 함
        creditCost: 0, // 음성인식은 크레딧 차감하지 않음
        remainingCredits: remainingCredits,
        transcribeMeta: transcribeMeta,
      );

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

      // Firestore에 작업 기록 저장
      await _firestoreService.saveAction(
        type: 'summarize',
        success: true,
        processingTime: DateTime.now().millisecondsSinceEpoch, // 실제로는 작업 시작 시간부터 계산해야 함
        creditCost: 0, // 요약도 크레딧 차감하지 않음
        remainingCredits: remainingCredits,
        summarizeMeta: summarizeMeta,
      );

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

      final response = await _getHttpClient().post(
        Uri.parse('https://deductcredits-v4kacndtqq-uc.a.run.app'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode({
          'videoDuration': videoDuration,
        }),
      );

      if (response.statusCode != 200) {
        if (kDebugMode) print('❌ AIService: 서버 크레딧 차감 실패: ${response.statusCode}');
        return;
      }

      final responseData = jsonDecode(response.body) as Map<String, dynamic>;
      final remainingCredits = responseData['credits'] as int;

      // 전체 과정 완료 메타데이터 생성
      final completeMeta = {
        'videoLength': videoDuration,
        'duration': videoDuration,
        'videoId': _generateVideoId(videoPath),
        'segmentCount': appState.segments.length,
        'selectedSegmentCount': appState.highlightedSegments.length,
        'processingType': 'transcribe_and_summarize',
      };

      // Firestore에 작업 기록 저장
      await _firestoreService.saveAction(
        type: 'complete_processing',
        success: true,
        processingTime: DateTime.now().millisecondsSinceEpoch,
        creditCost: 0, // 서버에서 차감된 크레딧 (실제로는 서버 응답에서 가져와야 함)
        remainingCredits: remainingCredits,
        transcribeMeta: completeMeta,
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

}
