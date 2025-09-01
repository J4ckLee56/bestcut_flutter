import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../models/theme_group.dart';
import 'video_player_widget.dart';
import 'segment_table_widget.dart';
import 'action_buttons_widget.dart';
import 'export_menu_widget.dart';
import '../utils/ui_constants.dart';
import '../theme/cursor_theme.dart';

class MainContentWidget extends StatefulWidget {
  final AppState appState;
  final BoxDecoration Function({
    Color? backgroundColor,
    Color? borderColor,
    double borderRadius,
    bool elevated,
  }) buildContainerDecoration;
  final VoidCallback onPickVideo;
  final VoidCallback onRecognizeSpeech;
  final VoidCallback onSummarizeScript;
  final void Function(int) onSegmentTap;
  final void Function(int) onSegmentSecondaryTap;
  final void Function(int) onSegmentDoubleTap;
  final void Function(int, String) onFinishEditing;
  final VoidCallback? onExportXML;
  final VoidCallback? onExportFCPXML;
  final VoidCallback? onExportDaVinciXML;
  final VoidCallback? onExportMP4;
  final VoidCallback? onExportSummaryXML;
  final VoidCallback? onTogglePlayPause; // VideoService 콜백 추가
  final VoidCallback? onExportSummaryFCPXML;
  final VoidCallback? onExportSummaryDaVinciXML;
  final VoidCallback? onExportSummaryMP4;

  const MainContentWidget({
    super.key,
    required this.appState,
    required this.buildContainerDecoration,
    required this.onPickVideo,
    required this.onRecognizeSpeech,
    required this.onSummarizeScript,
    required this.onSegmentTap,
    required this.onSegmentSecondaryTap,
    required this.onSegmentDoubleTap,
    required this.onFinishEditing,
    this.onExportXML,
    this.onExportFCPXML,
    this.onExportDaVinciXML,
    this.onExportMP4,
    this.onExportSummaryXML,
    this.onTogglePlayPause,
    this.onExportSummaryFCPXML,
    this.onExportSummaryDaVinciXML,
    this.onExportSummaryMP4,
  });

  @override
  State<MainContentWidget> createState() => _MainContentWidgetState();
}

class _MainContentWidgetState extends State<MainContentWidget> {
  // 좌측 패널의 고정 너비 (픽셀 단위)
  double _leftPanelWidth = 500.0; // 기본값: 500px 고정
  bool _isDragging = false;
  bool _isHovering = false;
  
  // 최소/최대 너비 제한
  static const double _minLeftPanelWidth = 300.0;
  static const double _maxLeftPanelWidth = 800.0;

