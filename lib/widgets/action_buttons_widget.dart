import 'package:flutter/material.dart';
import '../models/app_state.dart';
import '../utils/constants.dart';
import '../utils/ui_constants.dart';
import '../theme/cursor_theme.dart';

class ActionButtonsWidget extends StatelessWidget {
  final AppState appState;
  final VoidCallback onPickVideo;
  final VoidCallback onRecognizeSpeech;
  final VoidCallback onSummarizeScript;

  const ActionButtonsWidget({
    super.key,
    required this.appState,
    required this.onPickVideo,
    required this.onRecognizeSpeech,
    required this.onSummarizeScript,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildCursorButton(
          onPressed: (appState.isRecognizing || appState.isSummarizing) ? null : onPickVideo,
          icon: Icons.folder_open,
          label: '불러오기',
          isEnabled: true,
        ),
        _buildCursorButton(
          onPressed: (appState.isRecognizing || appState.isSummarizing || appState.videoPath == null) ? null : onRecognizeSpeech,
          icon: appState.isRecognizing ? Icons.mic : Icons.record_voice_over,
          label: appState.isRecognizing ? '음성인식 중...' : '음성인식',
          isEnabled: appState.videoPath != null,
          isProcessing: appState.isRecognizing,
        ),
        _buildCursorButton(
          onPressed: (appState.isRecognizing || appState.isSummarizing || appState.segments.isEmpty) ? null : onSummarizeScript,
          icon: appState.isSummarizing ? Icons.hourglass_empty : Icons.summarize,
          label: appState.isSummarizing ? '요약 중...' : '내용요약',
          isEnabled: appState.segments.isNotEmpty,
          isProcessing: appState.isSummarizing,
        ),
      ],
    );
  }

  // Cursor AI 스타일 버튼 빌더
  Widget _buildCursorButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    required bool isEnabled,
    bool isProcessing = false,
  }) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: CursorTheme.spacingXS),
        child: ElevatedButton.icon(
          onPressed: isEnabled ? onPressed : null,
          icon: Icon(
            icon,
            size: 16,
            color: isEnabled ? CursorTheme.textPrimary : CursorTheme.textTertiary,
          ),
          label: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isEnabled ? CursorTheme.textPrimary : CursorTheme.textTertiary,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: isEnabled 
                ? (isProcessing ? CursorTheme.cursorBlue.withOpacity(0.8) : CursorTheme.cursorBlue)
                : CursorTheme.backgroundTertiary,
            foregroundColor: CursorTheme.textPrimary,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: CursorTheme.spacingS,
              vertical: CursorTheme.spacingXS,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
            ),
          ),
        ),
      ),
    );
  }
}




