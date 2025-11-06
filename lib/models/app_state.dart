import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'whisper_segment.dart';
import 'theme_group.dart';

/// 앱의 전체 상태를 관리하는 클래스
class AppState extends ChangeNotifier {
  // 비디오 관련 상태
  VideoPlayerController? _videoController;
  String? _videoPath;
  String? _videoTitle;
  
  // 음성인식 및 요약 관련 상태
  bool _isRecognizing = false;
  bool _isSummarizing = false;
  List<WhisperSegment> _segments = [];
  String? _summary;
  int _recognizeSession = 0; // 동영상 변경 시 세션 증가
  List<int> _highlightedSegments = [];
  List<ThemeGroup> _themeGroups = [];
  String? _currentProjectPath; // 현재 프로젝트 파일 경로
  
  // 비디오 컨트롤 관련 상태
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  int _currentSegmentIndex = -1; // 현재 재생 중인 세그먼트 인덱스
  int? _editingSegmentIndex; // 텍스트 수정 중인 세그먼트 인덱스
  
  // 성능 최적화를 위한 UI 업데이트 제어
  DateTime _lastUpdateTime = DateTime.now();
  static const Duration _updateInterval = Duration(milliseconds: 100); // 100ms마다만 UI 업데이트
  
  // 요약 미리보기 관련 상태
  bool _isPreviewMode = false;
  int _currentPreviewSegmentIndex = 0;
  bool _isPreviewPlaying = false;
  bool _isPreviewTransitioning = false;
  
  // 요약 모드 전용 상태
  int _currentSummarySegmentIndex = 0; // 현재 재생 중인 요약 세그먼트 인덱스 (0부터 시작)
  List<int> _summarySegmentIndices = []; // 요약 세그먼트들의 원본 인덱스 목록
  Duration _totalSummaryDuration = Duration.zero; // 모든 요약 세그먼트의 총 재생 시간
  
  // 진행도 다이얼로그 관련 상태
  bool _isOperationCancelled = false;
  double _progress = 0.0;
  String _progressMessage = '';
  bool _isCancelled = false;
  
  // 요약 미리보기 관련 상태
  Timer? _previewTimer;
  StreamController<String>? _progressStreamController;
  
  // UI 컨트롤 관련 상태
  final ScrollController _segmentScrollController = ScrollController();
  final Map<int, GlobalKey> _segmentKeys = {};
  
  // UI 레이아웃 관련 상태
  double _leftPanelFlex = 1.5; // 왼쪽 패널 비율 (프리뷰 영역)
  double _rightPanelFlex = 3.5; // 오른쪽 패널 비율 (테이블 영역)
  bool _isDividerHovered = false; // 분할기 호버 상태
  bool _isDividerDragging = false; // 분할기 드래그 상태

  // Getters
  VideoPlayerController? get videoController => _videoController;
  String? get videoPath => _videoPath;
  String? get videoTitle => _videoTitle;
  bool get isRecognizing => _isRecognizing;
  bool get isSummarizing => _isSummarizing;
  List<WhisperSegment> get segments => _segments;
  String? get summary => _summary;
  int get recognizeSession => _recognizeSession;
  List<int> get highlightedSegments => _highlightedSegments;
  List<ThemeGroup> get themeGroups => _themeGroups;
  String? get currentProjectPath => _currentProjectPath;
  bool get isPlaying => _isPlaying;
  Duration get currentPosition => _currentPosition;
  Duration get totalDuration => _totalDuration;
  int get currentSegmentIndex => _currentSegmentIndex;
  int? get editingSegmentIndex => _editingSegmentIndex;
  DateTime get lastUpdateTime => _lastUpdateTime;
  Duration get updateInterval => _updateInterval;
  bool get isPreviewMode => _isPreviewMode;
  int get currentPreviewSegmentIndex => _currentPreviewSegmentIndex;
  bool get isPreviewPlaying => _isPreviewPlaying;
  bool get isPreviewTransitioning => _isPreviewTransitioning;
  
