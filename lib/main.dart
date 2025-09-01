import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:window_manager/window_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'models/app_state.dart';
import 'services/video_service.dart';
import 'services/project_service.dart';
import 'services/ai_service.dart';
import 'services/xml_service.dart';
import 'widgets/welcome_screen_widget.dart';
import 'widgets/main_content_widget.dart';
import 'widgets/processing_screen_widget.dart';
import 'widgets/export_menu_widget.dart';
import 'theme/cursor_theme.dart';


// 내보내기 형식 enum
enum ExportFormat {
  premiere,
  finalCutPro,
  daVinciResolve,
  mp4Full,
  mp4Summary,
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Firebase 초기화
  try {
    if (Platform.isMacOS) {
      // 맥용 - 명시적 옵션 제공 (GoogleService-Info.plist 값 사용)
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: 'AIzaSyAfqn1HtMhXYgL5EVfXJ-lf2wZ3s5XPwSw',
          appId: '1:27116968071:ios:71f408d81a2bbb152e0022',
          messagingSenderId: '27116968071',
          projectId: 'bestcut-beta',
          storageBucket: 'bestcut-beta.firebasestorage.app',
        ),
      );
      if (kDebugMode) print('✅ Firebase 초기화 성공 (맥 - 명시적 옵션)');
    } else if (kIsWeb) {
      // 웹용 (윈도우) - 명시적 옵션 사용
      await Firebase.initializeApp(
        options: const FirebaseOptions(
          apiKey: "AIzaSyA6dzIJCfSmWRV3KB9irzgVt0iNziYQR00",
          authDomain: "bestcut-beta.firebaseapp.com",
          projectId: "bestcut-beta",
          storageBucket: "bestcut-beta.firebasestorage.app",
          messagingSenderId: "27116968071",
          appId: "1:27116968071:web:83b829c095e18c4f2e0022",
          measurementId: "G-2KWBLRG36F",
        ),
      );
              if (kDebugMode) print('✅ Firebase 초기화 성공 (웹/윈도우)');
    } else {
      // 기타 플랫폼
      await Firebase.initializeApp();
              if (kDebugMode) print('✅ Firebase 초기화 성공 (기타 플랫폼)');
    }
  } catch (e) {
          if (kDebugMode) print('❌ Firebase 초기화 실패: $e');
  }
  
  // 데스크톱 플랫폼에서만 윈도우 크기 설정
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
    
    WindowOptions windowOptions = const WindowOptions(
      size: Size(1280, 800),  // 기본 크기 설정 (bottom 오버플로우 방지를 위해 높이 증가)
      minimumSize: Size(1280, 800),  // 최소 크기 설정 (이보다 작게 할 수 없음)
      center: true,  // 화면 중앙에 배치
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.normal,
    );
    
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  runApp(const BestCutApp());
}

class BestCutApp extends StatelessWidget {
  const BestCutApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BestCut - AI Video Summarizer',
      theme: CursorTheme.darkTheme, // Cursor AI 다크 테마 적용
      home: const BestCutHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BestCutHomePage extends StatefulWidget {
  const BestCutHomePage({super.key});

  @override
  State<BestCutHomePage> createState() => _BestCutHomePageState();
}

class _BestCutHomePageState extends State<BestCutHomePage> {
  // AppState 인스턴스
  late final AppState _appState;
  
  // 상태 변경 추적 변수들
  String? _lastVideoPath;
  bool? _lastVideoControllerState;
  int _lastSegmentsCount = 0;
  int _lastThemeGroupsCount = 0;
  
  // 화면 전환 상태
  bool _showProcessingScreen = false;
  
  // VideoService 인스턴스
  late final VideoService _videoService;
  
  // ProjectService 인스턴스
  late final ProjectService _projectService;
  
  // AIService 인스턴스
  late final AIService _aiService;
  
  // XMLService 인스턴스
  late final XMLService _xmlService;
  
