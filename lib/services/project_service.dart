import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as path;
import '../models/app_state.dart';
import '../models/whisper_segment.dart';
import '../models/theme_group.dart';
import '../models/project_data.dart';
// TODO: constants import는 현재 사용되지 않음

class ProjectService {
  final AppState appState;
  
  ProjectService(this.appState);
  
  // 프로젝트 저장
  Future<void> saveProject() async {
    if (appState.videoPath == null || appState.segments.isEmpty) {
      // TODO: ScaffoldMessenger 처리 - context가 필요함
      return;
    }

    String? savePath;
    if (appState.currentProjectPath != null) {
          // 기존 프로젝트가 있으면 같은 경로에 저장
      savePath = appState.currentProjectPath;
        } else {
          // 새로 저장
          savePath = await FilePicker.platform.saveFile(
            dialogTitle: '프로젝트 저장',
        fileName: '${path.basenameWithoutExtension(appState.videoPath!)}.bcproj',
            type: FileType.custom,
            allowedExtensions: ['bcproj'],
          );
        }

    if (savePath != null) {
      try {
        final projectData = ProjectData(
          videoPath: appState.videoPath!,
          segments: appState.segments,
          summarySegments: appState.segments.where((s) => appState.highlightedSegments.contains(s.id)).toList(),
          appVersion: '1.0.0',
          fullSummaryText: appState.summary ?? '',
          themeGroups: appState.themeGroups.isNotEmpty ? appState.themeGroups : null,
        );

        final jsonString = jsonEncode(projectData.toJson());
        await File(savePath).writeAsString(jsonString);
        
        appState.currentProjectPath = savePath;

        // TODO: 성공 메시지 표시 - context가 필요함
      } catch (e) {
        // TODO: 에러 메시지 표시 - context가 필요함
      }
    }
  }
  
  // 다른 이름으로 프로젝트 저장
  Future<void> saveProjectAs() async {
    if (appState.videoPath == null || appState.segments.isEmpty) {
      // TODO: ScaffoldMessenger 처리 - context가 필요함
      return;
    }

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '프로젝트 다른 이름으로 저장',
      fileName: '${path.basenameWithoutExtension(appState.videoPath!)}_copy.bcproj',
      type: FileType.custom,
      allowedExtensions: ['bcproj'],
    );