  // 요약 모드 전용 getter
  int get currentSummarySegmentIndex => _currentSummarySegmentIndex;
  List<int> get summarySegmentIndices => List.unmodifiable(_summarySegmentIndices);
  Duration get totalSummaryDuration => _totalSummaryDuration;
  bool get isOperationCancelled => _isOperationCancelled;
  
  // 작업 취소 상태 설정
  set isOperationCancelled(bool value) {
    _isOperationCancelled = value;
    notifyListeners();
  }
  double get progress => _progress;
  String get progressMessage => _progressMessage;
  bool get isCancelled => _isCancelled;
  Timer? get previewTimer => _previewTimer;
  StreamController<String>? get progressStreamController => _progressStreamController;
  ScrollController get segmentScrollController => _segmentScrollController;
  Map<int, GlobalKey> get segmentKeys => _segmentKeys;
  double get leftPanelFlex => _leftPanelFlex;
  double get rightPanelFlex => _rightPanelFlex;
  bool get isDividerHovered => _isDividerHovered;
  bool get isDividerDragging => _isDividerDragging;
  
  // UI 상수
  static const Color successColor = Colors.green;
  static const double borderRadius = 8.0;
  static const double smallBorderRadius = 6.0;
  static const double buttonBorderRadius = 16.0;

  // Setters with notifyListeners
  set videoController(VideoPlayerController? value) {
    _videoController = value;
    notifyListeners();
  }

  set videoPath(String? value) {
    _videoPath = value;
    notifyListeners();
  }

  set videoTitle(String? value) {
    _videoTitle = value;
    notifyListeners();
  }

  set isRecognizing(bool value) {
    _isRecognizing = value;
    notifyListeners();
  }

  set isSummarizing(bool value) {
    _isSummarizing = value;
    notifyListeners();
  }

  set segments(List<WhisperSegment> value) {
    _segments = value;
    notifyListeners();
  }

  set summary(String? value) {
    _summary = value;
    notifyListeners();
  }

  set recognizeSession(int value) {
    _recognizeSession = value;
    notifyListeners();
  }

  set highlightedSegments(List<int> value) {
    _highlightedSegments = value;
    notifyListeners();
  }

  set themeGroups(List<ThemeGroup> value) {
    _themeGroups = value;
    notifyListeners();
  }

  set currentProjectPath(String? value) {
    _currentProjectPath = value;
    notifyListeners();
  }

  set isPlaying(bool value) {
    _isPlaying = value;
    notifyListeners();
  }

  set currentPosition(Duration value) {
    _currentPosition = value;
    notifyListeners();
  }

  set totalDuration(Duration value) {
    _totalDuration = value;
    notifyListeners();
  }

  set currentSegmentIndex(int value) {
    _currentSegmentIndex = value;
    notifyListeners();
  }

  set editingSegmentIndex(int? value) {
    _editingSegmentIndex = value;
    notifyListeners();
  }

  set lastUpdateTime(DateTime value) {
    _lastUpdateTime = value;
    notifyListeners();
  }

  set isPreviewMode(bool value) {
    _isPreviewMode = value;
    if (value) {
      _updateSummarySegmentData();
    }
    notifyListeners();
  }
  
  set currentSummarySegmentIndex(int value) {
    _currentSummarySegmentIndex = value;
    notifyListeners();
  }

  set currentPreviewSegmentIndex(int value) {
    _currentPreviewSegmentIndex = value;
    notifyListeners();
  }

  set isPreviewPlaying(bool value) {
    _isPreviewPlaying = value;
    notifyListeners();
  }

  set isPreviewTransitioning(bool value) {
    _isPreviewTransitioning = value;
    notifyListeners();
  }

  set progress(double value) {
    _progress = value;
    notifyListeners();
  }

  set progressMessage(String value) {
    _progressMessage = value;
    notifyListeners();
  }

  set isCancelled(bool value) {
    _isCancelled = value;
    notifyListeners();
  }

  set leftPanelFlex(double value) {
    _leftPanelFlex = value;
    notifyListeners();
  }

  set rightPanelFlex(double value) {
    _rightPanelFlex = value;
    notifyListeners();
  }

  set isDividerHovered(bool value) {
    _isDividerHovered = value;
    notifyListeners();
  }

