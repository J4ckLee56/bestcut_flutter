import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/app_state.dart';
import '../models/whisper_segment.dart';
import '../theme/cursor_theme.dart';

class WaveformEditorPanel extends StatefulWidget {
  final AppState appState;
  final double height;
  final VoidCallback onClose;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final void Function(double seconds)? onSeek;
  final VoidCallback? onTogglePlayPause;

  const WaveformEditorPanel({
    super.key,
    required this.appState,
    required this.onClose,
    this.onConfirm,
    this.onCancel,
    this.onSeek,
    this.onTogglePlayPause,
    this.height = 240,
  });

  @override
  State<WaveformEditorPanel> createState() => _WaveformEditorPanelState();
}

class _WaveformEditorPanelState extends State<WaveformEditorPanel> {
  static const double _paddingSec = 1.0;
  static const double _minDb = -60.0;
  static const double _maxDb = 0.0;
  static const double _minWordDuration = 0.05;

  List<AudioEnergyFrame> _frames = const <AudioEnergyFrame>[];
  double _rangeStart = 0.0;
  double _rangeEnd = 0.0;
  double? _segmentStart;
  double? _segmentEnd;
  double _playheadPositionSec = 0.0;
  int? _editingSegmentId;
  List<_EditableToken> _editableTokens = const <_EditableToken>[];
  int _editableTokenCount = 0;
  List<double> _boundaries = const <double>[];
  final GlobalKey _waveformKey = GlobalKey();
  double? _currentLayoutWidth;
  double? _currentTotalRange;
  int? _draggingBoundaryIndex;
  double _dragPointerOffset = 0.0;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onAppStateChanged);
    _rebuildWaveformData();
    _updatePlayhead();
  }

  @override
  void didUpdateWidget(covariant WaveformEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState != widget.appState) {
      oldWidget.appState.removeListener(_onAppStateChanged);
      widget.appState.addListener(_onAppStateChanged);
    }
    _rebuildWaveformData();
    _updatePlayhead();
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    _limitPlaybackToCurrentSegment();
    setState(() {
      _rebuildWaveformData();
      _updatePlayhead();
    });
  }

  void _updatePlayhead() {
    _playheadPositionSec = widget.appState.currentPosition.inMilliseconds / 1000.0;
  }

  void _rebuildWaveformData() {
    final segments = widget.appState.segments;
    final currentIndex = widget.appState.currentSegmentIndex;
    if (currentIndex < 0 || currentIndex >= segments.length) {
      _frames = const <AudioEnergyFrame>[];
      _rangeStart = 0.0;
      _rangeEnd = 0.0;
      _segmentStart = null;
      _segmentEnd = null;
      _editingSegmentId = null;
      _editableTokens = const <_EditableToken>[];
      _boundaries = const <double>[];
      _editableTokenCount = 0;
      return;
    }

    final segment = segments[currentIndex];
    final totalDurationSec = widget.appState.totalDuration.inMilliseconds / 1000.0;
    final prevSegment = currentIndex > 0 ? segments[currentIndex - 1] : null;
    final nextSegment = currentIndex + 1 < segments.length ? segments[currentIndex + 1] : null;

    final double prevEnd = prevSegment?.endSec ?? segment.startSec;
    final double nextStart = nextSegment?.startSec ?? segment.endSec;
    double prevWordStart = prevEnd;
    if (prevSegment != null && prevSegment.words.isNotEmpty) {
      prevWordStart = prevSegment.words.last.startSec;
    }
    double nextWordEnd = nextStart;
    if (nextSegment != null && nextSegment.words.isNotEmpty) {
      nextWordEnd = nextSegment.words.first.endSec;
    }

    final double baseSegmentLength = (segment.endSec - segment.startSec).clamp(0.0001, double.infinity);
    final int tokenCount = segment.words.length;
    final double tokenPadding = tokenCount * 0.05; // 50ms per token
    final double desiredWindow = baseSegmentLength + tokenPadding + (_paddingSec * 2);
    const double minWindow = 3.0;
    const double maxWindow = 12.0;
    final double clampedWindow = desiredWindow.clamp(minWindow, maxWindow);
    final double halfPadding = (clampedWindow - baseSegmentLength) / 2.0;

    final double availableStart = prevSegment != null ? prevWordStart : 0.0;
    final double availableEnd = nextSegment != null
        ? nextWordEnd
        : (totalDurationSec > 0 ? totalDurationSec : segment.endSec + halfPadding);

    final double softStart = math.max(segment.startSec - halfPadding, availableStart);
    final double softEnd = math.max(segment.endSec, math.min(segment.endSec + halfPadding, availableEnd));

    final double rangeStart = math.max(softStart, 0.0);
    final double rangeEnd = math.min(
      softEnd,
      totalDurationSec > 0 ? totalDurationSec : softEnd,
    );

    final bool needsInitialization = _editingSegmentId != segment.id ||
        _editableTokenCount != segment.words.length;

    if (needsInitialization) {
      _initializeEditableTokens(
        segment,
        prevSegment,
        nextSegment,
        rangeStart,
        rangeEnd,
        currentIndex,
      );
    }

    _frames = widget.appState.getEnergyFramesInRange(rangeStart, rangeEnd);
    _rangeStart = rangeStart;
    _rangeEnd = rangeEnd;
    _segmentStart = segment.startSec;
    _segmentEnd = segment.endSec;
  }

  void _initializeEditableTokens(
    WhisperSegment segment,
    WhisperSegment? prevSegment,
    WhisperSegment? nextSegment,
    double rangeStart,
    double rangeEnd,
    int segmentIndex,
  ) {
    _editingSegmentId = segment.id;

    if (segment.words.isEmpty) {
      _editableTokens = const <_EditableToken>[];
      _boundaries = const <double>[];
      _editableTokenCount = 0;
      return;
    }

    final tokens = <_EditableToken>[];

    if (prevSegment != null && prevSegment.words.isNotEmpty) {
      final prevWord = prevSegment.words.last;
      tokens.add(
        _EditableToken(
          originalIndex: prevWord.index,
          segmentId: segmentIndex - 1,
          word: prevWord.word,
          isSilence: prevWord.isSilence,
          score: prevWord.score,
          start: _roundToCentisecond(prevWord.startSec),
          end: _roundToCentisecond(prevWord.endSec),
          isContext: true,
          isEditable: true,
        ),
      );
    } else {
      final double virtualEnd = segment.words.first.startSec;
      tokens.add(
        _EditableToken(
          originalIndex: -1,
          word: '',
          isSilence: true,
          score: 1.0,
          start: _roundToCentisecond(rangeStart),
          end: _roundToCentisecond(virtualEnd),
          isContext: true,
          isEditable: true,
        ),
      );
    }

    for (final word in segment.words) {
      tokens.add(
        _EditableToken(
          originalIndex: word.index,
          segmentId: segmentIndex,
          word: word.word,
          isSilence: word.isSilence,
          score: word.score,
          start: _roundToCentisecond(word.startSec),
          end: _roundToCentisecond(word.endSec),
          isContext: false,
          isEditable: true,
        ),
      );
    }

    if (nextSegment != null && nextSegment.words.isNotEmpty) {
      final nextWord = nextSegment.words.first;
      tokens.add(
        _EditableToken(
          originalIndex: nextWord.index,
          segmentId: segmentIndex + 1,
          word: nextWord.word,
          isSilence: nextWord.isSilence,
          score: nextWord.score,
          start: _roundToCentisecond(nextWord.startSec),
          end: _roundToCentisecond(nextWord.endSec),
          isContext: true,
          isEditable: true,
        ),
      );
    } else {
      final double virtualStart = segment.words.last.endSec;
      tokens.add(
        _EditableToken(
          originalIndex: -1,
          word: '',
          isSilence: true,
          score: 1.0,
          start: _roundToCentisecond(virtualStart),
          end: _roundToCentisecond(rangeEnd),
          isContext: true,
          isEditable: true,
        ),
      );
    }

    _editableTokens = tokens;
    _editableTokenCount = tokens.where((t) => !t.isContext).length;

    _boundaries = List<double>.filled(_editableTokens.length + 1, 0.0);
    for (int i = 0; i < _editableTokens.length; i++) {
      _boundaries[i] = _editableTokens[i].start;
    }
    _boundaries[_boundaries.length - 1] = _editableTokens.last.end;

    _applyBoundariesToTokens();
  }

  void _applyBoundariesToTokens() {
    if (_editableTokens.isEmpty || _boundaries.length != _editableTokens.length + 1) {
      return;
    }

    for (int i = 0; i < _editableTokens.length; i++) {
      _editableTokens[i].start = _roundToCentisecond(_boundaries[i]);
      _editableTokens[i].end = _roundToCentisecond(_boundaries[i + 1]);
    }
  }

  double _roundToCentisecond(double value) {
    return (value * 100).roundToDouble() / 100.0;
  }

  @override
  Widget build(BuildContext context) {
    final hasData =
        _segmentStart != null && _segmentEnd != null && (_frames.isNotEmpty || _editableTokens.isNotEmpty);

    return Container(
      height: widget.height,
      decoration: CursorTheme.containerDecoration(
        backgroundColor: CursorTheme.backgroundTertiary.withOpacity(0.95),
        borderColor: CursorTheme.borderPrimary,
        borderRadius: CursorTheme.radiusLarge,
        elevated: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CursorTheme.spacingL,
                vertical: CursorTheme.spacingM,
              ),
              child: hasData
                  ? _buildWaveformView()
                  : _buildEmptyState(),
            ),
          ),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final currentIndex = widget.appState.currentSegmentIndex;
    final segment = (currentIndex >= 0 && currentIndex < widget.appState.segments.length)
        ? widget.appState.segments[currentIndex]
        : null;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CursorTheme.spacingL,
        vertical: CursorTheme.spacingS,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: CursorTheme.borderSecondary, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.multitrack_audio, color: CursorTheme.cursorBlue),
          const SizedBox(width: CursorTheme.spacingS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '파형 편집',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: CursorTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                if (segment != null)
                  Text(
                    '세그먼트 ${segment.id} | ${segment.startSec.toStringAsFixed(2)}s ~ ${segment.endSec.toStringAsFixed(2)}s',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: CursorTheme.textSecondary,
                        ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '재생/일시정지',
            icon: Icon(
              widget.appState.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
              color: CursorTheme.cursorBlue,
            ),
            onPressed: widget.onTogglePlayPause,
          ),
          IconButton(
            tooltip: '파형 닫기',
            icon: const Icon(Icons.close),
            onPressed: widget.onClose,
          ),
        ],
      ),
    );
  }

  Widget _buildWaveformView() {
    final double totalRange = _rangeEnd - _rangeStart;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        _currentLayoutWidth = width;
        _currentTotalRange = totalRange > 0 ? totalRange : null;

        final List<Widget> children = [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) =>
                  _seekWithinWaveform(details.localPosition.dx, width, totalRange),
              onPanUpdate: (details) =>
                  _seekWithinWaveform(details.localPosition.dx, width, totalRange),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                child: CustomPaint(
                  painter: _WaveformPainter(
                    frames: _frames,
                    rangeStart: _rangeStart,
                    rangeEnd: _rangeEnd,
                    segmentStart: _segmentStart!,
                    segmentEnd: _segmentEnd!,
                    playheadSec: _playheadPositionSec,
                    minDb: _minDb,
                    maxDb: _maxDb,
                  ),
                ),
              ),
            ),
          ),
        ];

        if (totalRange > 0 && _editableTokens.isNotEmpty) {
          const double minChipWidth = 32.0;
          const double chipTop = 12.0;

          for (final token in _editableTokens) {
            final double visualStart = math.max(token.start, _rangeStart);
            final double visualEnd = math.min(token.end, _rangeEnd);
            if (visualEnd <= visualStart) {
              continue;
            }

            final double normalizedStart = (visualStart - _rangeStart) / totalRange;
            final double normalizedEnd = (visualEnd - _rangeStart) / totalRange;
            final double rawLeft = normalizedStart * width;
            final double rawWidth = (normalizedEnd - normalizedStart) * width;
            final double chipWidth = rawWidth.clamp(minChipWidth, width);
            final double chipLeft = rawLeft.clamp(0.0, math.max(0.0, width - chipWidth));

            children.add(
              Positioned(
                left: chipLeft,
                top: chipTop,
                width: chipWidth,
                child: _buildTokenChip(token, chipWidth),
              ),
            );
          }

          if (_boundaries.length >= 3) {
            for (int i = 1; i < _boundaries.length - 1; i++) {
              final double boundary = _boundaries[i];
              final double boundaryX = ((boundary - _rangeStart) / totalRange) * width;
              children.addAll(
                _buildBoundaryHandleWidgets(
                  index: i,
                  x: boundaryX,
                  layoutWidth: width,
                  layoutHeight: height,
                  totalRange: totalRange,
                ),
              );
            }
          }
        }

        return Stack(
          key: _waveformKey,
          clipBehavior: Clip.none,
          children: children,
        );
      },
    );
  }

  Widget _buildTokenChip(_EditableToken token, double availableWidth) {
    final bool isSilence = token.isSilence;
    final bool isContext = token.isContext;
    final bool isEditable = token.isEditable;
    Color borderColor;
    Color backgroundColor;
    Color textColor;

    if (isContext) {
      borderColor = CursorTheme.borderSecondary;
      backgroundColor = CursorTheme.backgroundSecondary.withOpacity(0.45);
      textColor = CursorTheme.textSecondary;
    } else if (!isEditable) {
      borderColor = CursorTheme.borderSecondary;
      backgroundColor = CursorTheme.backgroundSecondary.withOpacity(0.55);
      textColor = CursorTheme.textSecondary;
    } else {
      borderColor = isSilence ? CursorTheme.warning : CursorTheme.cursorBlueLight;
      backgroundColor = borderColor.withOpacity(0.2);
      textColor = CursorTheme.textPrimary;
    }

    String label = token.word;
    if (label.isEmpty) {
      label = isContext ? '…' : (isSilence ? '무음' : '…');
    }

    return SizedBox(
      width: availableWidth,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: Alignment.center,
        constraints: const BoxConstraints(minHeight: 32),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Text(
          label.isEmpty ? '(빈 단어)' : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: textColor,
                fontWeight: FontWeight.w600,
              ),
        ),
      ),
    );
  }

  List<Widget> _buildBoundaryHandleWidgets({
    required int index,
    required double x,
    required double layoutWidth,
    required double layoutHeight,
    required double totalRange,
  }) {
    const double handleTouchWidth = 16.0;
    const double handleVisualWidth = 6.0;
    final double clampedLeft =
        (x - handleTouchWidth / 2).clamp(0.0, math.max(0.0, layoutWidth - handleTouchWidth));
    final double barHeight = math.max((layoutHeight - 24) * 0.6, 16);
    final Widget handle = Positioned(
      left: clampedLeft,
      top: 0,
      width: handleTouchWidth,
      height: layoutHeight,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (details) =>
              _onBoundaryPanStart(index, details.globalPosition, layoutWidth, totalRange),
          onPanUpdate: (details) => _onBoundaryPanUpdate(details.globalPosition),
          onPanEnd: (_) => _onBoundaryPanEnd(),
          child: Center(
            child: Container(
              width: handleVisualWidth,
              height: barHeight,
              decoration: BoxDecoration(
                color: CursorTheme.cursorBlueLight.withOpacity(0.95),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: CursorTheme.cursorBlue, width: 1),
              ),
            ),
          ),
        ),
      ),
    );

    final List<Widget> widgets = [handle];

    if (_draggingBoundaryIndex == index) {
      const double labelOffset = 4.0;
      const double labelHeight = 24.0;
      const double labelMinWidth = 96.0;
      int displayIndex = index;
      if (displayIndex >= _editableTokens.length || !_editableTokens[displayIndex].isEditable) {
        displayIndex = math.max(0, index - 1);
      }
      final displayToken = _editableTokens[displayIndex];
      final String rangeLabel =
          '${displayToken.start.toStringAsFixed(2)}s ~ ${displayToken.end.toStringAsFixed(2)}s';

      final double labelWidth = math.max(labelMinWidth, rangeLabel.length * 6.0 + 20);
      final double labelCenter = clampedLeft + handleTouchWidth / 2;
      final double labelLeft = math.min(
        math.max(0.0, labelCenter - labelWidth / 2),
        math.max(0.0, layoutWidth - labelWidth),
      );

      widgets.add(
        Positioned(
          left: labelLeft,
          top: math.max(0.0, layoutHeight - labelHeight - labelOffset),
          width: labelWidth,
          height: labelHeight,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: CursorTheme.backgroundSecondary.withOpacity(0.95),
              borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
              border: Border.all(color: CursorTheme.borderAccent),
            ),
            child: Text(
              rangeLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: CursorTheme.textPrimary,
                    fontSize: 11,
                  ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  void _onBoundaryPanStart(
    int index,
    Offset globalPosition,
    double layoutWidth,
    double totalRange,
  ) {
    if (_boundaries.length < 3 || totalRange <= 0) {
      _draggingBoundaryIndex = null;
      return;
    }

    final local = _globalToWaveformLocal(globalPosition);
    if (local == null) {
      _draggingBoundaryIndex = null;
      return;
    }

    final double boundaryX = ((_boundaries[index] - _rangeStart) / totalRange)
        .clamp(0.0, 1.0) * layoutWidth;

    _draggingBoundaryIndex = index;
    _dragPointerOffset = local.dx - boundaryX;
  }

  void _onBoundaryPanUpdate(Offset globalPosition) {
    final index = _draggingBoundaryIndex;
    final width = _currentLayoutWidth;
    final totalRange = _currentTotalRange;
    if (index == null || width == null || totalRange == null || totalRange <= 0) return;

    final local = _globalToWaveformLocal(globalPosition);
    if (local == null) return;

    final pointerX = local.dx - _dragPointerOffset;
    _updateBoundaryFromPointer(index, pointerX, width, totalRange);
  }

  void _onBoundaryPanEnd() {
    _draggingBoundaryIndex = null;
    _dragPointerOffset = 0.0;
  }

  void _updateBoundaryFromPointer(
    int index,
    double pointerX,
    double layoutWidth,
    double totalRange,
  ) {
    if (_boundaries.length < 3) return;

    final double clampedX = pointerX.clamp(0.0, layoutWidth);
    double newValue = _rangeStart + (clampedX / layoutWidth) * totalRange;

    final double minValue = _boundaries[index - 1] + _minWordDuration;
    final double maxValue = _boundaries[index + 1] - _minWordDuration;

    newValue = newValue.clamp(minValue, maxValue);
    newValue = _roundToCentisecond(newValue);

    if ((newValue - _boundaries[index]).abs() < 0.0005) {
      return;
    }

    setState(() {
      _boundaries[index] = newValue;
      _applyBoundariesToTokens();
    });
  }

  void _seekWithinWaveform(double dx, double layoutWidth, double totalRange) {
    if (layoutWidth <= 0 || totalRange <= 0) return;

    final double clampedX = dx.clamp(0.0, layoutWidth);
    final double normalized = clampedX / layoutWidth;
    final double targetSec = _rangeStart + normalized * totalRange;
    final double roundedTarget = _roundToCentisecond(targetSec);

    widget.onSeek?.call(roundedTarget);
    widget.appState.currentPosition =
        Duration(milliseconds: (roundedTarget * 1000).round());

    setState(() {
      _playheadPositionSec = roundedTarget;
    });
  }

  Offset? _globalToWaveformLocal(Offset globalPosition) {
    final context = _waveformKey.currentContext;
    if (context == null) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return null;
    return renderObject.globalToLocal(globalPosition);
  }

  void _limitPlaybackToCurrentSegment() {
    final controller = widget.appState.videoController;
    final segment = _currentSegment;
    if (controller == null || !controller.value.isInitialized || segment == null) {
      return;
    }

    if (!controller.value.isPlaying) {
      return;
    }

    final double positionSec = controller.value.position.inMilliseconds / 1000.0;
    final double segmentEnd = segment.endSec;
    final double segmentStart = segment.startSec;

    if (positionSec < segmentStart) {
      controller.seekTo(Duration(milliseconds: (segmentStart * 1000).round()));
      return;
    }

    if (positionSec >= segmentEnd - 0.001) {
      controller.pause();
      widget.appState.isPlaying = false;
      controller.seekTo(Duration(milliseconds: (segmentEnd * 1000).round()));
    }
  }

  WhisperSegment? get _currentSegment {
    final int index = widget.appState.currentSegmentIndex;
    if (index < 0 || index >= widget.appState.segments.length) {
      return null;
    }
    return widget.appState.segments[index];
  }

  void _handleConfirm() {
    final segments = widget.appState.segments;
    final currentIndex = widget.appState.currentSegmentIndex;

    if (_editableTokens.isEmpty || currentIndex < 0 || currentIndex >= segments.length) {
      widget.onConfirm?.call();
      widget.onClose();
      return;
    }

    final editableTokens = _editableTokens.where((token) => !token.isContext).toList(growable: false);
    if (editableTokens.isEmpty) {
      widget.onConfirm?.call();
      widget.onClose();
      return;
    }

    final updatedWords = <WordSegment>[];
    for (int i = 0; i < editableTokens.length; i++) {
      final token = editableTokens[i];
      updatedWords.add(
        WordSegment(
          index: i,
          word: token.word,
          startSec: _roundToCentisecond(token.start),
          endSec: _roundToCentisecond(token.end),
          score: token.score,
          isSilence: token.isSilence,
        ),
      );
    }

    final updatedText = updatedWords
        .where((word) => !word.isSilence && word.word.isNotEmpty)
        .map((word) => word.word)
        .join(' ')
        .trim();

    final updatedSegments = List<WhisperSegment>.from(segments);
    final currentSegment = updatedSegments[currentIndex];

    if (updatedWords.isNotEmpty) {
      // adjust neighboring segments if context tokens were present
      if (_editableTokens.isNotEmpty && _editableTokens.first.isContext) {
        final firstToken = _editableTokens.first;
        if (firstToken.segmentId != null && firstToken.isEditable) {
          final prevIdx = firstToken.segmentId!;
          if (prevIdx >= 0 && prevIdx < updatedSegments.length) {
            final prevSegment = updatedSegments[prevIdx];
            if (prevSegment.words.isNotEmpty) {
              final prevWords = List<WordSegment>.from(prevSegment.words);
              prevWords[prevWords.length - 1] = prevWords.last.copyWith(
                startSec: firstToken.start,
                endSec: firstToken.end,
              );
              updatedSegments[prevIdx] = prevSegment.copyWith(
                words: prevWords,
                endSec: firstToken.end,
              );
            }
          }
        }
      }

      final lastToken = _editableTokens.last;
      if (lastToken.isContext && lastToken.segmentId != null && lastToken.isEditable) {
        final nextIdx = lastToken.segmentId!;
        if (nextIdx >= 0 && nextIdx < updatedSegments.length) {
          final nextSegment = updatedSegments[nextIdx];
          if (nextSegment.words.isNotEmpty) {
            final nextWords = List<WordSegment>.from(nextSegment.words);
            nextWords[0] = nextWords.first.copyWith(
              startSec: lastToken.start,
              endSec: lastToken.end,
            );
            updatedSegments[nextIdx] = nextSegment.copyWith(
              words: nextWords,
              startSec: lastToken.start,
            );
          }
        }
      }
    }

    updatedSegments[currentIndex] = currentSegment.copyWith(
      startSec: updatedWords.first.startSec,
      endSec: updatedWords.last.endSec,
      text: updatedText.isEmpty ? currentSegment.text : updatedText,
      words: updatedWords,
    );

    widget.appState.segments = updatedSegments;

    if (widget.onConfirm != null) {
      widget.onConfirm!();
    } else {
      widget.onClose();
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        widget.appState.energyProfile.isEmpty
            ? '에너지 프로파일 데이터가 없습니다.'
            : '파형을 표시할 세그먼트를 선택해주세요.',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: CursorTheme.textSecondary,
            ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CursorTheme.spacingL,
        vertical: CursorTheme.spacingM,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: CursorTheme.borderSecondary, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: widget.onCancel ?? widget.onClose,
            child: const Text('취소'),
          ),
          const SizedBox(width: CursorTheme.spacingS),
          ElevatedButton(
            onPressed: _editableTokenCount == 0 ? null : _handleConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: CursorTheme.cursorBlue,
              foregroundColor: CursorTheme.textPrimary,
            ),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}

class _EditableToken {
  _EditableToken({
    required this.originalIndex,
    this.segmentId,
    required this.word,
    required this.isSilence,
    required this.score,
    required this.start,
    required this.end,
    this.isContext = false,
    this.isEditable = true,
  });

  final int originalIndex;
  final int? segmentId;
  final String word;
  final bool isSilence;
  final double score;
  double start;
  double end;
  final bool isContext;
  final bool isEditable;

  double get duration => end - start;
}

class _WaveformPainter extends CustomPainter {
  final List<AudioEnergyFrame> frames;
  final double rangeStart;
  final double rangeEnd;
  final double segmentStart;
  final double segmentEnd;
  final double playheadSec;
  final double minDb;
  final double maxDb;

  _WaveformPainter({
    required this.frames,
    required this.rangeStart,
    required this.rangeEnd,
    required this.segmentStart,
    required this.segmentEnd,
    required this.playheadSec,
    required this.minDb,
    required this.maxDb,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final backgroundPaint = Paint()
      ..color = CursorTheme.backgroundSecondary.withOpacity(0.9);
    canvas.drawRect(rect, backgroundPaint);

    if (rangeEnd <= rangeStart) {
      return;
    }

    // 세그먼트 영역 하이라이트
    final segmentPaint = Paint()
      ..color = CursorTheme.cursorBlue.withOpacity(0.1);
    final segmentStartX = ((segmentStart - rangeStart) / (rangeEnd - rangeStart)).clamp(0.0, 1.0) * size.width;
    final segmentEndX = ((segmentEnd - rangeStart) / (rangeEnd - rangeStart)).clamp(0.0, 1.0) * size.width;
    canvas.drawRect(
      Rect.fromLTRB(segmentStartX, 0, segmentEndX, size.height),
      segmentPaint,
    );

    if (frames.isEmpty) {
      final paint = Paint()
        ..color = CursorTheme.borderSecondary
        ..strokeWidth = 1.0;
      final y = size.height / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
      return;
    }

    final waveformPaint = Paint()
      ..color = CursorTheme.cursorBlue
      ..strokeWidth = 2;

    final midY = size.height / 2;
    final totalRange = rangeEnd - rangeStart;

    for (final frame in frames) {
      final x = ((frame.timeSec - rangeStart) / totalRange) * size.width;
      final normalized = _normalize(frame.rmsLevel);
      final amplitude = normalized * size.height * 0.45; // 상/하 대칭 90%
      canvas.drawLine(
        Offset(x, midY - amplitude),
        Offset(x, midY + amplitude),
        waveformPaint,
      );
    }

    // 플레이헤드 표시
    if (playheadSec >= rangeStart && playheadSec <= rangeEnd) {
      final playheadX = ((playheadSec - rangeStart) / totalRange) * size.width;
      final double handleHeight = 14.0;
      final double handleWidth = 16.0;

      final Paint playheadPaint = Paint()
        ..color = CursorTheme.warning
        ..strokeWidth = 2.0;

      // draw handle triangle
      final Path handlePath = Path()
        ..moveTo(playheadX - handleWidth / 2, 0)
        ..lineTo(playheadX + handleWidth / 2, 0)
        ..lineTo(playheadX, handleHeight)
        ..close();
      canvas.drawPath(handlePath, playheadPaint);

      canvas.drawLine(
        Offset(playheadX, handleHeight),
        Offset(playheadX, size.height),
        playheadPaint,
      );
    }
  }

  double _normalize(double rms) {
    final clamped = rms.clamp(minDb, maxDb);
    final normalized = (clamped - minDb) / (maxDb - minDb);
    return normalized.clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return identical(frames, oldDelegate.frames) == false ||
        rangeStart != oldDelegate.rangeStart ||
        rangeEnd != oldDelegate.rangeEnd ||
        segmentStart != oldDelegate.segmentStart ||
        segmentEnd != oldDelegate.segmentEnd ||
        playheadSec != oldDelegate.playheadSec;
  }
}