    if (savePath != null) {
      try {
      final projectData = ProjectData(
          videoPath: appState.videoPath!,
          segments: appState.segments,
          summarySegments: appState.segments.where((s) => appState.highlightedSegments.contains(s.id)).toList(),
        appVersion: '1.0.0',
          fullSummaryText: appState.summary ?? '',
          themeGroups: appState.themeGroups.isNotEmpty ? appState.themeGroups : null,
      );

      final jsonString = jsonEncode(projectData.toJson());
      await File(savePath).writeAsString(jsonString);
      
        appState.currentProjectPath = savePath;
      
        // TODO: 성공 메시지 표시 - context가 필요함
    } catch (e) {
        // TODO: 에러 메시지 표시 - context가 필요함
      }
    }
  }
  
  // 새 프로젝트 생성
  void newProject() {
    // 기존 비디오 컨트롤러 정리
    appState.videoController?.dispose();
    appState.videoController = null;
    
    // 요약 미리보기 타이머 정리
    appState.previewTimer?.cancel();
    
    appState.videoPath = null;
    appState.videoTitle = null;
    appState.segments = [];
    appState.summary = null;
    appState.isRecognizing = false;
    appState.isSummarizing = false;
    appState.recognizeSession++;
    appState.highlightedSegments = [];
    appState.themeGroups = [];
    appState.currentProjectPath = null;
    appState.currentPosition = Duration.zero;
    appState.totalDuration = Duration.zero;
    appState.isPlaying = false;
    appState.currentSegmentIndex = -1;
    appState.editingSegmentIndex = null;
    
    // 요약 미리보기 모드 초기화
    appState.isPreviewMode = false;
    appState.currentPreviewSegmentIndex = 0;
    appState.isPreviewPlaying = false;
    appState.isPreviewTransitioning = false;
  }
  
  // 프로젝트 열기
  Future<void> openProject() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bcproj'],
        dialogTitle: '프로젝트 열기',
      );

      if (result != null && result.files.single.path != null) {
      try {
        final file = File(result.files.single.path!);
        final jsonString = await file.readAsString();
        final jsonData = jsonDecode(jsonString);
        var projectData = ProjectData.fromJson(jsonData);

        // 비디오 파일 존재 및 접근 권한 확인
        final videoFile = File(projectData.videoPath);
        bool needsVideoReselection = false;
        String errorMessage = '';
        
        if (!videoFile.existsSync()) {
          needsVideoReselection = true;
          errorMessage = '원본 영상 파일을 찾을 수 없습니다. 영상 파일이 이동되었거나 삭제되었을 수 있습니다.';
        } else {
          // 비디오 파일 접근 권한 확인
          try {
            final file = await videoFile.open(mode: FileMode.read);
            await file.close();
          } catch (e) {
            needsVideoReselection = true;
            errorMessage = 'macOS 샌드박스 앱에서는 보안상 영상 파일에 직접 접근할 수 없습니다. 영상 파일을 다시 선택해주세요.';
          }
        }

        if (needsVideoReselection) {
          // TODO: 권한 오류 시 사용자에게 비디오 파일 재선택 요청 - context가 필요함
          return;
        }

        // 비디오 컨트롤러 초기화
        appState.videoController?.dispose();
        appState.videoController = VideoPlayerController.file(
          File(projectData.videoPath),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: false,
            allowBackgroundPlayback: false,
          ),
        );
        
        try {
          await appState.videoController!.initialize();
          await appState.videoController!.setVolume(1.0);
          
          // 첫 프레임(00:00) 위치로 설정하여 프리뷰에 첫 화면이 바로 보이도록 함
          await appState.videoController!.seekTo(Duration.zero);
          
          // 프레임 렌더링을 위해 매우 짧은 재생 후 즉시 일시정지
          await appState.videoController!.play();
          await Future.delayed(const Duration(milliseconds: 50));
          await appState.videoController!.pause();
          await appState.videoController!.seekTo(Duration.zero);
        } catch (e) {
          // TODO: 비디오 초기화 실패 시 사용자에게 안내 - context가 필요함
          appState.videoController?.dispose();
          appState.videoController = null;
          return;
        }
        
        // 비디오 컨트롤러 리스너 추가 (성능 최적화)
        appState.videoController!.addListener(optimizedVideoListener);

        // 상태 복원
        appState.videoPath = projectData.videoPath;
        appState.videoTitle = _extractVideoTitle(projectData.videoPath);
        appState.segments = projectData.segments;
        appState.summary = projectData.fullSummaryText;
        appState.highlightedSegments = projectData.summarySegments.map((s) => s.id).toList();
        appState.currentProjectPath = result.files.single.path;
        appState.isRecognizing = false;
        appState.isSummarizing = false;
        appState.recognizeSession++;
        appState.currentPosition = Duration.zero;
        appState.totalDuration = appState.videoController!.value.duration;
        appState.isPlaying = false;
        appState.currentSegmentIndex = -1;
        appState.editingSegmentIndex = null;
        
        // 요약 미리보기 모드 초기화
        appState.isPreviewMode = false;
        appState.currentPreviewSegmentIndex = 0;
        appState.isPreviewPlaying = false;
        appState.isPreviewTransitioning = false;
        
        // 저장된 챕터 정보 복원
        if (projectData.themeGroups != null && projectData.themeGroups!.isNotEmpty) {
          appState.themeGroups = projectData.themeGroups!;
        } else if (appState.highlightedSegments.isNotEmpty) {
          // 챕터 정보가 없으면 재구성
          _reconstructThemeGroups();
        }
        
        // 요약 미리보기 타이머 정리
        appState.previewTimer?.cancel();

        // TODO: 성공 메시지 표시 - context가 필요함
      } catch (e) {
        // TODO: 에러 메시지 표시 - context가 필요함
      }
    }
  }
  
  /// 테마 그룹 재구성 (public)
  void reconstructThemeGroups() {
    if (appState.segments.isEmpty) return;
    
    // 간단한 5개 그룹으로 재구성
    final totalSegments = appState.segments.length;
    final groupSize = (totalSegments / 5).ceil();
    
    List<ThemeGroup> groups = [];
    for (int i = 0; i < 5; i++) {
      final startId = i * groupSize + 1;
      int endId = ((i + 1) * groupSize).clamp(0, totalSegments);
      
      if (i == 4) {
        endId = totalSegments;
      }
      
      groups.add(ThemeGroup(
        theme: '챕터 ${i + 1}',
        segments: [], // TODO: 실제 세그먼트 데이터로 채워야 함
      ));
    }
    
    appState.themeGroups = groups;
  }

  // 테마 그룹 재구성 (private - 내부용)
  void _reconstructThemeGroups() {
    reconstructThemeGroups();
  }
  
  // 테마 색상 가져오기
  Color _getThemeColor(int index) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.red,
    ];
    return colors[index % colors.length];
  }
  
  /// 비디오 제목 추출 (public)
  String extractVideoTitle(String videoPath) {
    final fileName = path.basename(videoPath);
    return path.basenameWithoutExtension(fileName);
  }

  // 비디오 제목 추출 (private - 내부용)
  String _extractVideoTitle(String videoPath) {
    return extractVideoTitle(videoPath);
  }
  
  // 비디오 리스너 (성능 최적화)
  void optimizedVideoListener() {
    if (appState.videoController == null || !appState.videoController!.value.isInitialized) return;
    
    final now = DateTime.now();
    if (now.difference(appState.lastUpdateTime) < appState.updateInterval) {
      return;
    }
    
    appState.lastUpdateTime = now;
    
    final newPosition = appState.videoController!.value.position;
    final newDuration = appState.videoController!.value.duration;
    final newIsPlaying = appState.videoController!.value.isPlaying;
    
    if (newPosition != appState.currentPosition || 
        newDuration != appState.totalDuration || 
        newIsPlaying != appState.isPlaying) {
      appState.currentPosition = newPosition;
      appState.totalDuration = newDuration;
      appState.isPlaying = newIsPlaying;
    }
  }
  
  // 프로젝트 초기화
  void initializeProject() {
    // 기존 비디오 컨트롤러 정리
    appState.videoController?.dispose();
    appState.videoController = null;
    
    // 요약 미리보기 타이머 정리
    appState.previewTimer?.cancel();
    
    appState.videoPath = null;
    appState.videoTitle = null;
    appState.segments = [];
    appState.summary = null;
    appState.isRecognizing = false;
    appState.isSummarizing = false;
    appState.recognizeSession++;
    appState.highlightedSegments = [];
    appState.themeGroups = [];
    appState.currentProjectPath = null;
    appState.currentPosition = Duration.zero;
    appState.totalDuration = Duration.zero;
    appState.isPlaying = false;
    appState.currentSegmentIndex = -1;
    appState.editingSegmentIndex = null;
    
    // 요약 미리보기 모드 초기화
    appState.isPreviewMode = false;
    appState.currentPreviewSegmentIndex = 0;
    appState.isPreviewPlaying = false;
    appState.isPreviewTransitioning = false;
  }
  
  // XML 헤더 생성
  String generateXMLHeader() {
    final videoFileName = _getVideoFileName();
    final videoName = videoFileName.replaceAll('.mp4', '');
    final totalDuration = appState.totalDuration.inMilliseconds / 1000.0; // 원본 영상 전체 길이 사용
    final totalFrames = _secondsToFrames(totalDuration);
    
    return '''<?xml version="1.0" encoding="utf-8"?>
<xmeml version="5">
  <sequence id="video">
    <n>$videoName</n>
    <duration>$totalFrames</duration>
    <rate>
      <timebase>30</timebase>
      <ntsc>false</ntsc>
    </rate>
    <media>
      <video>
        <format>
          <samplecharacteristics>
            <width>1920</width>
            <height>1080</height>
            <anamorphic>false</anamorphic>
            <pixelaspectratio>square</pixelaspectratio>
            <fielddominance>none</fielddominance>
          </samplecharacteristics>
        </format>
        <track>''';
  }
  
  // 비디오 파일명 가져오기
  String _getVideoFileName() {
    if (appState.videoPath == null) return 'unknown.mp4';
    return path.basename(appState.videoPath!);
  }
  
  // 초를 프레임으로 변환
  String _secondsToFrames(double seconds) {
    final frames = (seconds * 30).round(); // 30fps 기준
    return frames.toString();
  }
  
  // 전체 XML 생성 (Premiere Pro)
  String generateFullXML() {
    if (appState.segments.isEmpty) return '';
    
    // TODO: 복잡한 XML 생성 로직 구현 필요
    // 현재는 간단한 버전으로 구현
    return generateXMLHeader() + '''
        </track>
      </video>
    </media>
  </sequence>
</xmeml>''';
  }
  
  // Final Cut Pro XML 생성
  String generateFCPXML() {
    // TODO: 구현 예정
    return '';
  }
  
  // DaVinci Resolve XML 생성
  String generateDaVinciXML() {
    // TODO: 구현 예정
    return '';
  }
  
  // 요약 XML 생성 (Premiere Pro)
  String generateSummaryXML() {
    // TODO: 구현 예정
    return '';
  }
  
  // 요약 Final Cut Pro XML 생성
  String generateSummaryFCPXML() {
    // TODO: 구현 예정
    return '';
  }
  
  // 요약 DaVinci Resolve XML 생성
  String generateSummaryDaVinciXML() {
    // TODO: 구현 예정
    return '';
  }
} 