  set previewTimer(Timer? value) {
    _previewTimer = value;
    notifyListeners();
  }

  set progressStreamController(StreamController<String>? value) {
    _progressStreamController = value;
    notifyListeners();
  }

  set isDividerDragging(bool value) {
    _isDividerDragging = value;
    notifyListeners();
  }

  /// 상태 초기화
  void reset() {
    _videoController = null;
    _videoPath = null;
    _videoTitle = null;
    _isRecognizing = false;
    _isSummarizing = false;
    _segments = [];
    _summary = null;
    _recognizeSession = 0;
    _highlightedSegments = [];
    _themeGroups = [];
    _currentProjectPath = null;
    _isPlaying = false;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    _currentSegmentIndex = -1;
    _editingSegmentIndex = null;
    _lastUpdateTime = DateTime.now();
    _isPreviewMode = false;
    _currentPreviewSegmentIndex = 0;
    _isPreviewPlaying = false;
    _isPreviewTransitioning = false;
    _isOperationCancelled = false;
    _progress = 0.0;
    _progressMessage = '';
    _isCancelled = false;
    _leftPanelFlex = 1.5;
    _rightPanelFlex = 3.5;
    _isDividerHovered = false;
    _isDividerDragging = false;
    notifyListeners();
  }

  /// 비디오 관련 상태 초기화
  void resetVideoState() {
    _videoController = null;
    _videoPath = null;
    _videoTitle = null;
    _isPlaying = false;
    _currentPosition = Duration.zero;
    _totalDuration = Duration.zero;
    _currentSegmentIndex = -1;
    _editingSegmentIndex = null;
    notifyListeners();
  }

  /// 음성인식 관련 상태 초기화
  void resetRecognitionState() {
    _isRecognizing = false;
    _segments = [];
    _recognizeSession++;
    _highlightedSegments = [];
    _themeGroups = [];
    notifyListeners();
  }

  /// 요약 관련 상태 초기화
  void resetSummaryState() {
    _isSummarizing = false;
    _summary = null;
    _isPreviewMode = false;
    _currentPreviewSegmentIndex = 0;
    _isPreviewPlaying = false;
    _isPreviewTransitioning = false;
    notifyListeners();
  }
  
  /// 세그먼트 업데이트 (FFmpegService에서 사용)
  void updateSegments(List<Map<String, dynamic>> segmentsData) {
    _segments = segmentsData.map((data) => WhisperSegment(
      id: data['id'],
      startSec: data['startSeconds'],
      endSec: data['endSeconds'],
      text: data['text'],
    )).toList();
    
    // 음성인식 완료 상태로 변경
    _isRecognizing = false;
    _recognizeSession++;
    
    notifyListeners();
  }
  
  /// 챕터 정보 업데이트 (FFmpegService에서 사용)
  void updateThemeGroups(List<Map<String, dynamic>> themeGroupsData) {
    _themeGroups = themeGroupsData.map((data) => ThemeGroup(
      theme: data['theme'],
      segments: data['segments'].map((s) => WhisperSegment(
        id: s['id'],
        startSec: s['startSeconds'],
        endSec: s['endSeconds'],
        text: s['text'],
      )).toList(),
      summary: data['description'],
    )).toList();
    
    notifyListeners();
  }
  
  /// 프로그레스 다이얼로그 표시
  void showProgressDialog(String title, String initialMessage) {
    _progressMessage = initialMessage;
    _progress = 0.0;
    _isCancelled = false;
    notifyListeners();
  }
  
  /// 프로그레스 다이얼로그 업데이트
  void updateProgress(String message) {
    _progressMessage = message;
    _progress += 0.1; // 진행도 증가
    if (_progress > 1.0) _progress = 1.0;
    notifyListeners();
  }
  
  /// 프로그레스 다이얼로그 닫기
  void closeProgressDialog() {
    _progressMessage = '';
    _progress = 0.0;
    _isCancelled = false;
    notifyListeners();
  }
  
