import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import '../models/app_state.dart';
import '../utils/constants.dart';
import '../utils/ui_constants.dart';
import '../theme/cursor_theme.dart';

class VideoPlayerWidget extends StatefulWidget {
  final AppState appState;
  final double previewWidth;
  final BoxDecoration Function({
    Color? backgroundColor,
    Color? borderColor,
    double borderRadius,
    bool elevated,
  }) buildContainerDecoration;
  final bool centerPlayButton; // 프로세싱 화면 전용 옵션
  final bool hideControls; // 프로세싱 화면에서 컨트롤러 숨김 옵션
  final bool hideTitle; // 동영상 제목 숨김 옵션
  final VoidCallback? onTogglePlayPause; // VideoService 콜백 추가

  const VideoPlayerWidget({
    super.key,
    required this.appState,
    required this.previewWidth,
    required this.buildContainerDecoration,
    this.centerPlayButton = false, // 기본값은 false
    this.hideControls = false, // 기본값은 false
    this.hideTitle = false, // 기본값은 false
    this.onTogglePlayPause, // 콜백 추가
  });

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  Timer? _timer;
  bool _isSummaryMode = false; // 요약 모드 상태
  bool _forceRedraw = false; // 강제 다시 그리기 플래그

  @override
  void initState() {
    super.initState();
    _startTimer();
    
    // 동영상 컨트롤러가 이미 초기화되어 있다면 첫 프레임 확인
    _ensureFirstFrameDisplay();
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // AppState가 변경되었거나 새로운 동영상이 로드되었을 때 첫 프레임 확인
    if (oldWidget.appState != widget.appState) {
      // 약간의 지연 후 첫 프레임 확인 (위젯 업데이트 완료 후)
      Future.delayed(const Duration(milliseconds: 50), () {
        _ensureFirstFrameDisplay();
      });
    }
    
    // 동영상 컨트롤러가 새로 초기화되었을 때도 확인
    if (oldWidget.appState.videoController != widget.appState.videoController &&
        widget.appState.videoController != null &&
        widget.appState.videoController!.value.isInitialized) {
      Future.delayed(const Duration(milliseconds: 50), () {
        _ensureFirstFrameDisplay();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted && widget.appState.videoController != null && 
          widget.appState.videoController!.value.isInitialized) {
        setState(() {
          // 현재 재생 위치 업데이트
          widget.appState.currentPosition = widget.appState.videoController!.value.position;
          // 전체 길이 업데이트
          if (widget.appState.totalDuration == null) {
            widget.appState.totalDuration = widget.appState.videoController!.value.duration;
          }
        });
        
        // 요약 모드일 때는 별도 처리 없이 기본 위치 업데이트만 수행
      }
    });
  }

  // 첫 프레임 표시 확인
  void _ensureFirstFrameDisplay() async {
    if (widget.appState.videoController != null && 
        widget.appState.videoController!.value.isInitialized) {
      try {
        print('🎬 VideoPlayerWidget: 첫 프레임 표시 시작...');
        
        // 1단계: 첫 프레임으로 이동
        await widget.appState.videoController!.seekTo(Duration.zero);
        
        // 2단계: 프레임을 실제로 렌더링하기 위해 매우 짧은 재생
        await widget.appState.videoController!.play();
        await Future.delayed(const Duration(milliseconds: 50));
        await widget.appState.videoController!.pause();
        await widget.appState.videoController!.seekTo(Duration.zero);
        
        // 3단계: 여러 번의 setState로 강제 UI 업데이트
        if (mounted) {
          setState(() {
            widget.appState.currentPosition = Duration.zero;
            widget.appState.isPlaying = false;
          });
          
          // 추가 setState로 위젯 트리 강제 재빌드
          await Future.delayed(const Duration(milliseconds: 50));
          if (mounted) {
            setState(() {
              _forceRedraw = !_forceRedraw; // 강제 다시 그리기 토글
            });
          }
          
          widget.appState.notifyListeners();
          print('🎬 VideoPlayerWidget: 첫 프레임 강제 렌더링 및 다중 UI 업데이트 완료 (강제 다시 그리기: $_forceRedraw)');
        }
      } catch (e) {
        print('❌ VideoPlayerWidget: 첫 프레임 표시 중 오류: $e');
      }
    } else {
      print('⚠️ VideoPlayerWidget: 컨트롤러가 없거나 초기화되지 않음');
    }
  }

