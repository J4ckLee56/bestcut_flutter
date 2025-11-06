/// FFmpeg silencedetect로 감지된 무음 구간 모델
class SilenceSegment {
  final double startSec;
  final double endSec;
  final double duration;

  const SilenceSegment({
    required this.startSec,
    required this.endSec,
    required this.duration,
  });

  factory SilenceSegment.fromJson(Map<String, dynamic> json) {
    return SilenceSegment(
      startSec: (json['startSec'] as num).toDouble(),
      endSec: (json['endSec'] as num).toDouble(),
      duration: (json['duration'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'startSec': startSec,
      'endSec': endSec,
      'duration': duration,
    };
  }

  @override
  String toString() {
    return 'SilenceSegment(start: ${startSec.toStringAsFixed(2)}s, end: ${endSec.toStringAsFixed(2)}s, duration: ${duration.toStringAsFixed(2)}s)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SilenceSegment &&
        other.startSec == startSec &&
        other.endSec == endSec &&
        other.duration == duration;
  }

  @override
  int get hashCode => startSec.hashCode ^ endSec.hashCode ^ duration.hashCode;
}

/// FFmpeg astats로 분석된 오디오 에너지 프레임
class AudioEnergyFrame {
  final double timeSec;
  final double rmsLevel; // dB 단위

  const AudioEnergyFrame({
    required this.timeSec,
    required this.rmsLevel,
  });

  bool get isSilence => rmsLevel < -40.0; // -40dB 이하는 무음으로 판단
  bool get isVoice => rmsLevel >= -40.0;

  @override
  String toString() {
    return 'AudioEnergyFrame(time: ${timeSec.toStringAsFixed(2)}s, rms: ${rmsLevel.toStringAsFixed(1)}dB)';
  }
}

/// Whisper 음성인식 결과를 담는 단어 모델
/// 무음도 word=""인 WordSegment로 표현 (isSilence: true)
class WordSegment {
  final int index; // 세그먼트 내 단어 인덱스
  final String word; // 무음인 경우 빈 문자열 ""
  final double startSec;
  final double endSec;
  final double score;
  final bool isSilence; // 무음 여부 (word == "" 이면 true)

  const WordSegment({
    required this.index,
    required this.word,
    required this.startSec,
    required this.endSec,
    required this.score,
    this.isSilence = false, // 기본값: 일반 단어
  });

  /// 일반 단어인지 확인
  bool get isWord => !isSilence;
  
  /// 지속 시간
  double get duration => endSec - startSec;

  factory WordSegment.fromJson(Map<String, dynamic> json) {
    return WordSegment(
      index: json['index'] as int,
      word: json['word'] as String,
      startSec: (json['startSec'] as num).toDouble(),
      endSec: (json['endSec'] as num).toDouble(),
      score: (json['score'] as num).toDouble(),
      isSilence: json['isSilence'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'index': index,
      'word': word,
      'startSec': startSec,
      'endSec': endSec,
      'score': score,
      'isSilence': isSilence,
    };
  }
  
  /// 복사본 생성 (편집용)
  WordSegment copyWith({
    int? index,
    String? word,
    double? startSec,
    double? endSec,
    double? score,
    bool? isSilence,
  }) {
    return WordSegment(
      index: index ?? this.index,
      word: word ?? this.word,
      startSec: startSec ?? this.startSec,
      endSec: endSec ?? this.endSec,
      score: score ?? this.score,
      isSilence: isSilence ?? this.isSilence,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WordSegment &&
        other.index == index &&
        other.word == word &&
        other.startSec == startSec &&
        other.endSec == endSec &&
        other.score == score &&
        other.isSilence == isSilence;
  }

  @override
  int get hashCode =>
      index.hashCode ^ 
      word.hashCode ^ 
      startSec.hashCode ^ 
      endSec.hashCode ^ 
      score.hashCode ^
      isSilence.hashCode;
  
  @override
  String toString() {
    if (isSilence) {
      return 'WordSegment(SILENCE, ${startSec.toStringAsFixed(2)}s-${endSec.toStringAsFixed(2)}s, ${duration.toStringAsFixed(2)}s)';
    }
    return 'WordSegment("$word", ${startSec.toStringAsFixed(2)}s-${endSec.toStringAsFixed(2)}s)';
  }
}

/// Whisper 음성인식 결과를 담는 세그먼트 모델
class WhisperSegment {
  final int id;
  final double startSec;
  final double endSec;
  String text; // 편집 가능하도록 final 제거
  final double confidence;
  bool? isSummary; // 요약 세그먼트 여부
  final List<WordSegment> words; // 단어 + 무음 통합 (isSilence로 구분)

  WhisperSegment({
    required this.id,
    required this.startSec,
    required this.endSec,
    required this.text,
    this.confidence = 1.0,
    this.isSummary,
    this.words = const [],
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
      words: const [],
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
      'words': words.map((w) => w.toJson()).toList(),
    };
  }

  /// JSON에서 생성 (구 silences 형식 마이그레이션 지원)
  factory WhisperSegment.fromJson(Map<String, dynamic> json) {
    final wordsList = (json['words'] as List<dynamic>? ?? const [])
        .map((item) => WordSegment.fromJson(item as Map<String, dynamic>))
        .toList();
    
    // 구 버전 호환성: silences가 있으면 words로 통합
    if (json.containsKey('silences') && json['silences'] != null) {
      final silencesList = (json['silences'] as List<dynamic>)
          .map((item) => SilenceSegment.fromJson(item as Map<String, dynamic>))
          .toList();
      
      // silences를 WordSegment로 변환하여 추가
      for (final silence in silencesList) {
        wordsList.add(WordSegment(
          index: wordsList.length,
          word: '',
          startSec: silence.startSec,
          endSec: silence.endSec,
          score: 1.0,
          isSilence: true,
        ));
      }
      
      // 시간순 정렬
      wordsList.sort((a, b) => a.startSec.compareTo(b.startSec));
      
      // 인덱스 재조정
      for (int i = 0; i < wordsList.length; i++) {
        wordsList[i] = wordsList[i].copyWith(index: i);
      }
    }
    
    return WhisperSegment(
      id: json['id'] as int,
      startSec: (json['startSec'] as num).toDouble(),
      endSec: (json['endSec'] as num).toDouble(),
      text: json['text'] as String,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
      isSummary: json['isSummary'] as bool?,
      words: wordsList,
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
    List<WordSegment>? words,
  }) {
    return WhisperSegment(
      id: id ?? this.id,
      startSec: startSec ?? this.startSec,
      endSec: endSec ?? this.endSec,
      text: text ?? this.text,
      confidence: confidence ?? this.confidence,
      isSummary: isSummary ?? this.isSummary,
      words: words ?? this.words,
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
        other.text == text &&
        _listEquals(other.words, words);
  }

  @override
  int get hashCode {
    return id.hashCode ^
        startSec.hashCode ^
        endSec.hashCode ^
        text.hashCode ^
        words.fold(0, (prev, w) => prev ^ w.hashCode);
  }

  bool _listEquals(List<WordSegment> a, List<WordSegment> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final aw = a[i];
      final bw = b[i];
      if (aw != bw) return false;
    }
    return true;
  }
} 