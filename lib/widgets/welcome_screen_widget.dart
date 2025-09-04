import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
// TODO: constants import는 현재 사용되지 않음
import '../services/video_service.dart';
import '../services/project_service.dart';
import '../services/auth_service.dart';
import '../services/credit_service.dart';
import '../models/app_state.dart';
import '../theme/cursor_theme.dart';
import 'login_dialog_widget.dart';

class WelcomeScreenWidget extends StatefulWidget {
  final VideoService videoService;
  final ProjectService projectService;
  final VoidCallback? onStartProcessing; // 콜백 추가

  const WelcomeScreenWidget({
    super.key,
    required this.videoService,
    required this.projectService,
    this.onStartProcessing, // 콜백 파라미터 추가
  });

  @override
  State<WelcomeScreenWidget> createState() => _WelcomeScreenWidgetState();
}

class _WelcomeScreenWidgetState extends State<WelcomeScreenWidget> {
  bool _dialogShown = false; // 다이얼로그 표시 상태 추적
  final _authService = AuthService();
  final _creditService = CreditService();
  int _userCredits = 0;

  @override
  void initState() {
    super.initState();
    // 다이얼로그 표시 플래그 초기화
    _dialogShown = false;
    // AppState 변경사항 구독
    widget.videoService.appState.addListener(_onAppStateChanged);
    
    // 크레딧 정보 로드
    _loadUserCredits();
  }
  
  // 동영상 로드 시 새로운 창 표시
  void _showVideoInfoDialog() {
    if (kDebugMode) print('🎬 WelcomeScreen: _showVideoInfoDialog() 시작');
    
    if (widget.videoService.appState.videoPath == null || widget.videoService.appState.videoController?.value.isInitialized != true) {
      if (kDebugMode) print('❌ WelcomeScreen: 동영상 정보가 부족함');
      return;
    }
    
    // 🚨 중요: 저장된 프로젝트인지 확인 (이중 보안)
    if (widget.videoService.appState.segments.isNotEmpty) {
      if (kDebugMode) print('📁 WelcomeScreen: _showVideoInfoDialog에서 저장된 프로젝트 감지 - 다이얼로그 표시하지 않음');
      return;
    }
    
    // 이미 다이얼로그가 표시되어 있는지 확인
    if (_dialogShown) {
      if (kDebugMode) print('❌ WelcomeScreen: 이미 다이얼로그가 표시됨 (_dialogShown 플래그)');
      return;
    }
    
    // 다이얼로그 표시 플래그 설정 (실제로 다이얼로그를 표시하기 전에)
    _dialogShown = true;
    if (kDebugMode) print('🎬 WelcomeScreen: _dialogShown = true로 설정됨');
    
    if (kDebugMode) print('🎬 WelcomeScreen: showDialog 호출');
    
    showDialog(
      context: context,
      barrierDismissible: false, // 배경 탭으로 닫기 방지
      builder: (BuildContext context) {
        if (kDebugMode) print('🎬 WelcomeScreen: 다이얼로그 빌더 호출됨');
        return _buildVideoInfoDialog();
      },
    ).then((_) {
      if (kDebugMode) print('🎬 WelcomeScreen: 다이얼로그 표시 완료');
      _dialogShown = false; // 다이얼로그가 닫힐 때 플래그 리셋
    }).catchError((error) {
      if (kDebugMode) print('❌ WelcomeScreen: 다이얼로그 표시 오류: $error');
      _dialogShown = false; // 오류 발생 시에도 플래그 리셋
    });
  }