    @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      child: Column(
        children: [
          // 영상 프리뷰 영역 (16:9 비율 유지하면서 재생바와 동일한 마진)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: CursorTheme.spacingM), // 재생바와 동일한 마진
            child: AspectRatio(
              aspectRatio: 16 / 9, // 16:9 비율 강제 적용
              child: Container(
                width: double.infinity,
                decoration: CursorTheme.containerDecoration(
                  backgroundColor: CursorTheme.backgroundTertiary,
                  borderColor: CursorTheme.borderSecondary,
                  borderRadius: CursorTheme.radiusSmall,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                  child: Stack(
                    children: [
                    // 동영상 플레이어
                    widget.appState.videoController != null && widget.appState.videoController!.value.isInitialized
                        ? Container(
                            width: double.infinity,
                            height: double.infinity,
                            color: Colors.black,
                            child: FittedBox(
                              fit: BoxFit.cover, // contain에서 cover로 변경하여 영역을 꽉 채움
                              child: SizedBox(
                                width: widget.appState.videoController!.value.size.width,
                                height: widget.appState.videoController!.value.size.height,
                                child: RepaintBoundary(
                                  key: Key('video_player_${widget.appState.videoController.hashCode}_${_forceRedraw}'),
                                  child: VideoPlayer(widget.appState.videoController!),
                                ),
                              ),
                            ),
                          )
                        : Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.video_library_outlined,
                                  size: 64,
                                  color: CursorTheme.textTertiary,
                                ),
                                const SizedBox(height: CursorTheme.spacingM),
                                Text(
                                  '비디오 프리뷰',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: CursorTheme.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                    

                    
                    // 중앙 재생 버튼
                    if (widget.appState.videoController != null && widget.appState.videoController!.value.isInitialized)
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: CursorTheme.containerDecoration(
                            backgroundColor: CursorTheme.backgroundSecondary.withOpacity(0.9),
                            borderColor: widget.appState.isPreviewMode 
                                ? CursorTheme.warning 
                                : CursorTheme.cursorBlue,
                            borderRadius: 32,
                            glowing: true,
                          ),
                          child: IconButton(
                            onPressed: () {
                              // VideoService의 togglePlayPause를 통해 처리
                              if (widget.onTogglePlayPause != null) {
                                widget.onTogglePlayPause!();
                              } else {
                                // 콜백이 없으면 기본 동작 (fallback)
                                if (widget.appState.isPlaying) {
                                  widget.appState.videoController?.pause();
                                  widget.appState.isPlaying = false;
                                } else {
                                  widget.appState.videoController?.play();
                                  widget.appState.isPlaying = true;
                                }
                                widget.appState.notifyListeners();
                              }
                            },
                            icon: Icon(
                              widget.appState.isPlaying ? Icons.pause : Icons.play_arrow,
                              size: 32,
                              color: widget.appState.isPreviewMode 
                                  ? CursorTheme.warning 
                                  : CursorTheme.cursorBlue,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          
          // 컴팩트한 비디오 컨트롤러 (hideControls가 false일 때만 표시)
          if (!widget.hideControls)
            Container(
              margin: const EdgeInsets.fromLTRB(
                CursorTheme.spacingM, 
                CursorTheme.spacingXS, 
                CursorTheme.spacingM, 
                0
              ), // 좌우 마진 추가하여 재생바가 너무 늘어나지 않도록
              padding: const EdgeInsets.symmetric(
                horizontal: CursorTheme.spacingS,
                vertical: CursorTheme.spacingXS,
              ),
              decoration: CursorTheme.containerDecoration(
                backgroundColor: CursorTheme.backgroundTertiary,
                borderColor: CursorTheme.borderSecondary,
                borderRadius: CursorTheme.radiusSmall,
              ),
              child: widget.appState.videoController != null && widget.appState.videoController!.value.isInitialized
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 재생바 (요약 모드일 때는 요약 세그먼트 기반)
                        widget.appState.isPreviewMode 
                            ? _buildSummaryProgressBar() 
                            : _buildRegularProgressBar(),
                        
                        // 시간 표시 (요약 모드일 때는 세그먼트 정보)
                        widget.appState.isPreviewMode 
                            ? _buildSummaryTimeDisplay() 
                            : _buildRegularTimeDisplay(),
                      ],
                    )
                  : Container(
                      height: 40,
                      child: Center(
                        child: Text(
                          '비디오가 로드되지 않았습니다',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: CursorTheme.textTertiary,
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }


  // 재생바 이동 시 해당 세그먼트 업데이트
  void _updateCurrentSegmentFromSeekPosition(double positionInSeconds) {
    for (int i = 0; i < widget.appState.segments.length; i++) {
      final segment = widget.appState.segments[i];
      if (positionInSeconds >= segment.startSec && positionInSeconds <= segment.endSec) {
        if (widget.appState.currentSegmentIndex != i) {
          widget.appState.currentSegmentIndex = i;
          // 세그먼트 테이블에서 스크롤도 업데이트되도록 알림
          widget.appState.notifyListeners();
        }
        break;
      }
    }
  }

  // 일반 재생바 빌더
  Widget _buildRegularProgressBar() {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: CursorTheme.cursorBlue,
        inactiveTrackColor: CursorTheme.borderSecondary,
        thumbColor: CursorTheme.cursorBlue,
        overlayColor: CursorTheme.cursorBlue.withOpacity(0.2),
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      child: Slider(
        value: widget.appState.currentPosition.inMilliseconds.toDouble(),
        min: 0.0,
        max: (widget.appState.totalDuration ?? Duration.zero).inMilliseconds.toDouble(),
        onChanged: (value) {
          final newPosition = Duration(milliseconds: value.toInt());
          widget.appState.videoController?.seekTo(newPosition);
          widget.appState.currentPosition = newPosition;
          
          // 새로운 위치에 해당하는 세그먼트 찾기 및 업데이트
          _updateCurrentSegmentFromSeekPosition(newPosition.inSeconds.toDouble());
          
          widget.appState.notifyListeners();
        },
      ),
    );
  }

  // 요약 모드 재생바 빌더 (네비게이션 버튼 포함)
  Widget _buildSummaryProgressBar() {
    final summarySegmentCount = widget.appState.summarySegmentIndices.length;
    final currentSummaryIndex = widget.appState.currentSummarySegmentIndex;
    
    return Row(
      children: [
        // 이전 세그먼트 버튼
        IconButton(
          onPressed: currentSummaryIndex > 0 ? () {
            _navigateToSummarySegment(currentSummaryIndex - 1);
          } : null,
          icon: Icon(
            Icons.skip_previous,
            size: 16,
            color: currentSummaryIndex > 0 ? CursorTheme.warning : CursorTheme.textTertiary,
          ),
        ),
        
        // 진행 표시바 (클릭 불가)
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: CursorTheme.borderSecondary,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: summarySegmentCount > 0 
                  ? (currentSummaryIndex + 1) / summarySegmentCount 
                  : 0.0,
              child: Container(
                decoration: BoxDecoration(
                  color: CursorTheme.warning,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        
        // 다음 세그먼트 버튼
        IconButton(
          onPressed: currentSummaryIndex < summarySegmentCount - 1 ? () {
            _navigateToSummarySegment(currentSummaryIndex + 1);
          } : null,
          icon: Icon(
            Icons.skip_next,
            size: 16,
            color: currentSummaryIndex < summarySegmentCount - 1 ? CursorTheme.warning : CursorTheme.textTertiary,
          ),
        ),
      ],
    );
  }
  
  // 요약 세그먼트 네비게이션
  void _navigateToSummarySegment(int summaryIndex) {
    if (summaryIndex >= 0 && summaryIndex < widget.appState.summarySegmentIndices.length) {
      final targetSegmentIndex = widget.appState.summarySegmentIndices[summaryIndex];
      final segment = widget.appState.segments[targetSegmentIndex];
      
      // 해당 요약 세그먼트로 이동
      widget.appState.currentSegmentIndex = targetSegmentIndex;
      widget.appState.currentSummarySegmentIndex = summaryIndex;
      
      final newPosition = Duration(milliseconds: (segment.startSec * 1000).round());
      widget.appState.videoController?.seekTo(newPosition);
      widget.appState.currentPosition = newPosition;
      
      widget.appState.notifyListeners();
      
      print('🎯 요약 세그먼트 ${summaryIndex + 1}/${widget.appState.summarySegmentIndices.length}로 이동');
    }
  }
  
  // 전체 → 요약 모드 전환
  void _switchToSummaryMode() {
    print('🔄 전체 → 요약 모드 전환 시작');
    
    // 1. 재생 중이면 일시정지
    bool wasPlaying = widget.appState.isPlaying;
    if (wasPlaying && widget.appState.videoController != null) {
      widget.appState.videoController!.pause();
      widget.appState.isPlaying = false;
      print('⏸️ 재생 중지');
    }
    
    // 2. 현재 재생 시간 기준으로 가장 가까운 요약 세그먼트 찾기
    final currentTime = widget.appState.currentPosition.inMilliseconds / 1000.0;
    final nearestSummaryIndex = _findNearestSummarySegment(currentTime);
    
    // 3. 요약 모드 활성화
    setState(() {
      widget.appState.isPreviewMode = true;
    });
    
    // 4. 가장 가까운 요약 세그먼트로 이동
    if (nearestSummaryIndex >= 0) {
      final segment = widget.appState.segments[nearestSummaryIndex];
      widget.appState.currentSegmentIndex = nearestSummaryIndex;
      widget.appState.updateCurrentSummarySegmentIndex(nearestSummaryIndex);
      
      final newPosition = Duration(milliseconds: (segment.startSec * 1000).round());
      widget.appState.videoController?.seekTo(newPosition);
      widget.appState.currentPosition = newPosition;
      
      print('🎯 가장 가까운 요약 세그먼트 ${nearestSummaryIndex + 1}로 이동 (ID: ${segment.id})');
    }
    
    widget.appState.notifyListeners();
    print('✅ 요약 모드 전환 완료');
  }
  
  // 요약 → 전체 모드 전환
  void _switchToFullMode() {
    print('🔄 요약 → 전체 모드 전환 시작');
    
    // 1. 재생 중이면 일시정지
    bool wasPlaying = widget.appState.isPlaying;
    if (wasPlaying && widget.appState.videoController != null) {
      widget.appState.videoController!.pause();
      widget.appState.isPlaying = false;
      print('⏸️ 재생 중지');
    }
    
    // 2. 전체 모드 활성화 (현재 하이라이트된 세그먼트 유지)
    setState(() {
      widget.appState.isPreviewMode = false;
      widget.appState.notifyListeners();
    });
    
    print('✅ 전체 모드 전환 완료 (세그먼트 ${widget.appState.currentSegmentIndex + 1} 유지)');
  }
  
  // 현재 시간 기준으로 가장 가까운 요약 세그먼트 찾기
  int _findNearestSummarySegment(double currentTime) {
    print('🔍 현재 시간 ${currentTime.toStringAsFixed(1)}s 기준으로 가장 가까운 요약 세그먼트 검색');
    
    int nearestIndex = -1;
    double minDistance = double.infinity;
    
    for (int i = 0; i < widget.appState.segments.length; i++) {
      final segment = widget.appState.segments[i];
      final isHighlighted = widget.appState.highlightedSegments.contains(segment.id);
      final isSummarySegment = segment.isSummary ?? false;
      
      if (isHighlighted || isSummarySegment) {
        // 세그먼트 중간 지점 계산
        final segmentMidTime = (segment.startSec + segment.endSec) / 2;
        final distance = (currentTime - segmentMidTime).abs();
        
        print('  요약 세그먼트 ${i + 1}: 중간시간=${segmentMidTime.toStringAsFixed(1)}s, 거리=${distance.toStringAsFixed(1)}s');
        
        if (distance < minDistance) {
          minDistance = distance;
          nearestIndex = i;
        }
      }
    }
    
    if (nearestIndex >= 0) {
      print('✅ 가장 가까운 요약 세그먼트: ${nearestIndex + 1} (거리: ${minDistance.toStringAsFixed(1)}s)');
    } else {
      print('❌ 요약 세그먼트를 찾을 수 없음');
    }
    
    return nearestIndex;
  }

  // 일반 시간 표시 빌더
  Widget _buildRegularTimeDisplay() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          _formatDuration(widget.appState.currentPosition),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: CursorTheme.textTertiary,
            fontFamily: 'monospace',
            fontSize: 10,
          ),
        ),
        Text(
          _formatDuration(widget.appState.totalDuration ?? Duration.zero),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: CursorTheme.textTertiary,
            fontFamily: 'monospace',
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  // 요약 모드 시간 표시 빌더
  Widget _buildSummaryTimeDisplay() {
    final summarySegmentCount = widget.appState.summarySegmentIndices.length;
    final currentSummaryIndex = widget.appState.currentSummarySegmentIndex;
    final totalSummaryDuration = widget.appState.totalSummaryDuration;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          '${currentSummaryIndex + 1}/$summarySegmentCount',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: CursorTheme.warning,
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          '요약 ${_formatDuration(totalSummaryDuration)}',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: CursorTheme.warning,
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
  
  // 시간 포맷팅 헬퍼 메서드 (밀리초 포함)
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    final milliseconds = (duration.inMilliseconds.remainder(1000) / 10).floor(); // 0-99 (0.01초 단위)
    final centiseconds = twoDigits(milliseconds);
    
    if (duration.inHours > 0) {
      return '$hours:$minutes:$seconds.$centiseconds';
    } else {
      return '$minutes:$seconds.$centiseconds';
    }
  }
}
