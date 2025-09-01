import 'whisper_segment.dart';
import 'theme_group.dart';

/// 프로젝트 데이터를 담는 모델
class ProjectData {
  final String videoPath;
  final List<WhisperSegment> segments;
  final List<WhisperSegment> summarySegments;
  final String appVersion;
  final String fullSummaryText;
  final List<ThemeGroup>? themeGroups;

  ProjectData({
    required this.videoPath,
    required this.segments,
    required this.summarySegments,
    required this.appVersion,
    required this.fullSummaryText,
    this.themeGroups,
  });

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'videoPath': videoPath,
      'segments': segments.map((s) => s.toJson()).toList(),
      'summarySegments': summarySegments.map((s) => s.toJson()).toList(),
      'appVersion': appVersion,
      'fullSummaryText': fullSummaryText,
      'themeGroups': themeGroups?.map((g) => g.toJson()).toList(),
    };
  }

  /// JSON에서 생성
  factory ProjectData.fromJson(Map<String, dynamic> json) {
    return ProjectData(
      videoPath: json['videoPath'] as String,
      segments: (json['segments'] as List)
          .map((s) => WhisperSegment.fromJson(s))
          .toList(),
      summarySegments: (json['summarySegments'] as List)
          .map((s) => WhisperSegment.fromJson(s))
          .toList(),
      appVersion: json['appVersion'] as String,
      fullSummaryText: json['fullSummaryText'] as String,
      themeGroups: json['themeGroups'] != null
          ? (json['themeGroups'] as List)
              .map((g) => ThemeGroup.fromJson(g))
              .toList()
          : null,
    );
  }

  /// 프로젝트 이름 반환 (비디오 파일명에서 확장자 제거)
  String get projectName {
    final fileName = videoPath.split('/').last;
    final lastDotIndex = fileName.lastIndexOf('.');
    if (lastDotIndex == -1) return fileName;
    return fileName.substring(0, lastDotIndex);
  }

  /// 총 세그먼트 수 반환
  int get totalSegments => segments.length;

  /// 요약 세그먼트 수 반환
  int get summarySegmentsCount => summarySegments.length;

  /// 총 지속 시간 반환 (초 단위)
  double get totalDuration {
    if (segments.isEmpty) return 0.0;
    return segments.last.endSec;
  }

  /// 요약 지속 시간 반환 (초 단위)
  double get summaryDuration {
    if (summarySegments.isEmpty) return 0.0;
    return summarySegments.fold(0.0, (total, segment) => total + segment.duration);
  }

  /// 압축률 반환 (요약 지속 시간 / 전체 지속 시간)
  double get compressionRatio {
    if (totalDuration == 0.0) return 0.0;
    return summaryDuration / totalDuration;
  }

  /// 압축률을 퍼센트로 반환
  String get compressionRatioPercent {
    return '${(compressionRatio * 100).toStringAsFixed(1)}%';
  }

  /// 프로젝트 정보 요약 반환
  String get projectSummary {
    return '''
프로젝트: $projectName
전체 세그먼트: $totalSegments개
요약 세그먼트: $summarySegmentsCount개
전체 지속 시간: ${_formatDuration(totalDuration)}
요약 지속 시간: ${_formatDuration(summaryDuration)}
압축률: $compressionRatioPercent
앱 버전: $appVersion
''';
  }

  /// 시간을 MM:SS 형식으로 포맷팅
  String _formatDuration(double seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = (seconds % 60).floor();
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return 'ProjectData(name: "$projectName", segments: $totalSegments, summary: $summarySegmentsCount, duration: ${_formatDuration(totalDuration)})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProjectData &&
        other.videoPath == videoPath &&
        other.segments == segments &&
        other.summarySegments == summarySegments &&
        other.appVersion == appVersion &&
        other.fullSummaryText == fullSummaryText &&
        other.themeGroups == themeGroups;
  }

  @override
  int get hashCode {
    return videoPath.hashCode ^
        segments.hashCode ^
        summarySegments.hashCode ^
        appVersion.hashCode ^
        fullSummaryText.hashCode ^
        themeGroups.hashCode;
  }
} 