  // AppState 변경사항 구독
  @override
  void initState() {
    super.initState();
    if (kDebugMode) print('🚀 main.dart: initState() 호출됨!');
    
    // AppState 초기화
    _appState = AppState();
          if (kDebugMode) print('📱 main.dart: AppState 인스턴스 생성됨');
    
    // VideoService 초기화
    _videoService = VideoService(_appState);
          if (kDebugMode) print('🎬 main.dart: VideoService 초기화됨');
    
    // ProjectService 초기화
    _projectService = ProjectService(_appState);
          if (kDebugMode) print('📁 main.dart: ProjectService 초기화됨');
    
    // AIService 초기화
    _aiService = AIService(_appState, context);
          if (kDebugMode) print('🤖 main.dart: AIService 초기화됨');
    
    // XMLService 초기화
    _xmlService = XMLService(_appState);
          if (kDebugMode) print('📄 main.dart: XMLService 초기화됨');
    
    // AppState 변경사항 구독
          if (kDebugMode) print('🔗 main.dart: AppState 구독 설정 중...');
    if (kDebugMode) print('   - AppState 인스턴스 ID: ${_appState.hashCode}');
    _appState.addListener(_onAppStateChanged);
    if (kDebugMode) print('✅ main.dart: AppState 구독 설정 완료');
    
    // 앱 첫 실행 시 초기화된 상태 확보 (다음 프레임에서 실행)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _projectService.initializeProject();
      if (kDebugMode) print('📋 main.dart: 프로젝트 초기화 완료');
    });
  }

  @override
  void dispose() {
    // 구독 해제
    _appState.removeListener(_onAppStateChanged);
    
    // 비디오 컨트롤러 정리
    _appState.videoController?.removeListener(_videoService.optimizedVideoListener);
    _appState.videoController?.dispose();
    
    // 타이머 정리
    _appState.previewTimer?.cancel();
    
    // 스트림 컨트롤러 정리
    if (_appState.progressStreamController != null && !_appState.progressStreamController!.isClosed) {
      _appState.progressStreamController!.close();
    }
    
    // 스크롤 컨트롤러 정리
    _appState.segmentScrollController.dispose();
    
    super.dispose();
  }

  void _onAppStateChanged() {
    // AppState가 변경되면 UI 리빌드
    // 실제로 중요한 변경사항이 있을 때만 setState 호출
    if (_shouldRebuildUI()) {
      setState(() {});
    }
  }
  
  // UI 리빌드가 필요한지 판단하는 메서드
  bool _shouldRebuildUI() {
    // 비디오 경로나 컨트롤러 상태가 변경된 경우
    if (_lastVideoPath != _appState.videoPath || 
        _lastVideoControllerState != _appState.videoController?.value.isInitialized) {
      
      // 새 동영상이 로드된 경우에만 취소 상태 리셋 (무한 루프 방지)
      if (_lastVideoPath != _appState.videoPath && _appState.videoPath != null) {
        if (kDebugMode) print('🔄 main.dart: 새 동영상 로드됨 - 취소 상태 리셋');
        // Future.microtask를 사용하여 다음 프레임에서 실행 (순환 참조 방지)
        Future.microtask(() {
          if (mounted) {
            _aiService.resetCancellation();
          }
        });
      }
      
      _lastVideoPath = _appState.videoPath;
      _lastVideoControllerState = _appState.videoController?.value.isInitialized;
      return true;
    }
    
    // 세그먼트나 테마 그룹이 변경된 경우
    if (_lastSegmentsCount != _appState.segments.length ||
        _lastThemeGroupsCount != _appState.themeGroups.length) {
      _lastSegmentsCount = _appState.segments.length;
      _lastThemeGroupsCount = _appState.themeGroups.length;
      return true;
    }
    
    return false;
  }
  
  // Processing Screen으로 전환
  void _startProcessing() {
    if (kDebugMode) print('🚀 main.dart: _startProcessing() 호출됨');
      setState(() {
      _showProcessingScreen = true;
    });
    if (kDebugMode) print('✅ main.dart: _showProcessingScreen = true로 설정됨');
  }
  
  // Welcome Screen 표시 여부 결정
  bool _showWelcomeScreen() {
    // Processing Screen이 활성화되어 있으면 Welcome Screen 표시 안함
    if (_showProcessingScreen) return false;
    
    // 동영상이 로드되어 있고 초기화된 경우
    if (_appState.videoPath != null && _appState.videoController?.value.isInitialized == true) {
      // 세그먼트가 있으면 작업이 완료된 것이므로 Main Content Screen 표시
      if (_appState.segments.isNotEmpty) {
        return false; // Main Content Screen 표시
      }
      // 세그먼트가 없으면 아직 작업을 시작하지 않은 것이므로 Welcome Screen 표시 (다이얼로그용)
      return true;
    }
    
    // 동영상이 로드되지 않은 경우 Welcome Screen 표시
    return _appState.videoPath == null || 
           _appState.videoController == null || 
           !_appState.videoController!.value.isInitialized;
  }
  
  // Processing Screen에서 메인 화면으로 전환
  void _onProcessingComplete() {
    if (kDebugMode) print('🎯 main.dart: _onProcessingComplete() 호출됨');
    setState(() {
      _showProcessingScreen = false;
    });
    if (kDebugMode) print('✅ main.dart: _showProcessingScreen = false로 설정됨');
  }

  // Processing Screen에서 Welcome Screen으로 복귀
  void _onCancelProcessing() {
    if (kDebugMode) print('❌ main.dart: _onCancelProcessing() 호출됨');
    
    // AppState 상태 초기화
        _appState.isRecognizing = false;
        _appState.isSummarizing = false;
    _appState.segments.clear();
    _appState.themeGroups.clear();
    _appState.highlightedSegments.clear();
        _appState.currentSegmentIndex = -1;
        _appState.isPreviewMode = false;
    // _appState.isOperationCancelled는 유지 (취소 상태 유지)
    
    // 동영상 관련 상태 완전 초기화 (다이얼로그 자동 호출 방지)
    _appState.videoPath = null;
    _appState.videoController = null;
    
    // 진행 상태 초기화
    if (_appState.progressStreamController != null && !_appState.progressStreamController!.isClosed) {
      _appState.progressStreamController!.add('작업이 취소되었습니다.');
    }
    
    // 다이얼로그 상태 초기화를 위한 강제 리빌드
        setState(() {
      _showProcessingScreen = false;
    });
    
    // 다이얼로그가 완전히 닫힐 때까지 잠시 대기
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {}); // 강제 리빌드로 다이얼로그 상태 초기화
      }
    });
    
    if (kDebugMode) print('✅ main.dart: _showProcessingScreen = false로 설정됨');
    if (kDebugMode) print('✅ main.dart: 모든 작업 상태 초기화 완료');
    if (kDebugMode) print('✅ main.dart: 동영상 상태 완전 초기화 완료');
  }
  

  // Cursor AI 스타일 버튼 위젯
  Widget _buildCursorButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    bool isAccent = false,
  }) {
    return Container(
      decoration: CursorTheme.containerDecoration(
        backgroundColor: isAccent ? CursorTheme.cursorBlue.withOpacity(0.1) : CursorTheme.backgroundTertiary,
        borderColor: isAccent ? CursorTheme.cursorBlue : CursorTheme.borderPrimary,
        borderRadius: CursorTheme.radiusSmall,
      ),
      child: IconButton(
        icon: Icon(
          icon,
          size: 18,
          color: isAccent ? CursorTheme.cursorBlue : CursorTheme.textSecondary,
        ),
        onPressed: onPressed,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(8),
      ),
    );
  }
  
  // 전체/요약 모드 토글 버튼 빌더
  Widget _buildModeToggleButton() {
    return Container(
      height: 40, // 프로젝트 관련 버튼과 동일한 높이
      decoration: CursorTheme.containerDecoration(
        backgroundColor: CursorTheme.backgroundTertiary,
        borderColor: CursorTheme.borderSecondary,
        borderRadius: CursorTheme.radiusSmall,
        elevated: false,
      ),
      child: Material(
        color: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 전체 모드 버튼
            InkWell(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(CursorTheme.radiusSmall),
                bottomLeft: Radius.circular(CursorTheme.radiusSmall),
              ),
              onTap: () {
        setState(() {
          _appState.isPreviewMode = false;
                });
                _appState.notifyListeners();
                if (kDebugMode) print('🔄 전체 모드로 전환');
              },
                    child: Container(
                padding: const EdgeInsets.symmetric(horizontal: CursorTheme.spacingM),
                height: 40,
                                decoration: BoxDecoration(
                  color: !_appState.isPreviewMode 
                      ? CursorTheme.cursorBlue 
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(CursorTheme.radiusSmall),
                    bottomLeft: Radius.circular(CursorTheme.radiusSmall),
                  ),
                ),
                child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                        Icons.playlist_play,
                        color: !_appState.isPreviewMode 
                            ? CursorTheme.textPrimary 
                            : CursorTheme.textSecondary,
                                            size: 16,
                                          ),
                      const SizedBox(width: CursorTheme.spacingS),
                                          Text(
                        '전체',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: !_appState.isPreviewMode 
                              ? CursorTheme.textPrimary 
                              : CursorTheme.textSecondary,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
            
            // 구분선
                            Container(
              width: 1,
              height: 40,
              color: CursorTheme.borderSecondary,
            ),
            
            // 요약 모드 버튼
            InkWell(
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(CursorTheme.radiusSmall),
                bottomRight: Radius.circular(CursorTheme.radiusSmall),
              ),
              onTap: () {
                  setState(() {
                  _appState.isPreviewMode = true;
                });
                _appState.notifyListeners();
                if (kDebugMode) print('🔄 요약 모드로 전환');
              },
                        child: Container(
                padding: const EdgeInsets.symmetric(horizontal: CursorTheme.spacingM),
                height: 40,
                          decoration: BoxDecoration(
                  color: _appState.isPreviewMode 
                      ? CursorTheme.warning 
                      : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(CursorTheme.radiusSmall),
                    bottomRight: Radius.circular(CursorTheme.radiusSmall),
                  ),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                        Icons.star_outline,
                        color: _appState.isPreviewMode 
                            ? CursorTheme.textPrimary 
                            : CursorTheme.textSecondary,
                                size: 16,
                      ),
                      const SizedBox(width: CursorTheme.spacingS),
                                        Text(
                        '요약',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _appState.isPreviewMode 
                              ? CursorTheme.textPrimary 
                              : CursorTheme.textSecondary,
                                                ),
                                              ),
                                      ],
                                    ),
                                  ),
                                ),
                          ),
                        ],
                      ),
                    ),
    );
  }

  // 공통 컨테이너 데코레이션 (Cursor AI 스타일로 업데이트)
  BoxDecoration _buildContainerDecoration({
    Color? backgroundColor,
    Color? borderColor,
    double borderRadius = CursorTheme.radiusMedium,
    bool elevated = false,
  }) {
    return CursorTheme.containerDecoration(
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      borderRadius: borderRadius,
      elevated: elevated,
    );
  }




  @override
  Widget build(BuildContext context) {
    if (kDebugMode) {
      print('🔄 main.dart: 화면 전환 상태 확인');
      print('   - _showProcessingScreen: $_showProcessingScreen');
      print('   - _showWelcomeScreen(): ${_showWelcomeScreen()}');
      print('   - videoPath: ${_appState.videoPath}');
      print('   - videoController: ${_appState.videoController != null ? "존재" : "null"}');
      print('   - isInitialized: ${_appState.videoController?.value.isInitialized ?? false}');
      print('   - 현재 표시될 화면: ${_showProcessingScreen ? "ProcessingScreen" : (_showWelcomeScreen() ? "WelcomeScreen" : "MainContentWidget")}');
    }
    
    return Scaffold(
      appBar: (_appState.videoPath != null && !_showWelcomeScreen() && !_showProcessingScreen) ? AppBar(
        title: Row(
          children: [
            // BestCut 로고 아이콘
                        Container(
              padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                color: CursorTheme.cursorBlue,
                borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                          ),
                          child: const Icon(
                Icons.video_settings,
                color: CursorTheme.textPrimary,
                size: 20,
              ),
            ),
            const SizedBox(width: CursorTheme.spacingS),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                  'BestCut',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                    color: CursorTheme.textPrimary,
                              ),
                            ),
                            Text(
                  'AI Video Summarizer',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CursorTheme.textTertiary,
                              ),
                            ),
                          ],
                        ),
            
            // 전체/요약 모드 토글 버튼 (로고 우측)
            const SizedBox(width: CursorTheme.spacingL),
            _buildModeToggleButton(),
          ],
        ),
        toolbarHeight: 80,
        backgroundColor: CursorTheme.backgroundSecondary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: CursorTheme.borderPrimary,
          ),
        ),
        actions: [
          // 프로젝트 관리 버튼들 (Cursor AI 스타일)
          Container(
            margin: const EdgeInsets.only(right: CursorTheme.spacingM),
                      child: Row(
              mainAxisSize: MainAxisSize.min,
                        children: [
                _buildCursorButton(
                  icon: Icons.add_circle_outline,
                  tooltip: '새 프로젝트',
                  onPressed: () => _projectService.newProject(),
                  isAccent: true,
                ),
                const SizedBox(width: CursorTheme.spacingS),
                _buildCursorButton(
                  icon: Icons.folder_open_outlined,
                  tooltip: '프로젝트 열기',
                  onPressed: () => _projectService.openProject(),
                ),
                const SizedBox(width: CursorTheme.spacingS),
                _buildCursorButton(
                  icon: Icons.save_outlined,
                  tooltip: '프로젝트 저장',
                  onPressed: () => _projectService.saveProject(),
                ),
                const SizedBox(width: CursorTheme.spacingS),
                _buildCursorButton(
                  icon: Icons.save_as_outlined,
                  tooltip: '다른 이름으로 저장',
                  onPressed: () => _projectService.saveProjectAs(),
                ),
              ],
            ),
          ),
          
          // 내보내기 메뉴 (Cursor AI 스타일)
                    Container(
            margin: const EdgeInsets.only(right: CursorTheme.spacingM),
            child: ExportMenuWidget(
              onExportXML: () => _exportProject(ExportFormat.premiere),
              onExportFCPXML: () => _exportProject(ExportFormat.finalCutPro),
              onExportDaVinciXML: () => _exportProject(ExportFormat.daVinciResolve),
              onExportMP4: () => _exportProject(ExportFormat.mp4Full),
              onExportSummaryXML: () => _exportProject(ExportFormat.premiere, isSummary: true),
              onExportSummaryFCPXML: () => _exportProject(ExportFormat.finalCutPro, isSummary: true),
              onExportSummaryDaVinciXML: () => _exportProject(ExportFormat.daVinciResolve, isSummary: true),
              onExportSummaryMP4: () => _exportProject(ExportFormat.mp4Summary),
            ),
          ),
        ],
      ) : null,
      body: _showProcessingScreen
          ? ProcessingScreenWidget(
              appState: _appState,
              aiService: _aiService,
              videoService: _videoService,
              onProcessingComplete: _onProcessingComplete,
              onCancelProcessing: _onCancelProcessing,
            )
          : _showWelcomeScreen()
              ? WelcomeScreenWidget(
                  videoService: _videoService,
                  projectService: _projectService,
                  onStartProcessing: _startProcessing,
                )
              : MainContentWidget(
              appState: _appState,
              buildContainerDecoration: _buildContainerDecoration,
              onPickVideo: () => _videoService.pickVideo(),
                      onRecognizeSpeech: () => _aiService.recognizeSpeech(),
        onSummarizeScript: () => _aiService.summarizeScript(),
                          onSegmentTap: (index) {
              // 세그먼트 탭 로직
              if (index >= 0 && index < _appState.segments.length) {
                final segment = _appState.segments[index];

                print('🖱️ 세그먼트 ${index + 1} 클릭됨 (ID: ${segment.id})');

                // 재생 중이면 즉시 일시정지
                if (_appState.isPlaying && _appState.videoController != null) {
                  _appState.videoController!.pause();
                  _appState.isPlaying = false;
                  print('⏸️ 재생 중지 (세그먼트 클릭으로 인한)');
                }

                // 현재 세그먼트 인덱스 업데이트
                _appState.currentSegmentIndex = index;
                
                // 요약 모드일 때는 요약 세그먼트 인덱스도 업데이트
                if (_appState.isPreviewMode) {
                  _appState.updateCurrentSummarySegmentIndex(index);
                }
                
                // 비디오 재생 위치 이동
                _videoService.seekTo(Duration(milliseconds: (segment.startSec * 1000).round()));
                
                print('🎯 세그먼트 ${index + 1}로 이동 및 하이라이트');
                
                // UI 업데이트
                _appState.notifyListeners();
              }
            },
              onSegmentSecondaryTap: (index) {
                // 요약 세그먼트 토글 로직
                final currentSegments = _appState.segments;
                if (index >= 0 && index < currentSegments.length) {
                  final segment = currentSegments[index];
                  final highlightedSegments = _appState.highlightedSegments;
                  
                  if (highlightedSegments.contains(segment.id)) {
                    highlightedSegments.remove(segment.id);
            } else {
                    highlightedSegments.add(segment.id);
                  }
                  
                  _appState.highlightedSegments = highlightedSegments;
                }
              },
              onSegmentDoubleTap: (index) {
                // 세그먼트 편집 시작 로직
                _appState.editingSegmentIndex = index;
              },
              onFinishEditing: (index, newText) {
                // 세그먼트 편집 완료 로직
                final currentSegments = _appState.segments;
                if (index >= 0 && index < currentSegments.length) {
                  currentSegments[index] = currentSegments[index].copyWith(text: newText);
                  _appState.segments = currentSegments;
                }
          _appState.editingSegmentIndex = null;
        },
        onTogglePlayPause: () => _videoService.togglePlayPause(),
      ),
    );
  }



  /// 내보내기 프로젝트 메서드
  Future<void> _exportProject(ExportFormat format, {bool isSummary = false}) async {
    if (_appState.segments.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내보낼 세그먼트가 없습니다.')),
        );
        return;
      }

    try {
      if (kDebugMode) print('📤 main.dart: 내보내기 시작 - 형식: $format');
      
      // 선택된 세그먼트 ID 결정
      List<int> selectedIds;
      if (isSummary) {
        selectedIds = _appState.highlightedSegments.toList();
        if (selectedIds.isEmpty) {
          selectedIds = _appState.segments.map((s) => s.id).toList();
        }
      } else {
        selectedIds = _appState.segments.map((s) => s.id).toList();
      }

      switch (format) {
        case ExportFormat.premiere:
          await _exportXMLFile(ExportFormat.premiere, selectedIds, isSummary);
        break;
        case ExportFormat.finalCutPro:
          await _exportXMLFile(ExportFormat.finalCutPro, selectedIds, isSummary);
          break;
        case ExportFormat.daVinciResolve:
          await _exportXMLFile(ExportFormat.daVinciResolve, selectedIds, isSummary);
          break;
        case ExportFormat.mp4Full:
          // TODO: MP4 내보내기 구현
          if (kDebugMode) print('📤 MP4 전체 내보내기 (아직 구현되지 않음)');
          break;
        case ExportFormat.mp4Summary:
          // TODO: MP4 요약 내보내기 구현
          if (kDebugMode) print('📤 MP4 요약 내보내기 (아직 구현되지 않음)');
        break;
      }
      
              if (kDebugMode) print('✅ main.dart: 내보내기 완료 - 형식: $format');
  } catch (e) {
              if (kDebugMode) print('❌ main.dart: 내보내기 실패 - 형식: $format, 오류: $e');
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('내보내기 실패: $e')),
      );
    }
  }

  /// XML 파일 내보내기 공통 메서드
  Future<void> _exportXMLFile(ExportFormat format, List<int> selectedIds, bool isSummary) async {
    try {
      String xmlContent;
      String fileName;
      String dialogTitle;
      List<String> allowedExtensions;

      switch (format) {
        case ExportFormat.premiere:
          xmlContent = await _xmlService.generatePremiereXML(
            isSummary: isSummary,
            selectedSegmentIds: selectedIds,
          );
          fileName = '${_xmlService.getVideoFileName().replaceAll('.mp4', '')}${isSummary ? '_요약' : ''}.xml';
          dialogTitle = isSummary ? '요약 XML 파일 저장' : '전체 XML 파일 저장';
          allowedExtensions = ['xml'];
          break;
        case ExportFormat.finalCutPro:
          xmlContent = await _xmlService.generateFCPXML(
            isSummary: isSummary,
            selectedSegmentIds: selectedIds,
          );
          fileName = '${_xmlService.getVideoFileName().replaceAll('.mp4', '')}${isSummary ? '_요약' : ''}.fcpxml';
          dialogTitle = isSummary ? '요약 Final Cut Pro XML 파일 저장' : 'Final Cut Pro XML 파일 저장';
          allowedExtensions = ['fcpxml'];
          break;
        case ExportFormat.daVinciResolve:
          xmlContent = await _xmlService.generateDaVinciXML(
            isSummary: isSummary,
            selectedSegmentIds: selectedIds,
          );
          fileName = '${_xmlService.getVideoFileName().replaceAll('.mp4', '')}${isSummary ? '_요약' : ''}_다빈치.xml';
          dialogTitle = isSummary ? '요약 DaVinci Resolve XML 파일 저장' : 'DaVinci Resolve XML 파일 저장';
          allowedExtensions = ['xml'];
          break;
        default:
          throw Exception('지원하지 않는 내보내기 형식: $format');
      }

      // 파일 저장 대화상자 열기
      final String? filePath = await FilePicker.platform.saveFile(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
      );

      if (filePath != null) {
        // 파일에 쓰기
        final File xmlFile = File(filePath);
        await xmlFile.writeAsString(xmlContent, encoding: utf8);
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${isSummary ? '요약 ' : ''}XML 파일이 저장되었습니다: ${path.basename(filePath)}')),
        );
      }
  } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('XML 파일 저장 중 오류가 발생했습니다: $e')),
      );
    }
  }
} // _BestCutHomePageState 클래스 끝
