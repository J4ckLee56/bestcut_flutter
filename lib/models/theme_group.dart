import 'whisper_segment.dart';

/// 주제별로 그룹화된 세그먼트들을 담는 모델
class ThemeGroup {
  final String theme;
  final List<WhisperSegment> segments;
  final String? summary;
  final List<String> keywords;

  ThemeGroup({
    required this.theme,
    required this.segments,
    this.summary,
    this.keywords = const [],
  });

  /// 세그먼트들의 총 지속 시간 반환
  double get totalDuration {
    return segments.fold(0.0, (total, segment) => total + segment.duration);
  }

  /// 시작 시간 반환 (가장 빠른 세그먼트 기준)
  double get startTime {
    if (segments.isEmpty) return 0.0;
    return segments.map((s) => s.startSec).reduce((a, b) => a < b ? a : b);
  }

  /// 종료 시간 반환 (가장 늦은 세그먼트 기준)
  double get endTime {
    if (segments.isEmpty) return 0.0;
    return segments.map((s) => s.endSec).reduce((a, b) => a > b ? a : b);
  }

  /// 세그먼트 수 반환
  int get segmentCount => segments.length;

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'theme': theme,
      'segments': segments.map((s) => s.toJson()).toList(),
      'summary': summary,
      'keywords': keywords,
    };
  }

  /// JSON에서 생성
  factory ThemeGroup.fromJson(Map<String, dynamic> json) {
    return ThemeGroup(
      theme: json['theme'] as String,
      segments: (json['segments'] as List)
          .map((s) => WhisperSegment.fromJson(s))
          .toList(),
      summary: json['summary'] as String?,
      keywords: (json['keywords'] as List?)?.cast<String>() ?? [],
    );
  }

  /// 주제와 세그먼트로 새로운 ThemeGroup 생성
  factory ThemeGroup.create(String theme, List<WhisperSegment> segments) {
    return ThemeGroup(
      theme: theme,
      segments: segments,
    );
  }

  /// 요약 정보 추가
  ThemeGroup withSummary(String summary) {
    return ThemeGroup(
      theme: theme,
      segments: segments,
      summary: summary,
      keywords: keywords,
    );
  }

  /// 키워드 추가
  ThemeGroup withKeywords(List<String> keywords) {
    return ThemeGroup(
      theme: theme,
      segments: segments,
      summary: summary,
      keywords: keywords,
    );
  }

  @override
  String toString() {
    return 'ThemeGroup(theme: "$theme", segments: $segmentCount, duration: ${totalDuration.toStringAsFixed(1)}s)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThemeGroup &&
        other.theme == theme &&
        other.segments == segments &&
        other.summary == summary &&
        other.keywords == keywords;
  }

  @override
  int get hashCode {
    return theme.hashCode ^
        segments.hashCode ^
        summary.hashCode ^
        keywords.hashCode;
  }
} 