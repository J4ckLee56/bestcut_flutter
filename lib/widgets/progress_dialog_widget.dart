import 'package:flutter/material.dart';
import 'dart:async';

/// 진행도 다이얼로그
class ProgressDialog extends StatefulWidget {
  final String title;
  final String initialMessage;
  final VoidCallback onCancel;
  final Stream<String> progressStream;

  const ProgressDialog({
    Key? key,
    required this.title,
    required this.initialMessage,
    required this.onCancel,
    required this.progressStream,
  }) : super(key: key);

  // 정적 메서드: 다이얼로그 표시
  static void show(
    BuildContext context, {
    required String title,
    required String initialMessage,
    required VoidCallback onCancel,
    required Stream<String> progressStream,
  }) {
    print('🔍 ProgressDialog.show() 호출됨');
    print('   - title: $title');
    print('   - initialMessage: $initialMessage');
    print('   - context: $context');
    
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          print('🔍 ProgressDialog builder 호출됨');
          return ProgressDialog(
            title: title,
            initialMessage: initialMessage,
            progressStream: progressStream,
            onCancel: onCancel,
          );
        },
      );
      print('✅ ProgressDialog.showDialog() 호출 완료');
    } catch (e) {
      print('❌ ProgressDialog.show() 오류: $e');
    }
  }

  // 정적 메서드: 다이얼로그 닫기
  static void close(BuildContext context) {
    try {
      if (context.mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
        print('✅ ProgressDialog.close() 성공');
      } else {
        print('⚠️ ProgressDialog.close() 실패: context.mounted=${context.mounted}, canPop=${Navigator.of(context).canPop()}');
      }
    } catch (e) {
      print('❌ ProgressDialog.close() 오류: $e');
    }
  }

  @override
  _ProgressDialogState createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<ProgressDialog> {
  String _currentMessage = '';
  double _progress = 0.0;
  StreamSubscription<String>? _subscription;

  @override
  void initState() {
    super.initState();
    _currentMessage = widget.initialMessage;
    
    // 진행 상황 스트림 리스닝
    _subscription = widget.progressStream.listen((message) {
      if (mounted) {
        setState(() {
          _currentMessage = message;
          _progress = _calculateProgress(message);
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  // 진행률 계산 개선
  double _calculateProgress(String message) {
    // 메시지 기반 진행률 계산
    if (message.contains('초기화') || message.contains('설정')) {
      return 0.1;
    } else if (message.contains('FFmpeg') || message.contains('오디오 추출')) {
      return 0.2;
    } else if (message.contains('Whisper') || message.contains('음성 인식')) {
      return 0.4;
    } else if (message.contains('SRT') || message.contains('파싱')) {
      return 0.6;
    } else if (message.contains('AI') || message.contains('분석')) {
      return 0.7;
    } else if (message.contains('챕터') || message.contains('생성')) {
      return 0.8;
    } else if (message.contains('완료') || message.contains('성공')) {
      return 1.0;
    } else if (message.contains('청크') || message.contains('세그먼트')) {
      return 0.3;
    } else if (message.contains('개요') || message.contains('요약')) {
      return 0.5;
    } else if (message.contains('통합') || message.contains('결합')) {
      return 0.7;
    } else if (message.contains('그룹화') || message.contains('분류')) {
      return 0.9;
    }
    
    // 기본 진행률 (점진적 증가)
    return (_progress + 0.05).clamp(0.0, 0.95);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false, // 뒤로가기 버튼 비활성화
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 제목
              Row(
                children: [
                  Icon(
                    widget.title.contains('음성인식') ? Icons.mic : Icons.summarize,
                    color: Colors.blue[600],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // 진행률 표시
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '진행률',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${(_progress * 100).round()}%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[600],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  AnimatedBuilder(
                    animation: AlwaysStoppedAnimation(_progress),
                    builder: (context, child) {
                      return LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
                        minHeight: 8,
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // 메시지
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _currentMessage,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              
              // 취소 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.cancel, size: 18),
                  label: const Text('작업 취소'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