  // 요약 세그먼트 데이터 업데이트
  void _updateSummarySegmentData() {
    _summarySegmentIndices.clear();
    _totalSummaryDuration = Duration.zero;
    _currentSummarySegmentIndex = 0;
    
    // 요약 세그먼트 인덱스 수집
    for (int i = 0; i < _segments.length; i++) {
      final segment = _segments[i];
      final isHighlighted = _highlightedSegments.contains(segment.id);
      final isSummarySegment = segment.isSummary ?? false;
      
      if (isHighlighted || isSummarySegment) {
        _summarySegmentIndices.add(i);
        // 세그먼트 지속 시간 계산하여 총 시간에 추가
        final duration = Duration(
          milliseconds: ((segment.endSec - segment.startSec) * 1000).round(),
        );
        _totalSummaryDuration += duration;
      }
    }
    
    print('📊 요약 세그먼트 업데이트: ${_summarySegmentIndices.length}개, 총 시간: ${_formatDuration(_totalSummaryDuration)}');
  }
  
  // 현재 재생 중인 세그먼트가 몇 번째 요약 세그먼트인지 찾기
  void updateCurrentSummarySegmentIndex(int currentSegmentIndex) {
    if (!_isPreviewMode) return;
    
    final summaryIndex = _summarySegmentIndices.indexOf(currentSegmentIndex);
    if (summaryIndex >= 0 && summaryIndex != _currentSummarySegmentIndex) {
      _currentSummarySegmentIndex = summaryIndex;
      notifyListeners();
    }
  }
  
  // 시간 포맷팅 헬퍼
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  
  /// 세그먼트를 특정 단어 앞에서 분할
  /// [segmentIndex]: 분할할 세그먼트의 인덱스
  /// [wordIndex]: 분할 기준이 되는 단어의 인덱스 (이 단어부터 새 세그먼트로)
  /// 반환: 성공 여부
  bool splitSegmentAtWord(int segmentIndex, int wordIndex) {
    if (segmentIndex < 0 || segmentIndex >= _segments.length) {
      print('❌ 잘못된 세그먼트 인덱스: $segmentIndex');
      return false;
    }
    
    final segment = _segments[segmentIndex];
    if (wordIndex < 0 || wordIndex >= segment.words.length) {
      print('❌ 잘못된 단어 인덱스: $wordIndex (세그먼트 단어 수: ${segment.words.length})');
      return false;
    }
    
    // 첫 번째 세그먼트: 원본 시작 ~ 분할 단어 직전까지
    final firstWords = segment.words.sublist(0, wordIndex);
    final firstSilences = <SilenceSegment>[];
    
    // 두 번째 세그먼트: 분할 단어 ~ 원본 끝까지
    final secondWords = segment.words.sublist(wordIndex);
    final secondSilences = <SilenceSegment>[];
    
    // 무음 구간 재분배: 분할 시간 결정
    // firstWords가 비어있으면 세그먼트 시작부터, 아니면 마지막 단어 끝까지
    final splitTime = firstWords.isEmpty 
        ? segment.startSec 
        : firstWords.last.endSec;
    for (final silence in segment.silences) {
      if (silence.endSec <= splitTime) {
        firstSilences.add(silence);
      } else if (silence.startSec >= splitTime) {
        secondSilences.add(silence);
      } else {
        // 무음이 분할 지점을 걸치는 경우: 분할
        firstSilences.add(SilenceSegment(
          startSec: silence.startSec,
          endSec: splitTime,
          duration: splitTime - silence.startSec,
        ));
        secondSilences.add(SilenceSegment(
          startSec: splitTime,
          endSec: silence.endSec,
          duration: silence.endSec - splitTime,
        ));
      }
    }
    
    // 첫 번째 세그먼트 생성 (기존 ID 유지)
    // 단어가 없으면 무음만 있는 세그먼트
    final firstSegment = WhisperSegment(
      id: segment.id,
      startSec: segment.startSec,
      endSec: firstWords.isEmpty ? splitTime : splitTime,
      text: firstWords.isEmpty ? '' : firstWords.map((w) => w.word).join(' '),
      words: firstWords,
      silences: firstSilences,
      isSummary: segment.isSummary,
    );
    
    // 두 번째 세그먼트 생성 (새 ID: 기존 ID + 1)
    final secondSegment = WhisperSegment(
      id: segment.id + 1,
      startSec: splitTime,
      endSec: segment.endSec,
      text: secondWords.map((w) => w.word).join(' '),
      words: secondWords,
      silences: secondSilences,
      isSummary: segment.isSummary,
    );
    
    // 세그먼트 목록 업데이트
    _segments[segmentIndex] = firstSegment;
    _segments.insert(segmentIndex + 1, secondSegment);
    
    // 이후 세그먼트들의 ID 재조정
    for (int i = segmentIndex + 2; i < _segments.length; i++) {
      final seg = _segments[i];
      _segments[i] = WhisperSegment(
        id: i + 1,
        startSec: seg.startSec,
        endSec: seg.endSec,
        text: seg.text,
        words: seg.words,
        silences: seg.silences,
        isSummary: seg.isSummary,
      );
    }
    
    print('✂️ 세그먼트 #${segment.id} 분할 완료: "${segment.text}" → "${firstSegment.text}" | "${secondSegment.text}"');
    
    notifyListeners();
    return true;
  }
  
