/// Whisper 음성인식 결과를 담는 세그먼트 모델
class WhisperSegment {
  final int id;
  final double startSec;
  final double endSec;
  String text; // 편집 가능하도록 final 제거
  final double confidence;
  bool? isSummary; // 요약 세그먼트 여부

  WhisperSegment({
    required this.id,
    required this.startSec,
    required this.endSec,
    required this.text,
    this.confidence = 1.0,
    this.isSummary,
  });

  /// SRT 파일에서 WhisperSegment 생성
  factory WhisperSegment.fromSrt(String srtContent, int id) {
    final lines = srtContent.trim().split('\n');
    
    if (lines.length < 3) {
      throw FormatException('SRT 형식이 올바르지 않습니다: $srtContent');
    }

    // 시간 정보 파싱 (00:00:00,000 --> 00:00:00,000)
    final timeLine = lines[1];
    final timeMatch = RegExp(r'(\d{2}):(\d{2}):(\d{2}),(\d{3}) --> (\d{2}):(\d{2}):(\d{2}),(\d{3})')
        .firstMatch(timeLine);
    
    if (timeMatch == null) {
      throw FormatException('시간 형식이 올바르지 않습니다: $timeLine');
    }

    final startSec = _parseTimeToSeconds(
      int.parse(timeMatch.group(1)!),
      int.parse(timeMatch.group(2)!),
      int.parse(timeMatch.group(3)!),
      int.parse(timeMatch.group(4)!),
    );
    
    final endSec = _parseTimeToSeconds(
      int.parse(timeMatch.group(5)!),
      int.parse(timeMatch.group(6)!),
      int.parse(timeMatch.group(7)!),
      int.parse(timeMatch.group(8)!),
    );

    // 텍스트 내용 (3번째 줄부터)
    final text = lines.skip(2).join(' ').trim();

    return WhisperSegment(
      id: id,
      startSec: startSec,
      endSec: endSec,
      text: text,
    );
  }

  /// 시간을 초 단위로 변환
  static double _parseTimeToSeconds(int hours, int minutes, int seconds, int milliseconds) {
    return hours * 3600 + minutes * 60 + seconds + milliseconds / 1000.0;
  }

  /// 세그먼트 지속 시간 반환
  double get duration => endSec - startSec;

  /// 시작 시간을 MM:SS 형식으로 반환
  String get startTimeFormatted => _formatTime(startSec);

  /// 종료 시간을 MM:SS 형식으로 반환
  String get endTimeFormatted => _formatTime(endSec);

  /// 지속 시간을 MM:SS 형식으로 반환
  String get durationFormatted => _formatTime(duration);

  /// 시간을 MM:SS 형식으로 포맷팅 (UI 표시용 - 정밀도 손실)
  String _formatTime(double seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = (seconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
  
  /// 정확한 타임코드를 HH:MM:SS.mmm 형식으로 반환 (XML 출력용)
  String get preciseStartTime => _formatPreciseTime(startSec);
  String get preciseEndTime => _formatPreciseTime(endSec);
  
  /// 정밀한 시간 포맷팅 (밀리초 단위까지)
  String _formatPreciseTime(double seconds) {
    final hours = (seconds / 3600).floor();
    final minutes = ((seconds % 3600) / 60).floor();
    final remainingSeconds = seconds % 60;
    final sec = remainingSeconds.floor();
    final ms = ((remainingSeconds - sec) * 1000).round();
    
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}.${ms.toString().padLeft(3, '0')}';
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startSec': startSec,
      'endSec': endSec,
      'text': text,
      'confidence': confidence,
      'isSummary': isSummary,
    };
  }

  /// JSON에서 생성
  factory WhisperSegment.fromJson(Map<String, dynamic> json) {
    return WhisperSegment(
      id: json['id'] as int,
      startSec: (json['startSec'] as num).toDouble(),
      endSec: (json['endSec'] as num).toDouble(),
      text: json['text'] as String,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      isSummary: json['isSummary'] as bool?,
    );
  }

  /// 새로운 값으로 복사본 생성
  WhisperSegment copyWith({
    int? id,
    double? startSec,
    double? endSec,
    String? text,
    double? confidence,
    bool? isSummary,
  }) {
    return WhisperSegment(
      id: id ?? this.id,
      startSec: startSec ?? this.startSec,
      endSec: endSec ?? this.endSec,
      text: text ?? this.text,
      confidence: confidence ?? this.confidence,
      isSummary: isSummary ?? this.isSummary,
    );
  }

  @override
  String toString() {
    return 'WhisperSegment(id: $id, start: ${startTimeFormatted}, end: ${endTimeFormatted}, text: "$text")';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WhisperSegment &&
        other.id == id &&
        other.startSec == startSec &&
        other.endSec == endSec &&
        other.text == text;
  }

  @override
  int get hashCode {
    return id.hashCode ^
        startSec.hashCode ^
        endSec.hashCode ^
        text.hashCode;
  }
} 