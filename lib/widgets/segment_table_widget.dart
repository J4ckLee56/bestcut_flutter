import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../utils/constants.dart';
import '../utils/ui_constants.dart';
import '../theme/cursor_theme.dart';


class SegmentTableWidget extends StatefulWidget {
  final AppState appState;
  final BoxDecoration Function({
    Color? backgroundColor,
    Color? borderColor,
    double borderRadius,
    bool elevated,
  }) buildContainerDecoration;
  final void Function(int) onSegmentTap;
  final void Function(int) onSegmentSecondaryTap;
  final void Function(int) onSegmentDoubleTap;
  final void Function(int, String) onFinishEditing;
  final double previewWidth;

  const SegmentTableWidget({
    super.key,
    required this.appState,
    required this.buildContainerDecoration,
    required this.onSegmentTap,
    required this.onSegmentSecondaryTap,
    required this.onSegmentDoubleTap,
    required this.onFinishEditing,
    required this.previewWidth,
  });

  @override
  State<SegmentTableWidget> createState() => _SegmentTableWidgetState();
}

class _SegmentTableWidgetState extends State<SegmentTableWidget> {
  int? _editingIndex;
  final TextEditingController _editController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // AppState 변경 감지를 위한 리스너 추가
    widget.appState.addListener(_onAppStateChanged);
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    _editController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // AppState 변경 시 호출되는 메서드
  void _onAppStateChanged() {
    if (mounted) {
      setState(() {
        // 재생 중인 세그먼트로 자동 스크롤
        _scrollToPlayingSegment();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 표시할 세그먼트 필터링 (요약 모드일 때는 요약 세그먼트만)
    List<int> displaySegmentIndices = [];
    
    if (widget.appState.isPreviewMode) {
      // 요약 모드: 요약 세그먼트만 표시
      for (int i = 0; i < widget.appState.segments.length; i++) {
        final segment = widget.appState.segments[i];
        final isHighlighted = widget.appState.highlightedSegments.contains(segment.id);
        final isSummarySegment = segment.isSummary ?? false;
        
        if (isHighlighted || isSummarySegment) {
          displaySegmentIndices.add(i);
        }
      }
    } else {
      // 전체 모드: 모든 세그먼트 표시
      displaySegmentIndices = List.generate(widget.appState.segments.length, (index) => index);
    }
    
    return Container(
      decoration: CursorTheme.containerDecoration(
        backgroundColor: CursorTheme.backgroundTertiary,
        borderColor: CursorTheme.borderSecondary,
        borderRadius: CursorTheme.radiusSmall,
      ),
      child: Column(
        children: [
          // 모드 표시 헤더
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(CursorTheme.spacingS),
            decoration: BoxDecoration(
              color: widget.appState.isPreviewMode 
                  ? CursorTheme.warning.withOpacity(0.1)
                  : CursorTheme.backgroundSecondary,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(CursorTheme.radiusSmall),
                topRight: Radius.circular(CursorTheme.radiusSmall),
              ),
              border: Border(
                bottom: BorderSide(
                  color: CursorTheme.borderSecondary,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  widget.appState.isPreviewMode ? Icons.star : Icons.list_alt,
                  color: widget.appState.isPreviewMode ? CursorTheme.warning : CursorTheme.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: CursorTheme.spacingXS),
                Text(
                  widget.appState.isPreviewMode 
                      ? '요약 세그먼트 (${displaySegmentIndices.length}개)'
                      : '전체 세그먼트 (${displaySegmentIndices.length}개)',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: widget.appState.isPreviewMode ? CursorTheme.warning : CursorTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          
          // 세그먼트가 없을 때 표시할 메시지
          if (displaySegmentIndices.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.appState.isPreviewMode ? Icons.star_outline : Icons.list_alt,
                      color: CursorTheme.textTertiary,
                      size: 48,
                    ),
                    const SizedBox(height: CursorTheme.spacingM),
                    Text(
                      widget.appState.isPreviewMode 
                          ? '요약 세그먼트가 없습니다'
                          : '세그먼트가 없습니다',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: CursorTheme.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: CursorTheme.spacingS),
                    Text(
                      widget.appState.isPreviewMode
                          ? '세그먼트를 오른쪽 클릭하여\n요약 세그먼트로 표시하세요'
                          : '동영상을 불러오고 음성인식을 실행하면\n세그먼트가 표시됩니다',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: CursorTheme.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            // 세그먼트 리스트 (위치 인디케이터 포함)
            Expanded(
              child: Stack(
                children: [
                  Scrollbar(
                    controller: widget.appState.segmentScrollController,
                    thumbVisibility: true,
                    trackVisibility: false,
                    thickness: 6,
                    radius: const Radius.circular(CursorTheme.radiusSmall),
                    child: ListView.builder(
                      controller: widget.appState.segmentScrollController,
                      padding: const EdgeInsets.all(CursorTheme.spacingS),
                      itemCount: displaySegmentIndices.length,
                      itemBuilder: (context, listIndex) {
                        final i = displaySegmentIndices[listIndex];
                        
                        // 세그먼트 키가 없으면 생성
                        if (!widget.appState.segmentKeys.containsKey(i)) {
                          widget.appState.segmentKeys[i] = GlobalKey();
                        }
                        
                        final isSelected = i == widget.appState.currentSegmentIndex;
                        final isHighlighted = widget.appState.highlightedSegments.contains(widget.appState.segments[i].id);
                        final isSummarySegment = widget.appState.segments[i].isSummary ?? false;
                        // 하이라이트와 요약 세그먼트를 통합 (둘 중 하나라도 true면 요약으로 처리)
                        final isUnifiedSummary = isHighlighted || isSummarySegment;
                        
                        return _buildSegmentItem(context, i, isSelected, isUnifiedSummary);
                      },
                    ),
                  ),
                  
                  // 현재 하이라이트된 세그먼트 위치 인디케이터
                  if (widget.appState.currentSegmentIndex >= 0 && 
                      widget.appState.currentSegmentIndex < widget.appState.segments.length)
                    _buildPositionIndicator(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 개선된 세그먼트 아이템 빌더
  Widget _buildSegmentItem(BuildContext context, int index, bool isSelected, bool isUnifiedSummary) {
    final segment = widget.appState.segments[index];
    final isPlaying = widget.appState.isPlaying && 
                     widget.appState.currentPosition.inSeconds >= segment.startSec &&
                     widget.appState.currentPosition.inSeconds <= segment.endSec;
    
    return GestureDetector(
      key: widget.appState.segmentKeys[index],
      onTap: () => widget.onSegmentTap(index),
      onSecondaryTap: () => _toggleSummarySegment(index),
      onDoubleTap: () => _startEditing(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: CursorTheme.spacingXS),
        decoration: BoxDecoration(
          color: isPlaying
              ? CursorTheme.cursorBlue.withOpacity(0.2)
              : isSelected 
                  ? CursorTheme.cursorBlue.withOpacity(0.1)
                  : isUnifiedSummary
                      ? CursorTheme.warning.withOpacity(0.05)
                      : CursorTheme.backgroundSecondary,
          borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
          border: Border.all(
            color: isPlaying
                ? CursorTheme.cursorBlue
                : isSelected
                    ? CursorTheme.cursorBlue
                    : isUnifiedSummary
                        ? CursorTheme.warning
                        : CursorTheme.borderSecondary,
            width: isPlaying || isSelected ? 2 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(CursorTheme.spacingS),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단: 시간 정보 + 요약 표시
              Row(
                children: [
                  // 시간 정보
                  Expanded(
                    child: Text(
                      '${_formatTimeFromSeconds(segment.startSec)} - ${_formatTimeFromSeconds(segment.endSec)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isPlaying || isSelected ? CursorTheme.cursorBlue : CursorTheme.textTertiary,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  
                  // 요약 세그먼트 표시
                  if (isUnifiedSummary)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: CursorTheme.spacingXS,
                        vertical: 2,
                      ),
                      decoration: CursorTheme.containerDecoration(
                        backgroundColor: CursorTheme.warning.withOpacity(0.1),
                        borderColor: CursorTheme.warning,
                        borderRadius: CursorTheme.radiusSmall,
                      ),
                      child: Text(
                        '요약',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: CursorTheme.warning,
                          fontWeight: FontWeight.w600,
                          fontSize: 9,
                        ),
                      ),
                    ),
                    
                  // 재생 중 표시
                  if (isPlaying)
                    Container(
                      margin: const EdgeInsets.only(left: CursorTheme.spacingXS),
                      padding: const EdgeInsets.symmetric(
                        horizontal: CursorTheme.spacingXS,
                        vertical: 2,
                      ),
                      decoration: CursorTheme.containerDecoration(
                        backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
                        borderColor: CursorTheme.cursorBlue,
                        borderRadius: CursorTheme.radiusSmall,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_arrow,
                            color: CursorTheme.cursorBlue,
                            size: 10,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            '재생중',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: CursorTheme.cursorBlue,
                              fontWeight: FontWeight.w600,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: CursorTheme.spacingXS),
              
              // 세그먼트 텍스트 (편집 가능)
              _editingIndex == index 
                  ? _buildEditingTextField(index)
                  : Text(
                      segment.text,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isPlaying || isSelected ? CursorTheme.textPrimary : CursorTheme.textSecondary,
                        height: 1.4,
                      ),
                      softWrap: true,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  // 편집용 텍스트필드
  Widget _buildEditingTextField(int index) {
    return TextField(
      controller: _editController,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: CursorTheme.textPrimary,
        height: 1.4,
      ),
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
          borderSide: BorderSide(color: CursorTheme.cursorBlue),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
          borderSide: BorderSide(color: CursorTheme.cursorBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.all(CursorTheme.spacingS),
        fillColor: CursorTheme.backgroundSecondary,
        filled: true,
      ),
      maxLines: null,
      autofocus: true,
      onSubmitted: (value) => _finishEditing(index, value),
      onTapOutside: (_) => _finishEditing(index, _editController.text),
    );
  }

  // 편집 시작
  void _startEditing(int index) {
    setState(() {
      _editingIndex = index;
      _editController.text = widget.appState.segments[index].text;
    });
  }

  // 편집 완료
  void _finishEditing(int index, String newText) {
    if (_editingIndex == index) {
      setState(() {
        _editingIndex = null;
      });
      widget.onFinishEditing(index, newText);
    }
  }

  // 요약 세그먼트 토글
  void _toggleSummarySegment(int index) {
    setState(() {
      final segment = widget.appState.segments[index];
      segment.isSummary = !(segment.isSummary ?? false);
      // highlightedSegments에도 동기화
      if (segment.isSummary == true) {
        if (!widget.appState.highlightedSegments.contains(segment.id)) {
          widget.appState.highlightedSegments.add(segment.id);
        }
      } else {
        widget.appState.highlightedSegments.remove(segment.id);
      }
    });
    widget.appState.notifyListeners();
  }

  // 실시간 하이라이트 및 자동 스크롤
  void _scrollToPlayingSegment() {
    if (widget.appState.isPlaying) {
      final currentTime = widget.appState.currentPosition.inSeconds;
      for (int i = 0; i < widget.appState.segments.length; i++) {
        final segment = widget.appState.segments[i];
        if (currentTime >= segment.startSec && currentTime <= segment.endSec) {
          // 현재 재생 중인 세그먼트 인덱스 업데이트
          if (widget.appState.currentSegmentIndex != i) {
            widget.appState.currentSegmentIndex = i;
          }
          
          // 현재 재생 중인 세그먼트로 스크롤
          final key = widget.appState.segmentKeys[i];
          if (key?.currentContext != null) {
            Scrollable.ensureVisible(
              key!.currentContext!,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
          break;
        }
      }
    }
  }

  // 현재 위치 인디케이터 빌더
  Widget _buildPositionIndicator() {
    final totalSegments = widget.appState.segments.length;
    final currentIndex = widget.appState.currentSegmentIndex;
    
    if (totalSegments == 0 || currentIndex < 0) {
      return const SizedBox.shrink();
    }
    
    // 전체 높이에서 현재 위치 비율 계산
    final progress = currentIndex / (totalSegments - 1);
    
    return Positioned(
      right: 2, // 스크롤바 옆에 위치
      top: 0,
      bottom: 0,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final indicatorPosition = (constraints.maxHeight - 40) * progress + 20;
          
          return Container(
            width: 3,
            height: constraints.maxHeight,
            child: Stack(
              children: [
                // 현재 위치 인디케이터
                Positioned(
                  top: indicatorPosition - 10,
                  child: Container(
                    width: 3,
                    height: 20,
                    decoration: BoxDecoration(
                      color: CursorTheme.cursorBlue,
                      borderRadius: BorderRadius.circular(1.5),
                      boxShadow: [
                        BoxShadow(
                          color: CursorTheme.cursorBlue.withOpacity(0.5),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
                
                // 현재 세그먼트 번호 표시 (선택적)
                if (totalSegments <= 50) // 세그먼트가 많지 않을 때만 표시
                  Positioned(
                    top: indicatorPosition - 5,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: CursorTheme.cursorBlue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${currentIndex + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  // 시간 포맷팅 헬퍼 메서드
  String _formatTimeFromSeconds(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final secs = (seconds % 60).floor();
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
  }
}
