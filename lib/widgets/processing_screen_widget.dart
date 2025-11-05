import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../models/app_state.dart';
import '../services/ai_service.dart';
import '../services/video_service.dart';
import '../widgets/video_player_widget.dart';
import '../theme/cursor_theme.dart';

class ProcessingScreenWidget extends StatefulWidget {
  final AppState appState;
  final AIService aiService;
  final VideoService videoService;
  final VoidCallback? onProcessingComplete; // 콜백 추가
  final VoidCallback? onCancelProcessing; // 취소 콜백 추가

  const ProcessingScreenWidget({
    super.key,
    required this.appState,
    required this.aiService,
    required this.videoService,
    this.onProcessingComplete,
    this.onCancelProcessing,
  });

  @override
  State<ProcessingScreenWidget> createState() => _ProcessingScreenWidgetState();
}

class _ProcessingScreenWidgetState extends State<ProcessingScreenWidget> {
  bool _isProcessing = false;
  String _currentOperation = '준비 중...';
  double _progress = 0.0;
  List<String> _operationLogs = [];
  


  @override
  void initState() {
    super.initState();
    // 동영상 정보가 준비되면 자동으로 처리 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startProcessing();
    });
  }

  // 처리 시작
  Future<void> _startProcessing() async {
    if (_isProcessing) return;
    
    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _operationLogs.clear();
      _currentOperation = '음성인식 준비 중...';
    });

    try {
      // 1단계: 음성인식
      await _performSpeechRecognition();
      
      // 2단계: 내용 요약
      await _performContentSummarization();
      
      // 3단계: 완료
      _onProcessingComplete();
      
    } catch (e) {
      if (kDebugMode) print('❌ 처리 중 오류 발생: $e');
      _showErrorDialog('처리 중 오류가 발생했습니다: $e');
    }
  }

  // 음성인식 수행
  Future<void> _performSpeechRecognition() async {
    if (!mounted) return; // 위젯이 마운트되지 않은 경우 리턴
    
    setState(() {
      _currentOperation = '음성인식을 시작합니다...';
      _progress = 0.1;
      _addOperationLog('🎤 음성인식 시작');
    });

    try {

      await widget.aiService.recognizeSpeech();
      
      if (!mounted) return; // 위젯이 마운트되지 않은 경우 리턴
      
      // 음성인식 결과 확인
      if (widget.appState.segments.isEmpty) {
        throw Exception('음성인식에 실패했습니다. 세그먼트가 생성되지 않았습니다.');
      }
      
      setState(() {
        _currentOperation = '음성인식이 완료되었습니다!';
        _progress = 0.5;
        _addOperationLog('✅ 음성인식 완료');
      });
      
      // 잠시 대기
      await Future.delayed(const Duration(seconds: 1));
      
    } catch (e) {
      if (kDebugMode) print('❌ 음성인식 오류: $e');
      _addOperationLog('❌ 음성인식 오류: $e');
      rethrow;
    }
  }

  // 내용 요약 수행
  Future<void> _performContentSummarization() async {
    if (!mounted) return; // 위젯이 마운트되지 않은 경우 리턴
    
    setState(() {
      _currentOperation = 'AI가 내용을 분석하고 요약하고 있습니다...';
      _progress = 0.6;
      _addOperationLog('🤖 AI 내용 요약 시작');
    });

    try {
      await widget.aiService.summarizeScript();
      
      if (!mounted) return; // 위젯이 마운트되지 않은 경우 리턴
      
      setState(() {
        _currentOperation = '내용 요약이 완료되었습니다!';
        _progress = 1.0;
        _addOperationLog('✅ 내용 요약 완료');
      });
      
      // 전체 과정 완료 시 크레딧 차감
      await widget.aiService.handleCompleteProcessing();
      
      // 잠시 대기
      await Future.delayed(const Duration(seconds: 1));
      
    } catch (e) {
      if (kDebugMode) print('❌ 내용 요약 오류: $e');
      _addOperationLog('❌ 내용 요약 오류: $e');
      rethrow;
    }
  }

  // 처리 완료
  void _onProcessingComplete() {
    if (!mounted) return; // 위젯이 마운트되지 않은 경우 리턴
    
    setState(() {
      _currentOperation = '모든 처리가 완료되었습니다!';
      _progress = 1.0;
      _addOperationLog('🎉 모든 처리 완료!');
    });

    // 잠시 후 메인 화면으로 전환
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && widget.onProcessingComplete != null) {
        if (kDebugMode) print('🎯 ProcessingScreen: onProcessingComplete 콜백 호출');
        widget.onProcessingComplete!();
      }
    });
  }

  // 작업 로그 추가
  void _addOperationLog(String message) {
    if (!mounted) return; // 위젯이 마운트되지 않은 경우 리턴
    
    setState(() {
      _operationLogs.add('${DateTime.now().toString().substring(11, 19)} $message');
      // 최대 10개 로그만 유지
      if (_operationLogs.length > 10) {
        _operationLogs.removeAt(0);
      }
    });
  }
  


  // 오류 다이얼로그 표시
  void _showErrorDialog(String message, {VoidCallback? onClose}) {
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
              onPressed: () {
                Navigator.of(context).pop();
                if (onClose != null) {
                  onClose();
                }
              },
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CursorTheme.backgroundSecondary,
      body: Column(
        children: [
          // 상단: 통합 헤더
          _buildUnifiedTopSection(),
          
          // 중간: 메인 콘텐츠 (비디오 + 로그)
          Expanded(
            child: Row(
              children: [
                // 좌측: 비디오 프리뷰
                Expanded(
                  flex: 2,
                  child: _buildUnifiedVideoSection(),
                ),
                
                // 우측: 로그 섹션
                Expanded(
                  flex: 3,
                  child: _buildUnifiedLogSection(),
                ),
              ],
            ),
          ),
          
          // 하단: 프로그레스 섹션
          _buildUnifiedBottomSection(),
        ],
      ),
    );
  }

  // 통합 헤더 섹션
  Widget _buildUnifiedTopSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CursorTheme.spacingL),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: CursorTheme.borderPrimary, width: 1),
        ),
      ),
      child: Row(
        children: [
          // 왼쪽: AI 아이콘과 메인 텍스트
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(CursorTheme.spacingS),
                  decoration: CursorTheme.containerDecoration(
                    backgroundColor: CursorTheme.cursorBlue,
                    borderRadius: CursorTheme.radiusSmall,
                    glowing: true,
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    color: CursorTheme.textPrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: CursorTheme.spacingM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'AI 동영상 분석 중',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: CursorTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: CursorTheme.spacingXS),
                      Text(
                        '음성 인식과 내용 요약을 진행하고 있습니다',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: CursorTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // 오른쪽: 실시간 상태 인디케이터
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: CursorTheme.spacingM,
              vertical: CursorTheme.spacingS,
            ),
            decoration: CursorTheme.containerDecoration(
              backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
              borderColor: CursorTheme.cursorBlue,
              borderRadius: CursorTheme.radiusLarge,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    color: CursorTheme.cursorBlue,
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(width: CursorTheme.spacingS),
                Text(
                  '진행 중',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: CursorTheme.cursorBlue,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }



  // 2. Cursor AI 스타일 비디오 섹션
  Widget _buildCursorVideoSection() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: CursorTheme.containerDecoration(
        backgroundColor: CursorTheme.backgroundSecondary,
        borderColor: CursorTheme.borderPrimary,
        borderRadius: CursorTheme.radiusMedium,
        elevated: true,
      ),
      child: Column(
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.all(CursorTheme.spacingM),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: CursorTheme.borderPrimary,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(CursorTheme.spacingS),
                  decoration: CursorTheme.containerDecoration(
                    backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
                    borderColor: CursorTheme.cursorBlue,
                    borderRadius: CursorTheme.radiusSmall,
                  ),
                  child: const Icon(
                    Icons.play_circle_outline,
                    color: CursorTheme.cursorBlue,
                    size: 18,
                  ),
                ),
                const SizedBox(width: CursorTheme.spacingS),
                Text(
                  '비디오 프리뷰',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: CursorTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          // 비디오 플레이어
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(CursorTheme.spacingM),
              child: Center(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: VideoPlayerWidget(
                    appState: widget.appState,
                    previewWidth: 600,
                    centerPlayButton: true,
                    hideControls: true,
                    hideTitle: true,
                    buildContainerDecoration: ({backgroundColor, borderColor, double borderRadius = 6, bool elevated = false}) {
                      return CursorTheme.containerDecoration(
                        backgroundColor: CursorTheme.backgroundTertiary,
                        borderColor: CursorTheme.borderSecondary,
                        borderRadius: CursorTheme.radiusSmall,
                        elevated: elevated,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 3. Cursor AI 스타일 로그 섹션
  Widget _buildCursorLogSection() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: CursorTheme.containerDecoration(
        backgroundColor: CursorTheme.backgroundSecondary,
        borderColor: CursorTheme.borderPrimary,
        borderRadius: CursorTheme.radiusMedium,
        elevated: true,
      ),
      child: Column(
        children: [
          // 헤더
          Container(
            padding: const EdgeInsets.all(CursorTheme.spacingM),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: CursorTheme.borderPrimary,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(CursorTheme.spacingS),
                  decoration: CursorTheme.containerDecoration(
                    backgroundColor: CursorTheme.success.withOpacity(0.1),
                    borderColor: CursorTheme.success,
                    borderRadius: CursorTheme.radiusSmall,
                  ),
                  child: const Icon(
                    Icons.terminal,
                    color: CursorTheme.success,
                    size: 18,
                  ),
                ),
                const SizedBox(width: CursorTheme.spacingS),
                Text(
                  '처리 로그',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: CursorTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          // 현재 작업 상태 (오버플로우 방지)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(CursorTheme.spacingS),
            decoration: BoxDecoration(
              color: CursorTheme.cursorBlue.withOpacity(0.05),
              border: Border(
                bottom: BorderSide(
                  color: CursorTheme.borderPrimary,
                  width: 1,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '현재 작업',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: CursorTheme.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: CursorTheme.spacingXS),
                Text(
                  _currentOperation,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CursorTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // 로그 리스트
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(CursorTheme.spacingS),
              itemCount: _operationLogs.length,
              itemBuilder: (context, index) {
                final log = _operationLogs[index];
                final isLatest = index == _operationLogs.length - 1;
                
                return Container(
                  margin: const EdgeInsets.only(bottom: CursorTheme.spacingXS),
                  padding: const EdgeInsets.symmetric(
                    horizontal: CursorTheme.spacingS,
                    vertical: CursorTheme.spacingXS,
                  ),
                  decoration: CursorTheme.containerDecoration(
                    backgroundColor: isLatest 
                      ? CursorTheme.cursorBlue.withOpacity(0.1)
                      : CursorTheme.backgroundTertiary,
                    borderColor: isLatest 
                      ? CursorTheme.cursorBlue.withOpacity(0.3)
                      : CursorTheme.borderSecondary,
                    borderRadius: CursorTheme.radiusSmall,
                  ),
                  child: Text(
                    log,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isLatest 
                        ? CursorTheme.cursorBlue
                        : CursorTheme.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 4. Cursor AI 스타일 하단 프로그레스 섹션
  Widget _buildCursorBottomSection() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: CursorTheme.containerDecoration(
        backgroundColor: CursorTheme.backgroundSecondary,
        borderColor: CursorTheme.borderPrimary,
        borderRadius: CursorTheme.radiusMedium,
        elevated: true,
      ),
      child: Padding(
        padding: const EdgeInsets.all(CursorTheme.spacingL),
        child: Row(
          children: [
            // 왼쪽: 진행률 정보
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 진행률 헤더
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '처리 진행률',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: CursorTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: CursorTheme.spacingS,
                          vertical: CursorTheme.spacingXS,
                        ),
                        decoration: CursorTheme.containerDecoration(
                          backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
                          borderColor: CursorTheme.cursorBlue,
                          borderRadius: CursorTheme.radiusLarge,
                        ),
                        child: Text(
                          '${(_progress * 100).toInt()}%',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: CursorTheme.cursorBlue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: CursorTheme.spacingM),
                  
                  // 프로그레스바
                  ClipRRect(
                    borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                    child: LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: CursorTheme.backgroundTertiary,
                      valueColor: const AlwaysStoppedAnimation<Color>(CursorTheme.cursorBlue),
                      minHeight: 8,
                    ),
                  ),
                  
                  const SizedBox(height: CursorTheme.spacingS),
                  
                  // 단계 표시 (오버플로우 방지)
                  Wrap(
                    spacing: CursorTheme.spacingXS,
                    runSpacing: CursorTheme.spacingXS,
                    children: [
                      _buildProgressStep('음성인식', _progress >= 0.5, _progress >= 0.1),
                      _buildProgressStep('내용요약', _progress >= 1.0, _progress >= 0.6),
                      _buildProgressStep('완료', false, _progress >= 1.0),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: CursorTheme.spacingM),
            
            // 오른쪽: 취소 버튼 (크기 조정)
            Flexible(
              child: Container(
                decoration: CursorTheme.containerDecoration(
                  backgroundColor: CursorTheme.error.withOpacity(0.1),
                  borderColor: CursorTheme.error,
                  borderRadius: CursorTheme.radiusSmall,
                ),
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (kDebugMode) print('❌ ProcessingScreen: 취소 버튼 클릭됨');
                    widget.aiService.cancelOperation();
                    if (widget.onCancelProcessing != null) {
                      widget.onCancelProcessing!();
                    }
                  },
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('취소'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CursorTheme.error,
                    foregroundColor: CursorTheme.textPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: CursorTheme.spacingM,
                      vertical: CursorTheme.spacingS,
                    ),
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
    );
  }

  // 프로그레스 단계 위젯
  Widget _buildProgressStep(String label, bool isCompleted, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CursorTheme.spacingS,
        vertical: CursorTheme.spacingXS,
      ),
      decoration: CursorTheme.containerDecoration(
        backgroundColor: isCompleted 
          ? CursorTheme.success.withOpacity(0.1)
          : isActive 
            ? CursorTheme.cursorBlue.withOpacity(0.1)
            : CursorTheme.backgroundTertiary,
        borderColor: isCompleted 
          ? CursorTheme.success
          : isActive 
            ? CursorTheme.cursorBlue
            : CursorTheme.borderSecondary,
        borderRadius: CursorTheme.radiusSmall,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCompleted 
              ? Icons.check_circle
              : isActive 
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 14,
            color: isCompleted 
              ? CursorTheme.success
              : isActive 
                ? CursorTheme.cursorBlue
                : CursorTheme.textTertiary,
          ),
          const SizedBox(width: CursorTheme.spacingXS),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isCompleted 
                ? CursorTheme.success
                : isActive 
                  ? CursorTheme.cursorBlue
                  : CursorTheme.textTertiary,
              fontWeight: isCompleted || isActive 
                ? FontWeight.w600 
                : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
  
  // 통합 비디오 섹션
  Widget _buildUnifiedVideoSection() {
    return Container(
      padding: const EdgeInsets.all(CursorTheme.spacingL),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: CursorTheme.borderPrimary, width: 1),
        ),
      ),
      child: Column(
        children: [
          // 섹션 헤더
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(CursorTheme.spacingXS),
                decoration: CursorTheme.containerDecoration(
                  backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
                  borderColor: CursorTheme.cursorBlue,
                  borderRadius: CursorTheme.radiusSmall,
                ),
                child: Icon(
                  Icons.play_circle_outline,
                  color: CursorTheme.cursorBlue,
                  size: 16,
                ),
              ),
              const SizedBox(width: CursorTheme.spacingS),
              Text(
                '비디오 프리뷰',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: CursorTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: CursorTheme.spacingM),
          
          // 비디오 플레이어
          Expanded(
            child: Center(
              child: Container(
                width: double.infinity,
                decoration: CursorTheme.containerDecoration(
                  backgroundColor: CursorTheme.backgroundTertiary,
                  borderColor: CursorTheme.borderSecondary,
                  borderRadius: CursorTheme.radiusSmall,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                  child: AspectRatio(
                    aspectRatio: 16/9,
                    child: VideoPlayerWidget(
                      appState: widget.appState,
                      previewWidth: 400.0,
                      buildContainerDecoration: ({
                        Color? backgroundColor,
                        Color? borderColor,
                        double borderRadius = CursorTheme.radiusSmall,
                        bool elevated = false,
                      }) => CursorTheme.containerDecoration(
                        backgroundColor: backgroundColor ?? CursorTheme.backgroundTertiary,
                        borderColor: borderColor ?? CursorTheme.borderSecondary,
                        borderRadius: borderRadius,
                        elevated: elevated,
                      ),
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

  // 통합 로그 섹션
  Widget _buildUnifiedLogSection() {
    return Container(
      padding: const EdgeInsets.all(CursorTheme.spacingL),
      child: Column(
        children: [
          // 섹션 헤더
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(CursorTheme.spacingXS),
                decoration: CursorTheme.containerDecoration(
                  backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
                  borderColor: CursorTheme.cursorBlue,
                  borderRadius: CursorTheme.radiusSmall,
                ),
                child: Icon(
                  Icons.terminal,
                  color: CursorTheme.cursorBlue,
                  size: 16,
                ),
              ),
              const SizedBox(width: CursorTheme.spacingS),
              Text(
                '처리 로그',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: CursorTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: CursorTheme.spacingM),
          
          // 현재 작업 상태
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(CursorTheme.spacingS),
            decoration: CursorTheme.containerDecoration(
              backgroundColor: CursorTheme.cursorBlue.withOpacity(0.05),
              borderColor: CursorTheme.cursorBlue,
              borderRadius: CursorTheme.radiusSmall,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '현재 작업',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: CursorTheme.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: CursorTheme.spacingXS),
                Text(
                  _currentOperation,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CursorTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          const SizedBox(height: CursorTheme.spacingM),
          
          // 로그 리스트
          Expanded(
            child: Container(
              decoration: CursorTheme.containerDecoration(
                backgroundColor: CursorTheme.backgroundTertiary,
                borderColor: CursorTheme.borderSecondary,
                borderRadius: CursorTheme.radiusSmall,
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(CursorTheme.spacingS),
                itemCount: _operationLogs.length,
                itemBuilder: (context, index) {
                  final isLatest = index == _operationLogs.length - 1;
                  return Container(
                    margin: const EdgeInsets.only(bottom: CursorTheme.spacingXS),
                    padding: const EdgeInsets.symmetric(
                      horizontal: CursorTheme.spacingS,
                      vertical: CursorTheme.spacingXS,
                    ),
                    decoration: isLatest ? CursorTheme.containerDecoration(
                      backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
                      borderColor: CursorTheme.cursorBlue,
                      borderRadius: CursorTheme.radiusSmall,
                    ) : null,
                    child: Text(
                      _operationLogs[index],
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isLatest ? CursorTheme.cursorBlue : CursorTheme.textSecondary,
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 통합 하단 섹션
  Widget _buildUnifiedBottomSection() {
    return Container(
      padding: const EdgeInsets.all(CursorTheme.spacingL),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: CursorTheme.borderPrimary, width: 1),
        ),
      ),
      child: Row(
        children: [
          // 좌측: 프로그레스 정보
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(CursorTheme.spacingXS),
                      decoration: CursorTheme.containerDecoration(
                        backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
                        borderColor: CursorTheme.cursorBlue,
                        borderRadius: CursorTheme.radiusSmall,
                      ),
                      child: Icon(
                        Icons.trending_up,
                        color: CursorTheme.cursorBlue,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: CursorTheme.spacingS),
                    Text(
                      '처리 진행률',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: CursorTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(_progress * 100).round()}%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: CursorTheme.cursorBlue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CursorTheme.spacingS),
                
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: CursorTheme.borderSecondary,
                  valueColor: AlwaysStoppedAnimation<Color>(CursorTheme.cursorBlue),
                  minHeight: 8,
                ),
                
                const SizedBox(height: CursorTheme.spacingS),
                
                // 단계 표시
                Wrap(
                  spacing: CursorTheme.spacingXS,
                  runSpacing: CursorTheme.spacingXS,
                  children: [
                    _buildProgressStep('음성인식', _progress >= 0.5, _progress >= 0.1),
                    _buildProgressStep('내용요약', _progress >= 1.0, _progress >= 0.6),
                    _buildProgressStep('완료', false, _progress >= 1.0),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(width: CursorTheme.spacingM),
          
          // 우측: 취소 버튼
          Flexible(
            child: ElevatedButton.icon(
              onPressed: () {
                if (kDebugMode) print('❌ ProcessingScreen: 취소 버튼 클릭됨');
                widget.aiService.cancelOperation();
                if (widget.onCancelProcessing != null) {
                  widget.onCancelProcessing!();
                }
              },
              icon: const Icon(Icons.close, size: 16),
              label: const Text('취소'),
              style: ElevatedButton.styleFrom(
                backgroundColor: CursorTheme.error,
                foregroundColor: CursorTheme.textPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: CursorTheme.spacingM,
                  vertical: CursorTheme.spacingS,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
