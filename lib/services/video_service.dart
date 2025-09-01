import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import '../models/app_state.dart';
import '../models/whisper_segment.dart';
import '../models/theme_group.dart';
// TODO: constants import는 현재 사용되지 않음

class VideoService {
  final AppState appState;
  
  VideoService(this.appState);
  

  
  // 비디오 파일 선택
  Future<void> pickVideo() async {
    // 즉시 실행되는 로그 (메서드 호출 확인용)
    print('🚀 pickVideo 메서드가 호출되었습니다!');
    
    try {
      print('=== pickVideo 시작 ===');
      
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        dialogTitle: '동영상 파일 선택',
      );

      if (result != null && result.files.single.path != null) {
        final videoPath = result.files.single.path!;
        final videoTitle = result.files.single.name;
        
        print('✅ 동영상 파일 선택됨: $videoTitle');
        print('📁 경로: $videoPath');
        
        // 정상적인 동영상 로드 처리
        print('🎬 동영상 로드 시작...');
        
        try {
          // 기존 비디오 컨트롤러 정리
          if (appState.videoController != null) {
            print('🧹 기존 비디오 컨트롤러 정리 중...');
            appState.videoController!.dispose();
            appState.videoController = null;
          }
          
          // 요약 미리보기 타이머 정리
          if (appState.previewTimer != null) {
            print('⏰ 기존 타이머 정리 중...');
            appState.previewTimer!.cancel();
          }
          
          // 새로운 비디오 컨트롤러 생성 및 초기화
          print('🔧 새로운 비디오 컨트롤러 생성 중...');
          final controller = VideoPlayerController.file(
            File(videoPath),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: false,
              allowBackgroundPlayback: false,
            ),
          );
          
          print('⏳ 비디오 컨트롤러 초기화 중...');
          await controller.initialize();
          print('✅ 비디오 컨트롤러 초기화 완료!');
          
          // 볼륨 설정 및 첫 프레임 표시 준비
          await controller.setVolume(1.0);
          
          // 첫 프레임(00:00) 위치로 설정하여 프리뷰에 첫 화면이 바로 보이도록 함
          print('🎬 첫 프레임으로 이동 중...');
          await controller.seekTo(Duration.zero);
          
          // 프레임 렌더링을 위해 매우 짧은 재생 후 즉시 일시정지
          await controller.play();
          await Future.delayed(const Duration(milliseconds: 50));
          await controller.pause();
          await controller.seekTo(Duration.zero);
          print('✅ 첫 프레임 강제 렌더링 완료!');
          
          // AppState 업데이트
          print('🔄 AppState 업데이트 중...');
          appState.videoController = controller;
          appState.videoPath = videoPath;
          appState.videoTitle = videoTitle;
          appState.currentPosition = Duration.zero;
          appState.totalDuration = controller.value.duration;
          appState.isPlaying = false;
          appState.currentSegmentIndex = -1;
          appState.editingSegmentIndex = null;
          
          // 요약 미리보기 모드 초기화
          appState.isPreviewMode = false;
          appState.currentPreviewSegmentIndex = 0;
          appState.isPreviewPlaying = false;
          appState.isPreviewTransitioning = false;
          
          print('✅ 동영상 로드 완료!');
          print('📊 동영상 정보:');
          print('   - 제목: $videoTitle');
          print('   - 길이: ${appState.totalDuration}');
          print('   - 경로: $videoPath');
          
          // UI 업데이트를 위한 notifyListeners 호출
          print('🔗 VideoService: AppState notifyListeners 호출');
          print('   - AppState 인스턴스 ID: ${appState.hashCode}');
          appState.notifyListeners();
          print('🔄 UI 업데이트 완료');
          
        } catch (e) {
          print('❌ 동영상 로드 중 오류 발생: $e');
          print('📋 오류 스택: ${StackTrace.current}');
          
          // 사용자에게 오류 알림
          ScaffoldMessenger.of(navigatorKey.currentContext!).showSnackBar(
            SnackBar(
              content: Text('동영상 로드 중 오류가 발생했습니다: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        print('❌ 동영상 파일이 선택되지 않았습니다.');
      }
    } catch (e) {
      print('pickVideo 중 오류 발생: $e');
      print('📋 오류 스택: ${StackTrace.current}');
    }
  }
  
  // 비디오 재생/일시정지 토글
  void togglePlayPause() {
    if (appState.videoController != null && appState.videoController!.value.isInitialized) {
      if (appState.videoController!.value.isPlaying) {
        appState.videoController!.pause();
        appState.isPlaying = false;
        print('⏸️ 재생 일시정지');
      } else {
        // 요약 모드일 때는 첫 번째 요약 세그먼트로 이동 후 재생
        if (appState.isPreviewMode) {
          print('🎯 요약 모드 재생 시작');
          _playFirstSummarySegment();
        } else {
          appState.videoController!.play();
          appState.isPlaying = true;
          print('▶️ 전체 모드 재생 시작');
        }
      }
    }
  }
  
  // 첫 번째 요약 세그먼트 재생
  void _playFirstSummarySegment() {
    final firstSummaryIndex = _findNextSummarySegment(0);
    
    if (firstSummaryIndex >= 0) {
      final firstSegment = appState.segments[firstSummaryIndex];
      appState.currentSegmentIndex = firstSummaryIndex;
      appState.updateCurrentSummarySegmentIndex(firstSummaryIndex);
      
      // 첫 번째 요약 세그먼트로 이동
      final startPosition = Duration(milliseconds: (firstSegment.startSec * 1000).round());
      seekTo(startPosition);
      
      // 재생 시작
      appState.videoController!.play();
      appState.isPlaying = true;
      
      print('🎯 첫 번째 요약 세그먼트 ${firstSummaryIndex + 1} 재생 시작 (ID: ${firstSegment.id})');
      
      // 해당 세그먼트가 끝나면 다음 요약 세그먼트로 이동하도록 타이머 설정
      _scheduleNextSummarySegment(firstSummaryIndex, firstSegment);
    } else {
      print('❌ 요약 세그먼트가 없습니다');
    }
  }
  
  // 다음 요약 세그먼트로 이동 스케줄링
  void _scheduleNextSummarySegment(int currentIndex, segment) {
    final segmentDuration = segment.endSec - segment.startSec;
    final playDuration = Duration(milliseconds: (segmentDuration * 1000 * 0.95).round()); // 95% 재생 후 이동
    
    Timer(playDuration, () {
      if (!appState.isPreviewMode || !appState.isPlaying) return;
      
      final nextSummaryIndex = _findNextSummarySegment(currentIndex + 1);
      
      if (nextSummaryIndex >= 0) {
        final nextSegment = appState.segments[nextSummaryIndex];
        appState.currentSegmentIndex = nextSummaryIndex;
        appState.updateCurrentSummarySegmentIndex(nextSummaryIndex);
        
        // 다음 요약 세그먼트로 이동
        final nextPosition = Duration(milliseconds: (nextSegment.startSec * 1000).round());
        seekTo(nextPosition);
        
        print('🎯 다음 요약 세그먼트 ${nextSummaryIndex + 1}로 이동 (ID: ${nextSegment.id})');
        
        // 다음 세그먼트도 스케줄링
        _scheduleNextSummarySegment(nextSummaryIndex, nextSegment);
      } else {
        // 모든 요약 세그먼트 재생 완료
        appState.videoController!.pause();
        appState.isPlaying = false;
        print('✅ 모든 요약 세그먼트 재생 완료');
      }
    });
  }
  
  // 특정 위치로 이동
  void seekTo(Duration position) {
    if (appState.videoController != null && appState.videoController!.value.isInitialized) {
      appState.videoController!.seekTo(position);
    }
  }
  
  // 현재 세그먼트 업데이트
  void updateCurrentSegment() {
    if (appState.videoController == null || appState.segments.isEmpty) return;
    
    final currentTime = appState.videoController!.value.position.inMilliseconds / 1000.0;
    
    // 요약 모드에서는 더 적극적인 세그먼트 관리
    if (appState.isPreviewMode && appState.isPlaying) {
      _handleSummaryModePlayback(currentTime);
      return;
    }
    
    // 일반 모드에서의 세그먼트 업데이트
    int newIndex = -1;
    for (int i = 0; i < appState.segments.length; i++) {
      final segment = appState.segments[i];
      if (currentTime >= segment.startSec && currentTime <= segment.endSec) {
        newIndex = i;
        break;
      }
    }
    
    if (newIndex != appState.currentSegmentIndex) {
      appState.currentSegmentIndex = newIndex;
    }
  }
  
  // 요약 모드 전용 재생 관리
  void _handleSummaryModePlayback(double currentTime) {
    // 현재 재생 위치가 속한 세그먼트 찾기
    int currentSegmentIndex = -1;
    for (int i = 0; i < appState.segments.length; i++) {
      final segment = appState.segments[i];
      if (currentTime >= segment.startSec && currentTime <= segment.endSec) {
        currentSegmentIndex = i;
        break;
      }
    }
    
    if (currentSegmentIndex >= 0) {
      final currentSegment = appState.segments[currentSegmentIndex];
      final isHighlighted = appState.highlightedSegments.contains(currentSegment.id);
      final isSummarySegment = currentSegment.isSummary ?? false;
      
      print('🔍 요약 모드 재생 관리: 세그먼트 ${currentSegmentIndex + 1}, 하이라이트=$isHighlighted, 요약=$isSummarySegment, 시간=${currentTime.toStringAsFixed(1)}s');
      
      // 현재 세그먼트가 요약 세그먼트인지 확인
      if (isHighlighted || isSummarySegment) {
        // 요약 세그먼트 - 정상 재생 계속
        if (appState.currentSegmentIndex != currentSegmentIndex) {
          appState.currentSegmentIndex = currentSegmentIndex;
          appState.updateCurrentSummarySegmentIndex(currentSegmentIndex);
          print('✅ 요약 세그먼트 ${currentSegmentIndex + 1} 정상 재생 중');
        }
        
        // 세그먼트 재생 완료 체크
        _checkSummarySegmentCompletion(currentSegmentIndex, currentTime);
      } else {
        // 요약 세그먼트가 아님 - 즉시 다음 요약 세그먼트로 건너뛰기
        print('⚠️ 요약 모드에서 비요약 세그먼트 ${currentSegmentIndex + 1} 감지 - 강제 건너뛰기');
        
        // 즉시 건너뛰기 (딜레이 없이)
        final nextSummaryIndex = _findNextSummarySegment(currentSegmentIndex + 1);
        
        if (nextSummaryIndex >= 0) {
          final nextSegment = appState.segments[nextSummaryIndex];
          appState.currentSegmentIndex = nextSummaryIndex;
          appState.updateCurrentSummarySegmentIndex(nextSummaryIndex);
          
          final newPosition = Duration(milliseconds: (nextSegment.startSec * 1000).round());
          seekTo(newPosition);
          
          print('🎯 요약 모드: 세그먼트 ${nextSummaryIndex + 1}로 즉시 건너뛰기 (ID: ${nextSegment.id})');
        } else {
          // 더 이상 요약 세그먼트가 없으면 재생 중지
          appState.videoController!.pause();
          appState.isPlaying = false;
          print('✅ 모든 요약 세그먼트 재생 완료');
        }
      }
    }
  }
  
  // 세그먼트로 이동
  void seekToSegment(int segmentIndex) {
    if (segmentIndex >= 0 && segmentIndex < appState.segments.length) {
      final segment = appState.segments[segmentIndex];
      
      // 프리뷰 모드인 경우 처리
      if (appState.isPreviewMode) {
        // TODO: 요약 세그먼트 처리
        return;
      }
      
      // 일반 모드에서 세그먼트로 이동
      final startPosition = Duration(milliseconds: (segment.startSec * 1000).toInt());
      seekTo(startPosition);
      appState.currentSegmentIndex = segmentIndex;
    }
  }
  
  // 요약 미리보기 시작
  void startSummaryPreview() {
    if (appState.segments.isEmpty) return;
    
    // 현재 재생 위치 저장
    final currentTime = appState.videoController?.value.position.inMilliseconds ?? 0;
    
    appState.previewTimer?.cancel();
    
    appState.isPreviewMode = true;
    appState.isPreviewPlaying = false;
    appState.currentPreviewSegmentIndex = 0;
    appState.isPreviewTransitioning = false;
    
    // 현재 위치 유지
    if (appState.videoController != null) {
      appState.videoController!.seekTo(Duration(milliseconds: currentTime));
    }
    
    appState.videoController?.pause();
  }
  
  // 요약 미리보기 정지
  void stopSummaryPreview() {
    // 현재 재생 위치 유지
    final currentTime = appState.videoController?.value.position.inMilliseconds ?? 0;
    
    appState.previewTimer?.cancel();
    
    appState.isPreviewMode = false;
    appState.isPreviewPlaying = false;
    appState.currentPreviewSegmentIndex = 0;
    appState.isPreviewTransitioning = false;
    
    // 현재 위치 유지
    if (appState.videoController != null) {
      appState.videoController!.seekTo(Duration(milliseconds: currentTime));
    }
    
    appState.videoController?.pause();
  }
  
  // 요약 미리보기 재생/일시정지
  void pauseResumePreview() {
    if (appState.isPreviewTransitioning) return;
    
    if (appState.isPreviewPlaying) {
      appState.videoController?.pause();
      appState.previewTimer?.cancel();
      appState.isPreviewPlaying = false;
    } else {
      appState.videoController?.play();
      // TODO: 현재 세그먼트 모니터링 재시작
      appState.isPreviewPlaying = true;
    }
  }
  
  // 다음 요약 세그먼트로 이동
  void nextPreviewSegment() {
    // TODO: 요약 세그먼트 리스트 구현
    if (appState.currentPreviewSegmentIndex < 0) {
      appState.currentPreviewSegmentIndex = 0;
    }
  }
  
  // 이전 요약 세그먼트로 이동
  void previousPreviewSegment() {
    if (appState.currentPreviewSegmentIndex > 0) {
      appState.currentPreviewSegmentIndex--;
    }
  }
  
  // 특정 요약 세그먼트로 이동
  void jumpToPreviewSegment(int index) {
    if (index >= 0 && index < appState.segments.length) {
      playPreviewSegment(index);
    }
  }
  
  // 요약 세그먼트 재생
  Future<void> playPreviewSegment(int index) async {
    if (index < 0 || index >= appState.segments.length) {
      return;
    }
    
    // 전환 중이면 대기
    if (appState.isPreviewTransitioning) {
      return;
    }

    // 기존 타이머 정리
    appState.previewTimer?.cancel();
    
    appState.isPreviewTransitioning = true;
    appState.currentPreviewSegmentIndex = index;

    final segment = appState.segments[index];
    
    try {
      // 정확한 시작 지점으로 이동 (밀리초 단위)
      final startPosition = Duration(milliseconds: (segment.startSec * 1000).toInt());
      await appState.videoController!.seekTo(startPosition);
      
      // 잠시 대기 후 재생 시작
      await Future.delayed(const Duration(milliseconds: 100));
      
      if (appState.isPreviewMode) {
        await appState.videoController!.play();
        
        appState.isPreviewPlaying = true;
        appState.isPreviewTransitioning = false;

        // 세그먼트 종료 시점 모니터링 시작
        startSegmentMonitoring(segment, index);
      }
    } catch (e) {
      print('세그먼트 재생 오류: $e');
      appState.isPreviewTransitioning = false;
    }
  }
  
  // 요약 세그먼트로 이동
  Future<void> seekToPreviewSegment(int index) async {
    // TODO: 요약 세그먼트 이동 구현
  }
  
  // 세그먼트 모니터링 시작
  void startSegmentMonitoring(WhisperSegment segment, int index) {
    const checkInterval = Duration(milliseconds: 100); // 100ms마다 확인
    final endTime = segment.endSec;
    
    appState.previewTimer = Timer.periodic(checkInterval, (timer) {
      if (!appState.isPreviewMode || appState.isPreviewTransitioning) {
        timer.cancel();
        return;
      }

      final currentTime = appState.videoController?.value.position.inMilliseconds ?? 0;
      final currentSeconds = currentTime / 1000.0;

      // 세그먼트 끝에 도달했는지 확인 (50ms 여유)
      if (currentSeconds >= endTime - 0.05) {
        timer.cancel();
        
        // 다음 세그먼트로 이동
        if (index < appState.segments.length - 1) {
          playPreviewSegment(index + 1);
        } else {
          // 모든 세그먼트 완료
          stopSummaryPreview();
        }
      }
    });
  }
  
  // 비디오 리스너 (성능 최적화)
  void optimizedVideoListener() {
    if (appState.videoController == null || !appState.videoController!.value.isInitialized) return;
    
    final now = DateTime.now();
    if (now.difference(appState.lastUpdateTime) < appState.updateInterval) {
      // 업데이트 간격이 너무 짧으면 건너뛰기
      return;
    }
    
    appState.lastUpdateTime = now;
    
    final newPosition = appState.videoController!.value.position;
    final newDuration = appState.videoController!.value.duration;
    final newIsPlaying = appState.videoController!.value.isPlaying;
    
    // 실제 값이 변경되었을 때만 업데이트
    if (newPosition != appState.currentPosition || 
        newDuration != appState.totalDuration || 
        newIsPlaying != appState.isPlaying) {
      appState.currentPosition = newPosition;
      appState.totalDuration = newDuration;
      appState.isPlaying = newIsPlaying;
      updateCurrentSegment();
    }
  }

  // 자동 처리 시작 (동영상 로드 후)
  Future<void> _startAutoProcessing() async {
    try {
      print('=== 자동 처리 시작 ===');
      
      // 임시로 자동 처리 비활성화 (테스트용)
      print('자동 처리가 임시로 비활성화되었습니다. (테스트 중)');
      return;
      
      // 1단계: 오디오 추출
      print('1단계: 오디오 추출 시작');
      final audioPath = await _extractAudio();
      
      // 2단계: 음성인식 시작
      print('2단계: 음성인식 시작');
      await _startSpeechRecognition(audioPath);
      
      print('=== 자동 처리 완료 ===');
    } catch (e) {
      print('자동 처리 중 오류 발생: $e');
    }
  }

  // 오디오 추출
  Future<String> _extractAudio() async {
    if (appState.videoPath == null) throw Exception('비디오 경로가 없습니다.');
    
    final audioPath = '${Directory.systemTemp.path}/extracted_audio.wav';
    print('오디오 추출 경로: $audioPath');
    
    // 기존 오디오 파일 삭제
    if (File(audioPath).existsSync()) {
      File(audioPath).deleteSync();
    }
    
    // FFmpeg로 오디오 추출
    final result = await Process.run(
      'ffmpeg',
      ['-i', appState.videoPath!, '-vn', '-acodec', 'pcm_s16le', '-ar', '16000', '-ac', '1', audioPath],
    );
    
    if (result.exitCode != 0) {
      throw Exception('오디오 추출 실패: ${result.stderr}');
    }
    
    print('오디오 추출 완료: $audioPath');
    return audioPath;
  }

  // 음성인식 시작
  Future<void> _startSpeechRecognition(String audioPath) async {
    // AIService를 통해 음성인식 시작
    // TODO: AIService 인스턴스에 접근하는 방법 필요
    print('음성인식 시작 예정: $audioPath');
  }

  // 요약 세그먼트만 재생 시작
  void _startSummaryOnlyPlayback() {
    // 현재 위치에서 가장 가까운 요약 세그먼트 찾기
    final currentIndex = appState.currentSegmentIndex >= 0 ? appState.currentSegmentIndex : 0;
    final nextSummaryIndex = _findNextSummarySegment(currentIndex);
    
    if (nextSummaryIndex >= 0) {
      // 요약 세그먼트로 이동
      final segment = appState.segments[nextSummaryIndex];
      appState.currentSegmentIndex = nextSummaryIndex;
      seekTo(Duration(milliseconds: (segment.startSec * 1000).round()));
      
      // 재생 시작
      appState.videoController!.play();
      appState.isPlaying = true;
      
      print('🎯 요약 모드: 세그먼트 ${nextSummaryIndex + 1} 재생 시작 (ID: ${segment.id})');
    } else {
      // 요약 세그먼트가 없으면 알림
      print('⚠️ 요약 세그먼트가 없습니다.');
    }
  }

  // 다음 요약 세그먼트 찾기
  int _findNextSummarySegment(int startIndex) {
    print('🔍 ${startIndex}부터 요약 세그먼트 검색 시작');
    print('📊 전체 세그먼트 수: ${appState.segments.length}');
    print('🎯 하이라이트된 세그먼트: ${appState.highlightedSegments}');
    
    for (int i = startIndex; i < appState.segments.length; i++) {
      final segment = appState.segments[i];
      final isHighlighted = appState.highlightedSegments.contains(segment.id);
      final isSummarySegment = segment.isSummary ?? false;
      
      print('  세그먼트 ${i + 1}: ID=${segment.id}, 하이라이트=$isHighlighted, 요약=$isSummarySegment');
      
      if (isHighlighted || isSummarySegment) {
        print('✅ 요약 세그먼트 발견: 인덱스 $i');
        return i;
      }
    }
    
    print('🔄 처음부터 다시 검색');
    // 처음부터 다시 찾기
    for (int i = 0; i < startIndex; i++) {
      final segment = appState.segments[i];
      final isHighlighted = appState.highlightedSegments.contains(segment.id);
      final isSummarySegment = segment.isSummary ?? false;
      
      print('  세그먼트 ${i + 1}: ID=${segment.id}, 하이라이트=$isHighlighted, 요약=$isSummarySegment');
      
      if (isHighlighted || isSummarySegment) {
        print('✅ 요약 세그먼트 발견: 인덱스 $i');
        return i;
      }
    }
    
    print('❌ 요약 세그먼트를 찾을 수 없음');
    return -1; // 요약 세그먼트가 없음
  }

    // 요약 세그먼트 재생 완료 감지 및 다음 세그먼트로 이동
  void _checkSummarySegmentCompletion(int currentIndex, double currentTime) {
    if (currentIndex < 0 || currentIndex >= appState.segments.length) return;

    final currentSegment = appState.segments[currentIndex];
    final isHighlighted = appState.highlightedSegments.contains(currentSegment.id);
    final isSummarySegment = currentSegment.isSummary ?? false;

    // 현재 세그먼트가 요약 세그먼트이고, 재생이 거의 끝났는지 확인
    if (isHighlighted || isSummarySegment) {
      final segmentDuration = currentSegment.endSec - currentSegment.startSec;
      final playedDuration = currentTime - currentSegment.startSec;
      final completionRatio = playedDuration / segmentDuration;

      print('📊 요약 세그먼트 ${currentIndex + 1} 진행률: ${(completionRatio * 100).toStringAsFixed(1)}%');

      // 세그먼트의 90% 이상 재생되었으면 다음 요약 세그먼트로 이동 (더 빠른 전환)
      if (completionRatio >= 0.90) {
        print('🎬 요약 세그먼트 ${currentIndex + 1} 재생 완료 (${(completionRatio * 100).toStringAsFixed(1)}%)');

        final nextSummaryIndex = _findNextSummarySegment(currentIndex + 1);

        if (nextSummaryIndex >= 0) {
          final nextSegment = appState.segments[nextSummaryIndex];
          appState.currentSegmentIndex = nextSummaryIndex;
          appState.updateCurrentSummarySegmentIndex(nextSummaryIndex);
          
          final newPosition = Duration(milliseconds: (nextSegment.startSec * 1000).round());
          seekTo(newPosition);

          print('🎯 다음 요약 세그먼트 ${nextSummaryIndex + 1}로 자동 이동 (ID: ${nextSegment.id})');
        } else {
          // 더 이상 요약 세그먼트가 없으면 재생 중지
          appState.videoController!.pause();
          appState.isPlaying = false;
          print('✅ 모든 요약 세그먼트 재생 완료');
        }
      }
    }
  }

  // 현재 세그먼트가 요약 세그먼트가 아니면 다음 요약 세그먼트로 건너뛰기
  void _checkAndSkipToNextSummarySegment(int currentIndex) {
    if (currentIndex < 0 || currentIndex >= appState.segments.length) return;
    
    final currentSegment = appState.segments[currentIndex];
    final isHighlighted = appState.highlightedSegments.contains(currentSegment.id);
    final isSummarySegment = currentSegment.isSummary ?? false;
    
    print('🔍 세그먼트 ${currentIndex + 1} 체크: ID=${currentSegment.id}, 하이라이트=$isHighlighted, 요약=$isSummarySegment');
    
    // 현재 세그먼트가 요약 세그먼트가 아니면 **즉시** 다음 요약 세그먼트로 건너뛰기
    if (!isHighlighted && !isSummarySegment) {
      print('⏭️ 요약 세그먼트가 아니므로 즉시 건너뛰기');
      
      // 즉시 건너뛰기 위해 딜레이 추가
      Future.delayed(Duration(milliseconds: 50), () {
        if (!appState.isPreviewMode || !appState.isPlaying) return;
        
        final nextSummaryIndex = _findNextSummarySegment(currentIndex + 1);
        
        if (nextSummaryIndex >= 0) {
          final nextSegment = appState.segments[nextSummaryIndex];
          appState.currentSegmentIndex = nextSummaryIndex;
          seekTo(Duration(milliseconds: (nextSegment.startSec * 1000).round()));
          
          print('🎯 요약 모드: 세그먼트 ${nextSummaryIndex + 1}로 강제 건너뛰기 (ID: ${nextSegment.id})');
          
          // 요약 세그먼트 인덱스도 업데이트
          appState.updateCurrentSummarySegmentIndex(nextSummaryIndex);
        } else {
          // 더 이상 요약 세그먼트가 없으면 재생 중지
          appState.videoController!.pause();
          appState.isPlaying = false;
          print('✅ 모든 요약 세그먼트 재생 완료');
        }
      });
    } else {
      print('✅ 요약 세그먼트이므로 계속 재생');
    }
  }
}

// 전역 네비게이터 키 (임시로 여기에 정의)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>(); 