  @override
  void dispose() {
    // 구독 해제
    widget.videoService.appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    // 동영상이 로드되면 새로운 창 표시 (한 번만)
    if (widget.videoService.appState.videoPath != null && 
        widget.videoService.appState.videoController?.value.isInitialized == true) {
      
      // 🚨 중요: 저장된 프로젝트인지 확인
      // 세그먼트가 이미 존재하면 저장된 프로젝트이므로 다이얼로그 표시하지 않음
      if (widget.videoService.appState.segments.isNotEmpty) {
        if (kDebugMode) print('📁 WelcomeScreen: 저장된 프로젝트 감지 - 다이얼로그 표시하지 않음');
        
        // 다이얼로그가 열려있다면 닫기
        if (_dialogShown) {
          if (kDebugMode) print('🔒 WelcomeScreen: 저장된 프로젝트 감지 - 열린 다이얼로그 닫기');
          _dialogShown = false;
          // 다이얼로그가 열려있다면 닫기 (Navigator.pop은 context가 필요하므로 mounted 체크)
          if (mounted && context.mounted) {
            Navigator.of(context).pop();
          }
        }
        return;
      }
      
      // 새로운 동영상이고 다이얼로그가 아직 표시되지 않은 경우에만
      if (!_dialogShown) {
        if (kDebugMode) print('🎬 WelcomeScreen: 새로운 동영상 로드됨, 다이얼로그 표시 준비');
        
        // 새로운 창 표시 (즉시)
        if (mounted && context.mounted) {
          if (kDebugMode) print('🎬 WelcomeScreen: _showVideoInfoDialog() 호출');
          _showVideoInfoDialog();
        }
      }
    }
  }

