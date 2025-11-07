import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/app_state.dart';
import '../models/whisper_segment.dart';
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
  final void Function(int, WordSegment)? onWordTap;
  final void Function(int, WordSegment)? onSilenceTap;
  final void Function(int, String) onFinishEditing;
  final double previewWidth;

  const SegmentTableWidget({
    super.key,
    required this.appState,
    required this.buildContainerDecoration,
    required this.onSegmentTap,
    required this.onSegmentSecondaryTap,
    required this.onSegmentDoubleTap,
    this.onWordTap,
    this.onSilenceTap,
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
  final FocusNode _focusNode = FocusNode(); // 키보드 단축키를 위한 FocusNode
  int? _selectedWordSegmentIndex;
  int? _selectedWordIndex;
  int? _selectedSilenceSegmentIndex;
  int? _selectedSilenceIndex;
  
  // 다중 선택 상태
  final Set<int> _selectedSegmentIndices = {};
  int? _dragStartIndex;
  bool _isDragging = false;
  int? _lastHoveredIndex;

  @override
  void initState() {
    super.initState();
    // AppState 변경 감지를 위한 리스너 추가
    widget.appState.addListener(_onAppStateChanged);
  }

  @override
  void didUpdateWidget(covariant SegmentTableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentSegmentIndex = widget.appState.currentSegmentIndex;
    final bool shouldResetWord = _selectedWordSegmentIndex != null &&
        currentSegmentIndex != _selectedWordSegmentIndex;
    final bool shouldResetSilence = _selectedSilenceSegmentIndex != null &&
        currentSegmentIndex != _selectedSilenceSegmentIndex;

    if (shouldResetWord || shouldResetSilence) {
      setState(() {
        if (shouldResetWord) {
          _selectedWordSegmentIndex = null;
          _selectedWordIndex = null;
        }
        if (shouldResetSilence) {
          _selectedSilenceSegmentIndex = null;
          _selectedSilenceIndex = null;
        }
      });
    }
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    _editController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
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

  void _handleWordTap(int segmentIndex, int segmentId, int wordIndex, WordSegment word) {
    if (kDebugMode) {
      print('🖱️ 단어 "${word.word}" 선택됨 (index=$segmentIndex, id=$segmentId, wordIndex=$wordIndex)');
    }

    widget.onSegmentTap(segmentIndex);
    widget.onWordTap?.call(segmentIndex, word);

    setState(() {
      _selectedWordSegmentIndex = segmentIndex;
      _selectedWordIndex = wordIndex;
      _selectedSilenceSegmentIndex = null;
      _selectedSilenceIndex = null;
      // 단어 클릭 시 다중 선택 초기화
      _selectedSegmentIndices.clear();
      _dragStartIndex = null;
    });
  }

  void _handleSilenceTap(int segmentIndex, int silenceIndex, WordSegment silence) {
    if (kDebugMode) {
      print('🖱️ 무음 선택됨 (index=$segmentIndex, silenceIndex=$silenceIndex, range=${silence.startSec.toStringAsFixed(2)}-${silence.endSec.toStringAsFixed(2)}s)');
    }

    widget.onSegmentTap(segmentIndex);
    widget.onSilenceTap?.call(segmentIndex, silence);

    setState(() {
      _selectedWordSegmentIndex = null;
      _selectedWordIndex = null;
      _selectedSilenceSegmentIndex = segmentIndex;
      _selectedSilenceIndex = silenceIndex;
      // 무음칩 클릭 시 다중 선택 초기화
      _selectedSegmentIndices.clear();
      _dragStartIndex = null;
    });
  }
  
  // 키보드 단축키 핸들러
  void _handleKeyPress(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    
    final key = event.logicalKey;
    
    // S키: 세그먼트 분할
    if (key == LogicalKeyboardKey.keyS) {
      _handleSplitSegment();
    }
    // M키: 세그먼트 병합
    else if (key == LogicalKeyboardKey.keyM) {
      _handleMergeSegments();
    }
    // Escape: 선택 취소
    else if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _selectedSegmentIndices.clear();
        _dragStartIndex = null;
        _isDragging = false;
      });
    }
  }
  
  // Shift 키가 눌려있는지 확인
  bool _isShiftPressed(PointerDownEvent event) {
    return HardwareKeyboard.instance.isShiftPressed;
  }
  
  // 세그먼트 분할 처리
  void _handleSplitSegment() {
    // 단어 또는 무음이 선택되어 있어야 함
    if (_selectedWordSegmentIndex != null && _selectedWordIndex != null) {
      // 단어 기준 분할
      final segment = widget.appState.segments[_selectedWordSegmentIndex!];
      final word = segment.words[_selectedWordIndex!];
      
      if (kDebugMode) {
        print('📍 단어 분할 시도:');
        print('  - 세그먼트 인덱스: $_selectedWordSegmentIndex');
        print('  - 단어 인덱스: $_selectedWordIndex');
        print('  - 단어: "${word.word}"');
        print('  - 세그먼트 총 단어 수: ${segment.words.length}');
        print('  - wordIndex <= 0? ${_selectedWordIndex! <= 0}');
      }
      
      final success = widget.appState.splitSegmentAtWord(
        _selectedWordSegmentIndex!,
        _selectedWordIndex!,
      );
      
      if (success) {
        setState(() {
          _selectedWordSegmentIndex = null;
          _selectedWordIndex = null;
        });
        _showSnackBar('✂️ 세그먼트 분할 완료');
      } else {
        _showSnackBar('❌ 세그먼트 분할 실패');
      }
    } else if (_selectedSilenceSegmentIndex != null && _selectedSilenceIndex != null) {
      // 무음 기준 분할
      final success = _splitSegmentAtSilence(
        _selectedSilenceSegmentIndex!,
        _selectedSilenceIndex!,
      );
      
      if (success) {
        setState(() {
          _selectedSilenceSegmentIndex = null;
          _selectedSilenceIndex = null;
        });
        _showSnackBar('✂️ 세그먼트 분할 완료');
      } else {
        _showSnackBar('❌ 세그먼트 분할 실패');
      }
    } else {
      _showSnackBar('분할할 단어 또는 무음을 먼저 선택하세요.');
    }
  }
  
  Future<void> _handleTokenDoubleTap(int segmentIndex, int tokenIndex, WordSegment token) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _TokenEditDialog(
        initialText: token.isSilence ? '' : token.word,
        isSilence: token.isSilence,
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    // 다이얼로그가 완전히 닫힌 뒤에 반영되도록 다음 프레임으로 미룸
    await Future<void>.delayed(Duration.zero);

    if (!mounted) {
      return;
    }

    final bool updated = widget.appState.updateWordToken(segmentIndex, tokenIndex, result);
    if (!updated) {
      _showSnackBar('변경 사항이 없습니다.');
      return;
    }

    final updatedToken = widget.appState.segments[segmentIndex].words[tokenIndex];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      setState(() {
        if (updatedToken.isSilence) {
          _selectedWordSegmentIndex = null;
          _selectedWordIndex = null;
          _selectedSilenceSegmentIndex = segmentIndex;
          _selectedSilenceIndex = tokenIndex;
        } else {
          _selectedSilenceSegmentIndex = null;
          _selectedSilenceIndex = null;
          _selectedWordSegmentIndex = segmentIndex;
          _selectedWordIndex = tokenIndex;
        }
      });

      _showSnackBar(updatedToken.isSilence ? '🔇 무음으로 저장했습니다.' : '✏️ 단어를 수정했습니다.');
    });
  }

  // 무음 기준으로 세그먼트 분할 (무음 뒤에서 분할)
  bool _splitSegmentAtSilence(int segmentIndex, int silenceIndex) {
    final segment = widget.appState.segments[segmentIndex];
    
    // silenceIndex는 이제 words 배열의 인덱스
    // (무음도 words에 포함되어 있음)
    if (silenceIndex < 0 || silenceIndex >= segment.words.length) {
      if (kDebugMode) {
        print('❌ 잘못된 무음 인덱스: $silenceIndex');
      }
      return false;
    }
    
    final silence = segment.words[silenceIndex];
    if (!silence.isSilence) {
      if (kDebugMode) {
        print('❌ 선택된 토큰이 무음이 아닙니다: $silenceIndex');
      }
      return false;
    }
    
    if (kDebugMode) {
      print('📍 무음칩 분할 시도:');
      print('  - 세그먼트 인덱스: $segmentIndex');
      print('  - 무음 인덱스: $silenceIndex');
      print('  - 무음 시작: ${silence.startSec.toStringAsFixed(2)}s');
      print('  - 무음 끝: ${silence.endSec.toStringAsFixed(2)}s');
      print('  - 세그먼트 총 토큰 수: ${segment.words.length}');
      
      // 세그먼트 내 모든 토큰 위치 출력
      print('  - 세그먼트 구조:');
      for (int i = 0; i < segment.words.length; i++) {
        final token = segment.words[i];
        if (token.isSilence) {
          print('    [$i]: 무음 (${token.startSec.toStringAsFixed(2)}s - ${token.endSec.toStringAsFixed(2)}s)');
        } else {
          print('    [$i]: "${token.word}" (${token.startSec.toStringAsFixed(2)}s - ${token.endSec.toStringAsFixed(2)}s)');
        }
      }
    }
    
    // 무음 뒤의 첫 번째 토큰부터 새 세그먼트 시작
    final splitIndex = silenceIndex + 1;
    if (splitIndex >= segment.words.length) {
      if (kDebugMode) {
        print('❌ 무음 뒤에 이어지는 토큰이 없어 분할할 수 없습니다.');
        print('  → 무음 보장 세그먼트 생성 로직 수행');
      }

      final firstWords = segment.words.sublist(0, silenceIndex + 1);
      if (firstWords.length == segment.words.length) {
        if (kDebugMode) {
          print('⚠️ 분할 결과 두 번째 세그먼트가 비게 되므로 취소합니다.');
        }
        return false;
      }

      return widget.appState.splitSegmentAtWord(segmentIndex, firstWords.length);
    }
    
    if (kDebugMode) {
      final nextToken = segment.words[splitIndex];
      final tokenLabel = nextToken.isSilence ? '무음' : '"${nextToken.word}"';
      print('  - 분할 인덱스: $splitIndex');
      print('  - 분할 이후 첫 토큰: $tokenLabel');
      print('  → splitSegmentAtWord 호출 (wordIndex=$splitIndex)');
    }
    
    return widget.appState.splitSegmentAtWord(segmentIndex, splitIndex);
  }
  
  // 세그먼트 병합 처리
  void _handleMergeSegments() {
    if (_selectedSegmentIndices.length < 2) {
      _showSnackBar('병합할 세그먼트를 2개 이상 선택하세요.');
      return;
    }
    
    final success = widget.appState.mergeSegments(_selectedSegmentIndices.toList());
    
    if (success) {
      setState(() {
        _selectedSegmentIndices.clear();
        _dragStartIndex = null;
        _isDragging = false;
      });
      _showSnackBar('📦 세그먼트 병합 완료');
    } else {
      _showSnackBar('❌ 세그먼트 병합 실패');
    }
  }
  
  // 세그먼트 클릭 (Shift 키 지원)
  void _handleSegmentClick(int segmentIndex) {
    // Shift 키가 눌려있으면 범위 선택
    if (HardwareKeyboard.instance.isShiftPressed) {
      setState(() {
        if (_dragStartIndex == null) {
          // 첫 번째 선택
          _dragStartIndex = segmentIndex;
          _selectedSegmentIndices.clear();
          _selectedSegmentIndices.add(segmentIndex);
        } else {
          // 범위 선택
          _selectedSegmentIndices.clear();
          final start = _dragStartIndex! < segmentIndex ? _dragStartIndex! : segmentIndex;
          final end = _dragStartIndex! > segmentIndex ? _dragStartIndex! : segmentIndex;
          
          for (int i = start; i <= end; i++) {
            _selectedSegmentIndices.add(i);
          }
        }
      });
      return;
    }
    
    // Shift 없이 클릭하면 기존 선택 초기화
    setState(() {
      _dragStartIndex = segmentIndex;
      _selectedSegmentIndices.clear();
      _selectedSegmentIndices.add(segmentIndex);
    });
  }
  
  // 드래그 선택 시작
  void _handleDragStart(int segmentIndex) {
    setState(() {
      _isDragging = true;
      _dragStartIndex = segmentIndex;
      _lastHoveredIndex = segmentIndex;
      _selectedSegmentIndices.clear();
      _selectedSegmentIndices.add(segmentIndex);
    });
  }
  
  // 드래그 중 호버
  void _handleDragHover(int segmentIndex) {
    if (!_isDragging || _dragStartIndex == null) return;
    if (_lastHoveredIndex == segmentIndex) return;
    
    setState(() {
      _lastHoveredIndex = segmentIndex;
      _selectedSegmentIndices.clear();
      final start = _dragStartIndex! < segmentIndex ? _dragStartIndex! : segmentIndex;
      final end = _dragStartIndex! > segmentIndex ? _dragStartIndex! : segmentIndex;
      
      for (int i = start; i <= end; i++) {
        _selectedSegmentIndices.add(i);
      }
    });
  }
  
  // 드래그 종료
  void _handleDragEnd() {
    setState(() {
      _isDragging = false;
      _lastHoveredIndex = null;
    });
  }
  
  // 스낵바 표시 헬퍼
  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        backgroundColor: CursorTheme.backgroundSecondary,
      ),
    );
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
    
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyPress,
      autofocus: true,
      child: GestureDetector(
        onTap: () => _focusNode.requestFocus(), // 클릭 시 포커스 요청
        child: Container(
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
                const Spacer(),
                // 단축키 안내
                if (_selectedSegmentIndices.isEmpty && _selectedWordSegmentIndex == null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CursorTheme.spacingXS,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: CursorTheme.textTertiary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                    ),
                    child: Text(
                      '드래그 또는 Shift+클릭: 범위 선택',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: CursorTheme.textTertiary,
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                    ),
                  ),
                if (_selectedWordSegmentIndex != null && _selectedWordIndex != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CursorTheme.spacingXS,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: CursorTheme.cursorBlue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                    ),
                    child: Text(
                      '단축키 S: 선택한 단어 앞에서 분할',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: CursorTheme.cursorBlue,
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                    ),
                  ),
                if (_selectedSilenceSegmentIndex != null && _selectedSilenceIndex != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CursorTheme.spacingXS,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: CursorTheme.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                    ),
                    child: Text(
                      '단축키 S: 선택한 무음 앞에서 분할',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: CursorTheme.warning,
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                    ),
                  ),
                if (_selectedSegmentIndices.length >= 2)
                  Container(
                    margin: const EdgeInsets.only(left: CursorTheme.spacingXS),
                    padding: const EdgeInsets.symmetric(
                      horizontal: CursorTheme.spacingXS,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: CursorTheme.cursorBlueLight.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                    ),
                    child: Text(
                      '단축키 M: ${_selectedSegmentIndices.length}개 세그먼트 병합',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: CursorTheme.cursorBlueLight,
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
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
      ),
    ),
  );
}

  // 개선된 세그먼트 아이템 빌더
  Widget _buildSegmentItem(BuildContext context, int index, bool isSelected, bool isUnifiedSummary) {
    final segment = widget.appState.segments[index];
    
    // 정밀한 시간 비교 (밀리초 단위)
    final currentSec = (widget.appState.currentPosition.inMilliseconds / 1000.0);
    final isPlaying = widget.appState.isPlaying && 
                     currentSec >= segment.startSec &&
                     currentSec < segment.endSec;  // <= 대신 < 사용 (경계 중복 방지)
    
    // 다중 선택 여부 확인
    final bool isMultiSelected = _selectedSegmentIndices.contains(index);
    
    return MouseRegion(
      onEnter: (_) {
        if (_isDragging) {
          _handleDragHover(index);
        }
      },
      child: Listener(
        onPointerDown: (event) {
          // 왼쪽 버튼 + Shift 없음 = 드래그 시작
          if (event.buttons == 1 && !HardwareKeyboard.instance.isShiftPressed) {
            _handleDragStart(index);
          }
        },
        onPointerUp: (_) {
          if (_isDragging) {
            _handleDragEnd();
          }
        },
        child: GestureDetector(
          key: widget.appState.segmentKeys[index],
          behavior: HitTestBehavior.opaque,
          onTap: () {
            // 드래그 중이었으면 탭 무시
            if (_isDragging) {
              _handleDragEnd();
              return;
            }
            
            // Shift 키가 눌려있으면 다중 선택 모드
            if (HardwareKeyboard.instance.isShiftPressed) {
              _handleSegmentClick(index);
            } else {
              // 일반 탭: 비디오 이동
              widget.onSegmentTap(index);
              if (_selectedWordSegmentIndex != null ||
                  _selectedWordIndex != null ||
                  _selectedSilenceSegmentIndex != null ||
                  _selectedSilenceIndex != null) {
                setState(() {
                  _selectedWordSegmentIndex = null;
                  _selectedWordIndex = null;
                  _selectedSilenceSegmentIndex = null;
                  _selectedSilenceIndex = null;
                });
              }
              // 단일 클릭 시 다중 선택 초기화
              setState(() {
                _selectedSegmentIndices.clear();
                _dragStartIndex = null;
              });
            }
          },
          onSecondaryTap: () => _toggleSummarySegment(index),
          onDoubleTap: () => _startEditing(index),
        child: Container(
          margin: const EdgeInsets.only(bottom: CursorTheme.spacingXS),
          decoration: BoxDecoration(
            color: isMultiSelected
                ? CursorTheme.cursorBlueLight.withOpacity(0.2)
                : isPlaying
                    ? CursorTheme.cursorBlue.withOpacity(0.2)
                    : isSelected 
                        ? CursorTheme.cursorBlue.withOpacity(0.1)
                        : isUnifiedSummary
                            ? CursorTheme.warning.withOpacity(0.05)
                            : CursorTheme.backgroundSecondary,
            borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
            border: Border.all(
              color: isMultiSelected
                  ? CursorTheme.cursorBlueLight
                  : isPlaying
                      ? CursorTheme.cursorBlue
                      : isSelected
                          ? CursorTheme.cursorBlue
                          : isUnifiedSummary
                              ? CursorTheme.warning
                              : CursorTheme.borderSecondary,
              width: isMultiSelected || isPlaying || isSelected ? 2 : 1,
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
                  : _buildSegmentWordWrap(
                      context,
                      index,  // 세그먼트 인덱스 전달
                      segment,
                      isActive: isPlaying || isSelected,
                    ),
              ],
            ),
          ),
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

  Widget _buildSegmentWordWrap(
    BuildContext context,
    int segmentIndex,
    WhisperSegment segment, {
    required bool isActive,
  }) {
    final words = segment.words;
    
    final currentPosition = widget.appState.videoController?.value.position;
    final currentSec = (currentPosition?.inMilliseconds ?? 0) / 1000.0;
    
    // 토큰이 없는 경우: 텍스트만 표시
    if (words.isEmpty) {
      return Text(
        segment.text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: isActive ? CursorTheme.textPrimary : CursorTheme.textSecondary,
              height: 1.4,
            ),
        softWrap: true,
      );
    }

    // 단어와 무음을 시간 순서대로 표시 (이미 words에 통합됨)
    final List<Widget> widgets = [];
    
    for (int i = 0; i < words.length; i++) {
      final token = words[i];
      
      final isPlayingToken = currentSec >= token.startSec && currentSec < token.endSec;
      
      if (token.isSilence) {
        // 무음 칩
        final isSelectedSilence = _selectedSilenceSegmentIndex == segmentIndex &&
            _selectedSilenceIndex == i;
        
        widgets.add(_buildSilenceChip(
          context,
          segmentIndex: segmentIndex,
          silenceIndex: i,
          silence: token, // WordSegment를 그대로 전달 (duration getter 있음)
          isPlaying: isPlayingToken,
          isSelected: isSelectedSilence,
        ));
      } else {
        // 단어 칩
        final isSelectedWord = _selectedWordSegmentIndex == segmentIndex && 
            _selectedWordIndex == i;

        widgets.add(_buildWordChip(
          context,
          segmentIndex: segmentIndex,
          segmentId: segment.id,
          wordIndex: i,
          word: token,
          isPlaying: isPlayingToken,
          isSelected: isSelectedWord,
        ));
      }
    }
    
    return Wrap(
      spacing: CursorTheme.spacingXS,
      runSpacing: CursorTheme.spacingXS,
      children: widgets,
    );
  }

  Widget _buildWordChip(
    BuildContext context, {
    required int segmentIndex,
    required int segmentId,
    required int wordIndex,
    required WordSegment word,
    required bool isPlaying,
    required bool isSelected,
  }) {
    final bool isActive = isPlaying || isSelected;

    final Color backgroundColor = isSelected
        ? CursorTheme.cursorBlue.withOpacity(0.28)
        : isPlaying
            ? CursorTheme.cursorBlue.withOpacity(0.16)
            : CursorTheme.backgroundSecondary;

    final Color borderColor = isSelected
        ? CursorTheme.cursorBlue
        : isPlaying
            ? CursorTheme.cursorBlue.withOpacity(0.6)
            : CursorTheme.borderSecondary;

    final double borderWidth = isSelected ? 2.0 : 1.0;
    final Color textColor = isActive ? CursorTheme.cursorBlue : CursorTheme.textPrimary;
    final FontWeight fontWeight = isSelected
        ? FontWeight.w700
        : isPlaying
            ? FontWeight.w600
            : FontWeight.w500;

    return Tooltip(
      message: '${_formatTimeFromSeconds(word.startSec)} ~ ${_formatTimeFromSeconds(word.endSec)}',
      child: GestureDetector(
        onTap: () => _handleWordTap(segmentIndex, segmentId, wordIndex, word),
        onDoubleTap: () => _handleTokenDoubleTap(segmentIndex, wordIndex, word),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CursorTheme.spacingXS,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Text(
            word.word,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: textColor,
                  fontWeight: fontWeight,
                ),
          ),
        ),
      ),
    );
  }

  // 무음 칩 표시 (단어 사이)
  Widget _buildSilenceChip(
    BuildContext context, {
    required int segmentIndex,
    required int silenceIndex,
    required WordSegment silence,
    required bool isPlaying,
    required bool isSelected,
  }) {
    final bool isActive = isPlaying || isSelected;

    final Color backgroundColor = isSelected
        ? CursorTheme.warning.withOpacity(0.35)
        : isPlaying
            ? CursorTheme.warning.withOpacity(0.22)
            : CursorTheme.warning.withOpacity(0.12);

    final Color borderColor = isSelected
        ? CursorTheme.warning
        : CursorTheme.warning.withOpacity(isPlaying ? 0.6 : 0.3);

    final double borderWidth = isSelected ? 2.0 : 1.0;

    final Color labelColor = isActive
        ? CursorTheme.warning
        : CursorTheme.warning.withOpacity(0.85);

    final TextStyle labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: labelColor,
          fontWeight: isSelected
              ? FontWeight.w700
              : isPlaying
                  ? FontWeight.w600
                  : FontWeight.w500,
          fontSize: 10,
        ) ??
        TextStyle(
          color: labelColor,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        );

    return Tooltip(
      message:
          '무음 ${silence.duration.toStringAsFixed(2)}초 (${_formatTimeFromSeconds(silence.startSec)} ~ ${_formatTimeFromSeconds(silence.endSec)})',
      child: GestureDetector(
        onTap: () => _handleSilenceTap(segmentIndex, silenceIndex, silence),
        onDoubleTap: () => _handleTokenDoubleTap(segmentIndex, silenceIndex, silence),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CursorTheme.spacingXS,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.volume_mute_rounded,
                color: labelStyle.color,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text('무음', style: labelStyle),
            ],
          ),
        ),
      ),
    );
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
      // 정밀한 시간 비교 (밀리초 단위)
      final currentTime = widget.appState.currentPosition.inMilliseconds / 1000.0;
      
      for (int i = 0; i < widget.appState.segments.length; i++) {
        final segment = widget.appState.segments[i];
        
        // >= start && < end 사용 (경계 중복 방지)
        if (currentTime >= segment.startSec && currentTime < segment.endSec) {
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
  
  // 시간 포맷팅 헬퍼 메서드 (0.01초 단위까지 표시)
  String _formatTimeFromSeconds(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final remainingSeconds = seconds % 60;
    final secs = remainingSeconds.floor();
    final centiseconds = ((remainingSeconds - secs) * 100).round();
    
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${centiseconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}.${centiseconds.toString().padLeft(2, '0')}';
    }
  }
}

class _TokenEditDialog extends StatefulWidget {
  final String initialText;
  final bool isSilence;

  const _TokenEditDialog({
    required this.initialText,
    required this.isSilence,
  });

  @override
  State<_TokenEditDialog> createState() => _TokenEditDialogState();
}

class _TokenEditDialogState extends State<_TokenEditDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isSilence ? '무음 칩 편집' : '단어 칩 편집'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '내용을 입력하세요 (빈 문자열 → 무음)',
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: CursorTheme.spacingS),
          const Text(
            '입력을 비우면 무음으로 저장됩니다.',
            style: TextStyle(fontSize: 12, color: CursorTheme.textSecondary),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('저장'),
        ),
      ],
    );
  }
}