  @override
  Widget build(BuildContext context) {
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
          // 상단: 비디오 플레이어와 챕터 정보
          Expanded(
            child: Row(
              children: [
                // 좌측: 비디오 플레이어 (상단) + 챕터 정보 (하단) - 고정 너비
                SizedBox(
                  width: _leftPanelWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, // 위쪽 정렬
                        children: [
                          // 비디오 플레이어 섹션 헤더
                          Container(
                            padding: const EdgeInsets.all(CursorTheme.spacingM),
                            child: _buildSectionHeader('비디오 플레이어', Icons.play_circle_outline),
                          ),
                          
                          // 비디오 프리뷰 - 16:9 비율 유지하면서 유연한 크기 조정
                          LayoutBuilder(
                            builder: (context, videoConstraints) {
                              // 사용 가능한 너비에서 마진을 제외한 실제 비디오 너비 계산
                              final availableWidth = videoConstraints.maxWidth - (CursorTheme.spacingM * 2);
                              final videoHeight = availableWidth / (16 / 9); // 16:9 비율로 높이 계산
                              
                              return Container(
                                width: double.infinity,
                                height: videoHeight + 80, // 비디오 + 컨트롤러 높이
                                child: VideoPlayerWidget(
                                  appState: widget.appState,
                                  previewWidth: videoConstraints.maxWidth,
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
                                  onTogglePlayPause: widget.onTogglePlayPause,
                                ),
                              );
                            },
                          ),
                          
                          // 액션 버튼들
                          Container(
                            padding: const EdgeInsets.all(CursorTheme.spacingM),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: CursorTheme.borderPrimary, width: 1),
                              ),
                            ),
                            child: SizedBox(
                              height: 50,
                              child: ActionButtonsWidget(
                                appState: widget.appState,
                                onPickVideo: widget.onPickVideo,
                                onRecognizeSpeech: widget.onRecognizeSpeech,
                                onSummarizeScript: widget.onSummarizeScript,
                              ),
                            ),
                          ),
                          
                          // 하단: 챕터 정보 - 남은 공간 사용
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(CursorTheme.spacingM),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildSectionHeader('챕터 정보', Icons.category),
                                  const SizedBox(height: CursorTheme.spacingS),
                                  
                                  Expanded(
                                    child: _buildChapterInfo(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // 드래그 가능한 구분선
                    _buildResizableDivider(),
                    
                    // 우측: 세그먼트 리스트 (전체 높이)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(CursorTheme.spacingM), // 패딩 축소
                        child: Column(
                          children: [
                            _buildSectionHeader('세그먼트 목록', Icons.list_alt),
                            const SizedBox(height: CursorTheme.spacingS), // 간격 축소
                            
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, segmentConstraints) {
                                  return SegmentTableWidget(
                                    appState: widget.appState,
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
                                    onSegmentTap: widget.onSegmentTap,
                                    onSegmentSecondaryTap: widget.onSegmentSecondaryTap,
                                    onSegmentDoubleTap: widget.onSegmentDoubleTap,
                                    onFinishEditing: widget.onFinishEditing,
                                    previewWidth: segmentConstraints.maxWidth,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  // 드래그 가능한 구분선 위젯
  Widget _buildResizableDivider() {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onPanStart: (details) {
          setState(() => _isDragging = true);
        },
        onPanUpdate: (details) {
          if (!_isDragging) return;
          
          // 새로운 너비 계산 (드래그 위치를 절대 픽셀 값으로)
          final RenderBox renderBox = context.findRenderObject() as RenderBox;
          final localPosition = renderBox.globalToLocal(details.globalPosition);
          final newWidth = localPosition.dx.clamp(_minLeftPanelWidth, _maxLeftPanelWidth);
          
          setState(() {
            _leftPanelWidth = newWidth;
          });
        },
        onPanEnd: (details) {
          setState(() => _isDragging = false);
        },
        child: Container(
          width: 8,
          decoration: BoxDecoration(
            color: _isHovering || _isDragging 
                ? CursorTheme.cursorBlue.withOpacity(0.3)
                : CursorTheme.borderPrimary,
            borderRadius: BorderRadius.circular(2),
          ),
          child: Center(
            child: Container(
              width: 2,
              height: 40,
              decoration: BoxDecoration(
                color: _isHovering || _isDragging 
                    ? CursorTheme.cursorBlue
                    : CursorTheme.borderSecondary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 섹션 헤더 위젯
  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(CursorTheme.spacingXS),
          decoration: CursorTheme.containerDecoration(
            backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
            borderColor: CursorTheme.cursorBlue,
            borderRadius: CursorTheme.radiusSmall,
          ),
          child: Icon(
            icon,
            color: CursorTheme.cursorBlue,
            size: 16,
          ),
        ),
        const SizedBox(width: CursorTheme.spacingS),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: CursorTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  // 개선된 챕터 정보 위젯
  Widget _buildChapterInfo() {
    if (widget.appState.themeGroups.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(CursorTheme.spacingL),
        decoration: CursorTheme.containerDecoration(
          backgroundColor: CursorTheme.backgroundTertiary,
          borderColor: CursorTheme.borderSecondary,
          borderRadius: CursorTheme.radiusSmall,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              color: CursorTheme.textTertiary,
              size: 48,
            ),
            const SizedBox(height: CursorTheme.spacingM),
            Text(
              '챕터 정보가 없습니다',
              style: TextStyle(
                color: CursorTheme.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: CursorTheme.spacingS),
            Text(
              '음성인식과 내용요약을 완료하면\n챕터별 구성과 요약이 표시됩니다',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: CursorTheme.textTertiary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: CursorTheme.containerDecoration(
        backgroundColor: CursorTheme.backgroundTertiary,
        borderColor: CursorTheme.borderSecondary,
        borderRadius: CursorTheme.radiusSmall,
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(CursorTheme.spacingS),
        itemCount: widget.appState.themeGroups.length,
        itemBuilder: (context, index) {
          final group = widget.appState.themeGroups[index];
          return _buildChapterCard(context, group, index);
        },
      ),
    );
  }

  // 개별 챕터 카드
  Widget _buildChapterCard(BuildContext context, ThemeGroup group, int index) {
    // 첫 번째와 마지막 세그먼트에서 시간 구간 계산
    final startTime = group.segments.isNotEmpty ? group.segments.first.startSec : 0.0;
    final endTime = group.segments.isNotEmpty ? group.segments.last.endSec : 0.0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: CursorTheme.spacingS),
      decoration: CursorTheme.containerDecoration(
        backgroundColor: CursorTheme.backgroundSecondary,
        borderColor: CursorTheme.borderSecondary,
        borderRadius: CursorTheme.radiusSmall,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
          onTap: () => _navigateToChapter(group),
          child: Padding(
            padding: const EdgeInsets.all(CursorTheme.spacingM),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 상단: 챕터 번호 + 제목
                Row(
                  children: [
                    // 챕터 번호
                    Container(
                      width: 28,
                      height: 28,
                      decoration: CursorTheme.containerDecoration(
                        backgroundColor: CursorTheme.cursorBlue,
                        borderRadius: 14,
                        glowing: true,
                      ),
                      child: Center(
                        child: Text(
                          '${index + 1}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: CursorTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: CursorTheme.spacingS),
                    
                    // 챕터 제목
                    Expanded(
                      child: Text(
                        group.theme,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: CursorTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    // 네비게이션 아이콘
                    Icon(
                      Icons.arrow_forward_ios,
                      color: CursorTheme.textTertiary,
                      size: 12,
                    ),
                  ],
                ),
                
                const SizedBox(height: CursorTheme.spacingS),
                
                // 타임코드 구간
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: CursorTheme.spacingS,
                    vertical: CursorTheme.spacingXS,
                  ),
                  decoration: CursorTheme.containerDecoration(
                    backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
                    borderColor: CursorTheme.cursorBlue.withOpacity(0.3),
                    borderRadius: CursorTheme.radiusSmall,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.schedule,
                        color: CursorTheme.cursorBlue,
                        size: 14,
                      ),
                      const SizedBox(width: CursorTheme.spacingXS),
                      Text(
                        '${_formatTimeFromSeconds(startTime)} - ${_formatTimeFromSeconds(endTime)}',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: CursorTheme.cursorBlue,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 내용 요약 (있는 경우)
                if (group.summary != null && group.summary!.isNotEmpty) ...[
                  const SizedBox(height: CursorTheme.spacingS),
                  Container(
                    padding: const EdgeInsets.all(CursorTheme.spacingS),
                    decoration: CursorTheme.containerDecoration(
                      backgroundColor: CursorTheme.backgroundTertiary,
                      borderColor: CursorTheme.borderSecondary,
                      borderRadius: CursorTheme.radiusSmall,
                    ),
                    child: Text(
                      group.summary!,
                      style: TextStyle(
                        color: CursorTheme.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else ...[
                  // 요약이 없는 경우 세그먼트 내용으로 미리보기 생성
                  const SizedBox(height: CursorTheme.spacingS),
                  Container(
                    padding: const EdgeInsets.all(CursorTheme.spacingS),
                    decoration: CursorTheme.containerDecoration(
                      backgroundColor: CursorTheme.backgroundTertiary.withOpacity(0.5),
                      borderColor: CursorTheme.borderSecondary.withOpacity(0.5),
                      borderRadius: CursorTheme.radiusSmall,
                    ),
                    child: Text(
                      _generateChapterPreview(group),
                      style: TextStyle(
                        color: CursorTheme.textTertiary,
                        fontSize: 11,
                        height: 1.3,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                
                const SizedBox(height: CursorTheme.spacingS),
                
                // 하단: 세그먼트 수와 지속시간
                Row(
                  children: [
                    // 세그먼트 수
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.format_list_numbered,
                          color: CursorTheme.textTertiary,
                          size: 12,
                        ),
                        const SizedBox(width: CursorTheme.spacingXS),
                        Text(
                          '${group.segments.length}개 세그먼트',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: CursorTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(width: CursorTheme.spacingM),
                    
                    // 지속시간
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timelapse,
                          color: CursorTheme.textTertiary,
                          size: 12,
                        ),
                        const SizedBox(width: CursorTheme.spacingXS),
                        Text(
                          _formatDuration(endTime - startTime),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: CursorTheme.textTertiary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 챕터로 이동
  void _navigateToChapter(ThemeGroup group) {
    if (group.segments.isNotEmpty) {
      // 해당 챕터의 첫 번째 세그먼트로 이동
      final firstSegment = group.segments.first;
      final segmentIndex = widget.appState.segments.indexWhere((s) => s.id == firstSegment.id);
      
      if (segmentIndex != -1) {
        widget.onSegmentTap(segmentIndex);
      }
    }
  }

  // 시간 포맷팅 (초 → hh:mm:ss)
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

  // 지속시간 포맷팅
  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).floor();
    final secs = (seconds % 60).floor();
    
    if (minutes > 0) {
      return '${minutes}분 ${secs}초';
    } else {
      return '${secs}초';
    }
  }

  // 챕터 미리보기 생성 (요약이 없는 경우)
  String _generateChapterPreview(ThemeGroup group) {
    if (group.segments.isEmpty) {
      return '이 챕터에는 내용이 없습니다.';
    }
    
    // 세그먼트들의 텍스트를 합쳐서 미리보기 생성
    final allText = group.segments.map((s) => s.text.trim()).join(' ');
    
    if (allText.length <= 100) {
      return allText;
    }
    
    // 100자로 자르되 단어 단위로 자르기
    final words = allText.split(' ');
    String preview = '';
    for (final word in words) {
      if ((preview + word).length > 97) {
        break;
      }
      if (preview.isNotEmpty) preview += ' ';
      preview += word;
    }
    
    return preview.isEmpty ? allText.substring(0, 97) + '...' : preview + '...';
  }
}