  /// 여러 세그먼트를 하나로 병합
  /// [segmentIndices]: 병합할 세그먼트들의 인덱스 목록 (정렬된 상태로 전달)
  /// 반환: 성공 여부
  bool mergeSegments(List<int> segmentIndices) {
    if (segmentIndices.length < 2) {
      print('❌ 병합하려면 최소 2개 이상의 세그먼트가 필요합니다.');
      return false;
    }
    
    // 정렬 및 유효성 검사
    final sortedIndices = segmentIndices.toList()..sort();
    for (final index in sortedIndices) {
      if (index < 0 || index >= _segments.length) {
        print('❌ 잘못된 세그먼트 인덱스: $index');
        return false;
      }
    }
    
    // 연속된 세그먼트인지 확인
    for (int i = 0; i < sortedIndices.length - 1; i++) {
      if (sortedIndices[i + 1] != sortedIndices[i] + 1) {
        print('❌ 병합할 세그먼트들이 연속되어 있지 않습니다.');
        return false;
      }
    }
    
    final firstIndex = sortedIndices.first;
    final lastIndex = sortedIndices.last;
    
    // 병합할 세그먼트들 수집
    final segmentsToMerge = sortedIndices.map((i) => _segments[i]).toList();
    
    // 모든 단어와 무음 합치기
    final allWords = <WordSegment>[];
    final allSilences = <SilenceSegment>[];
    
    for (final segment in segmentsToMerge) {
      allWords.addAll(segment.words);
      allSilences.addAll(segment.silences);
    }
    
    // 시간순 정렬
    allWords.sort((a, b) => a.startSec.compareTo(b.startSec));
    allSilences.sort((a, b) => a.startSec.compareTo(b.startSec));
    
    // 병합된 세그먼트 생성
    final mergedSegment = WhisperSegment(
      id: segmentsToMerge.first.id,
      startSec: segmentsToMerge.first.startSec,
      endSec: segmentsToMerge.last.endSec,
      text: allWords.map((w) => w.word).join(' '),
      words: allWords,
      silences: allSilences,
      isSummary: segmentsToMerge.any((s) => s.isSummary == true),
    );
    
    // 세그먼트 목록 업데이트
    _segments[firstIndex] = mergedSegment;
    _segments.removeRange(firstIndex + 1, lastIndex + 1);
    
    // 이후 세그먼트들의 ID 재조정
    for (int i = firstIndex + 1; i < _segments.length; i++) {
      final seg = _segments[i];
      _segments[i] = WhisperSegment(
        id: i + 1,
        startSec: seg.startSec,
        endSec: seg.endSec,
        text: seg.text,
        words: seg.words,
        silences: seg.silences,
        isSummary: seg.isSummary,
      );
    }
    
    print('📦 세그먼트 병합 완료: ${segmentIndices.length}개 → 1개 "${mergedSegment.text.substring(0, mergedSegment.text.length > 50 ? 50 : mergedSegment.text.length)}..."');
    
    notifyListeners();
    return true;
  }
} 