  // 로그인 다이얼로그 표시
  void _showLoginDialog() {
    if (_authService.isLoggedIn) {
      // 로그아웃
      _showLogoutDialog();
    } else {
      // 로그인 다이얼로그 표시
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (BuildContext context) {
          return LoginDialogWidget(
            onLoginSuccess: () {
              setState(() {}); // UI 업데이트
              _loadUserCredits(); // 크레딧 정보 다시 로드
            },
            onCancel: () {
              Navigator.of(context).pop();
            },
          );
        },
      );
    }
  }

  // 로그아웃 확인 다이얼로그
  void _showLogoutDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: CursorTheme.backgroundSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CursorTheme.radiusMedium),
          ),
          title: Row(
            children: [
              Icon(Icons.logout, color: CursorTheme.warning, size: 20),
              const SizedBox(width: CursorTheme.spacingS),
              Text(
                '로그아웃',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: CursorTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            '정말 로그아웃하시겠습니까?',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: CursorTheme.textSecondary,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                '취소',
                style: TextStyle(color: CursorTheme.textSecondary),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _authService.signOut();
                setState(() {}); // UI 업데이트
                _loadUserCredits(); // 크레딧 정보 다시 로드
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: CursorTheme.warning,
                foregroundColor: CursorTheme.textPrimary,
              ),
              child: const Text('로그아웃'),
            ),
          ],
        );
      },
    );
  }

  // 사용자 크레딧 로드
  Future<void> _loadUserCredits() async {
    if (_authService.isLoggedIn) {
      try {
        final credits = await _creditService.getUserCredits();
        setState(() {
          _userCredits = credits;
        });
      } catch (e) {
        if (kDebugMode) print('❌ WelcomeScreen: 크레딧 로드 실패: $e');
      }
    } else {
      setState(() {
        _userCredits = 0;
      });
    }
  }

  
  // 동영상 정보 다이얼로그
  Widget _buildVideoInfoDialog() {
    if (widget.videoService.appState.videoPath == null) return const SizedBox.shrink();
    
    final videoPath = widget.videoService.appState.videoPath!;
    final videoTitle = path.basenameWithoutExtension(videoPath);
    final duration = widget.videoService.appState.videoController?.value.duration ?? Duration.zero;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 800,
        height: 600,
        decoration: CursorTheme.containerDecoration(
          backgroundColor: CursorTheme.backgroundSecondary,
          borderColor: CursorTheme.borderPrimary,
          borderRadius: CursorTheme.radiusMedium,
          elevated: true,
        ),
        child: Column(
          children: [
            // 헤더 (Cursor AI 스타일)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(CursorTheme.spacingL),
              decoration: BoxDecoration(
                color: CursorTheme.backgroundTertiary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(CursorTheme.radiusMedium),
                  topRight: Radius.circular(CursorTheme.radiusMedium),
                ),
                border: Border(
                  bottom: BorderSide(color: CursorTheme.borderPrimary, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(CursorTheme.spacingS),
                    decoration: CursorTheme.containerDecoration(
                      backgroundColor: CursorTheme.cursorBlue,
                      borderRadius: CursorTheme.radiusSmall,
                    ),
                    child: const Icon(Icons.video_file, color: CursorTheme.textPrimary, size: 20),
                  ),
                  const SizedBox(width: CursorTheme.spacingM),
                  Expanded(
                    child: Text(
                      '동영상 정보',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: CursorTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      // 위젯이 여전히 마운트되어 있는지 확인
                      if (!mounted) return;
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.close, color: CursorTheme.textSecondary, size: 20),
                  ),
                ],
              ),
            ),
            
            // 동영상 정보 (Cursor AI 스타일)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(CursorTheme.spacingL),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 정보 리스트
                    _buildInfoRow('제목', videoTitle, context),
                    const SizedBox(height: CursorTheme.spacingM),
                    _buildInfoRow('경로', videoPath, context, isPath: true),
                    const SizedBox(height: CursorTheme.spacingM),
                    _buildInfoRow('재생 시간', '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}', context),
                    
                    const SizedBox(height: CursorTheme.spacingL),
                    
                    // 처리 안내 (Cursor AI 스타일)
                    Container(
                      padding: const EdgeInsets.all(CursorTheme.spacingM),
                      decoration: CursorTheme.containerDecoration(
                        backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
                        borderColor: CursorTheme.cursorBlue,
                        borderRadius: CursorTheme.radiusSmall,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: CursorTheme.cursorBlue, size: 18),
                          const SizedBox(width: CursorTheme.spacingS),
                          Expanded(
                            child: Text(
                              '이 동영상에 대해 음성인식과 AI 내용 요약을 진행합니다.\n동영상 길이에 따라 몇 분에서 수십 분이 소요될 수 있습니다.',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: CursorTheme.cursorBlue,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // 버튼들 (Cursor AI 스타일)
            Container(
              padding: const EdgeInsets.all(CursorTheme.spacingL),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: CursorTheme.borderPrimary, width: 1),
                ),
              ),
              child: Row(
                children: [
                  // 취소 버튼
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () {
                          // 위젯이 여전히 마운트되어 있는지 확인
                          if (!mounted) return;
                          Navigator.of(context).pop();
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: CursorTheme.borderSecondary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                          ),
                        ),
                        child: Text(
                          '취소',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: CursorTheme.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(width: CursorTheme.spacingM),
                  
                  // 내용 요약 진행 버튼
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // 위젯이 여전히 마운트되어 있는지 확인
                          if (!mounted) return;
                          
                          // 로그인 체크
                          if (!_authService.isLoggedIn) {
                            Navigator.of(context).pop(); // 현재 다이얼로그 닫기
                            // 로그인 다이얼로그 표시
                            _showLoginDialog();
                            return;
                          }
                          
                          Navigator.of(context).pop(); // 현재 다이얼로그 닫기
                          // 크레딧 체크 후 처리 시작
                          _checkCreditsAndStartProcessing();
                        },
                        icon: const Icon(Icons.play_arrow, size: 18),
                        label: Text(
                          '내용 요약 진행하기',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CursorTheme.cursorBlue,
                          foregroundColor: CursorTheme.textPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
        );
  }

  // 정보 행 헬퍼 함수
  Widget _buildInfoRow(String label, String value, BuildContext context, {bool isPath = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: CursorTheme.textTertiary,
            ),
          ),
        ),
        const SizedBox(width: CursorTheme.spacingS),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: CursorTheme.textPrimary,
              fontFamily: isPath ? 'monospace' : null,
            ),
            maxLines: isPath ? 3 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: CursorTheme.backgroundPrimary, // Cursor AI 다크 배경
      ),
      child: Stack(
        children: [
          // 메인 콘텐츠
          Padding(
            padding: const EdgeInsets.all(CursorTheme.spacingXL),
            child: Row(
              children: [
            // 왼쪽: 사용 방법 섹션 (Cursor AI 스타일)
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.all(CursorTheme.spacingL),
                margin: const EdgeInsets.only(right: CursorTheme.spacingM),
                decoration: CursorTheme.containerDecoration(
                  backgroundColor: CursorTheme.backgroundSecondary,
                  borderColor: CursorTheme.borderPrimary,
                  borderRadius: CursorTheme.radiusMedium,
                  elevated: true,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(CursorTheme.spacingS),
                          decoration: CursorTheme.containerDecoration(
                            backgroundColor: CursorTheme.cursorBlue,
                            borderRadius: CursorTheme.radiusSmall,
                            glowing: true,
                          ),
                          child: const Icon(
                            Icons.tips_and_updates,
                            color: CursorTheme.textPrimary,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: CursorTheme.spacingS),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '사용 방법',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: CursorTheme.textPrimary,
                              ),
                            ),
                            Text(
                              'BestCut 사용법을 알아보세요',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: CursorTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: CursorTheme.spacingL),
                    Container(
                      padding: const EdgeInsets.all(CursorTheme.spacingS),
                      decoration: CursorTheme.containerDecoration(
                        backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
                        borderColor: CursorTheme.cursorBlue,
                        borderRadius: CursorTheme.radiusSmall,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lightbulb_outline, color: CursorTheme.cursorBlue, size: 16),
                          const SizedBox(width: CursorTheme.spacingS),
                          Expanded(
                            child: Text(
                              '팁: 동영상을 불러오면 자동으로 음성인식과 요약이 시작됩니다!',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: CursorTheme.cursorBlue,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // 오른쪽: 로고, 환영인사, 버튼들 (Cursor AI 스타일)
            Expanded(
              flex: 3,
              child: Container(
                padding: const EdgeInsets.all(CursorTheme.spacingXL),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 앱 로고 영역 (Cursor AI 스타일)
                    Container(
                      width: 100,
                      height: 100,
                      decoration: CursorTheme.containerDecoration(
                        backgroundColor: CursorTheme.cursorBlue,
                        borderRadius: CursorTheme.radiusLarge,
                        elevated: true,
                        glowing: true,
                      ),
                      child: const Icon(
                        Icons.video_settings,
                        size: 50,
                        color: CursorTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: CursorTheme.spacingL),
                    
                    // 앱 제목 (Cursor AI 스타일)
                    Text(
                      'BestCut',
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: CursorTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: CursorTheme.spacingM),
                    
                    // 앱 설명 (Cursor AI 스타일)
                    Text(
                      'AI Video Summarizer',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: CursorTheme.cursorBlue,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: CursorTheme.spacingS),
                    
                    Text(
                      '동영상 로드 시 자동으로 음성인식과 AI 요약을\n수행하여 영상의 핵심 내용을 빠르게 찾아보세요',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: CursorTheme.textSecondary,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: CursorTheme.spacingXL),
                    
                    // 크레딧 정보 표시 (로그인된 경우에만)
                    if (_authService.isLoggedIn) ...[
                      Container(
                        padding: const EdgeInsets.all(CursorTheme.spacingM),
                        decoration: CursorTheme.containerDecoration(
                          backgroundColor: CursorTheme.backgroundTertiary,
                          borderColor: CursorTheme.borderSecondary,
                          borderRadius: CursorTheme.radiusSmall,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.account_balance_wallet, color: CursorTheme.cursorBlue, size: 16),
                            const SizedBox(width: CursorTheme.spacingS),
                            Text(
                              '보유 크레딧: $_userCredits',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: CursorTheme.cursorBlue,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: CursorTheme.spacingM),
                    ],
                    
                    // 메인 액션 버튼들 (Cursor AI 스타일)
                    Column(
                      children: [
                        // 새 동영상 불러오기 버튼
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: widget.videoService.pickVideo,
                            icon: const Icon(Icons.video_file, size: 20),
                            label: Text(
                              '새 동영상 불러오기',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: CursorTheme.cursorBlue,
                              foregroundColor: CursorTheme.textPrimary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: CursorTheme.spacingM),
                        
                        
                        // 저장된 프로젝트 열기 버튼
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: () => widget.projectService.openProject(),
                            icon: const Icon(Icons.folder_open, size: 20),
                            label: Text(
                              '저장된 프로젝트 열기',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: CursorTheme.cursorBlue,
                              side: const BorderSide(color: CursorTheme.cursorBlue, width: 1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: CursorTheme.spacingL),
                    
                    // 추가 안내 텍스트 (Cursor AI 스타일)
                    Container(
                      padding: const EdgeInsets.all(CursorTheme.spacingM),
                      decoration: CursorTheme.containerDecoration(
                        backgroundColor: CursorTheme.backgroundTertiary,
                        borderColor: CursorTheme.borderSecondary,
                        borderRadius: CursorTheme.radiusSmall,
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.rocket_launch, color: CursorTheme.success, size: 16),
                              const SizedBox(width: CursorTheme.spacingXS),
                              Text(
                                '지금 바로 시작하세요!',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: CursorTheme.success,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: CursorTheme.spacingXS),
                          Text(
                            '몇 분 안에 영상의 핵심을 파악할 수 있습니다',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: CursorTheme.textTertiary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      
      // 오른쪽 상단 로그인 버튼
      Positioned(
        top: CursorTheme.spacingL,
        right: CursorTheme.spacingL,
        child: Container(
          decoration: BoxDecoration(
            color: CursorTheme.cursorBlue,
            borderRadius: BorderRadius.circular(25), // 라운드 처리
            boxShadow: [
              BoxShadow(
                color: CursorTheme.cursorBlue.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(25),
              onTap: _showLoginDialog,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: CursorTheme.spacingM,
                  vertical: CursorTheme.spacingS,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _authService.isLoggedIn ? Icons.person : Icons.login,
                      size: 18,
                      color: Colors.white, // 흰색 텍스트
                    ),
                    const SizedBox(width: CursorTheme.spacingXS),
                    Text(
                      _authService.isLoggedIn ? '로그아웃' : '로그인',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white, // 흰색 텍스트
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  ),
);
}

  // 크레딧 체크 후 처리 시작
  Future<void> _checkCreditsAndStartProcessing() async {
    try {
      // 비디오 컨트롤러 확인
      final videoController = widget.videoService.appState.videoController;
      if (videoController == null || !videoController.value.isInitialized) {
        _showErrorDialog('비디오가 로드되지 않았습니다.');
        return;
      }

      // 비디오 길이 계산
      final videoDuration = videoController.value.duration.inSeconds.toDouble();
      
      print('💰 WelcomeScreen: 크레딧 체크 시작 - 비디오 길이: ${videoDuration}초');
      
      // 크레딧 체크
      final creditInfo = await _creditService.checkCredits(videoDuration);
      
      if (!creditInfo['canPerform']) {
        // 크레딧 부족 시 에러 다이얼로그 표시
        final message = creditInfo['message'] ?? '크레딧이 부족합니다.';
        final shortage = creditInfo['shortage'] ?? 0;
        final requiredCredits = creditInfo['requiredCredits'] ?? 0;
        
        print('🚫 WelcomeScreen: 크레딧 부족 - $message');
        
        _showErrorDialog(
          '크레딧이 부족합니다.\n\n'
          '필요한 크레딧: $requiredCredits\n'
          '부족한 크레딧: $shortage\n\n'
          '크레딧을 충전한 후 다시 시도해주세요.'
        );
        return;
      }
      
      // 크레딧 충분 시 처리 시작
      print('✅ WelcomeScreen: 크레딧 충분 - 처리 시작');
      if (widget.onStartProcessing != null) {
        widget.onStartProcessing!();
      }
      
    } catch (e) {
      print('❌ WelcomeScreen: 크레딧 체크 오류: $e');
      _showErrorDialog('크레딧 확인 중 오류가 발생했습니다: $e');
    }
  }

  // 에러 다이얼로그 표시
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error, color: Colors.red[600], size: 24),
              const SizedBox(width: 8),
              const Text('오류 발생'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }
}
