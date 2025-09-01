import 'package:flutter/foundation.dart';
import '../models/app_state.dart';
import '../models/whisper_segment.dart';

/// XML 서비스 클래스
/// 프리미어 프로, 파이널컷 프로, 다빈치 리졸브용 XML 파일을 생성합니다.
class XMLService {
  final AppState _appState;

  XMLService(this._appState);

  /// 프리미어 프로 XML 생성
  Future<String> generatePremiereXML({
    required bool isSummary,
    required List<int> selectedSegmentIds,
  }) async {
    try {
      if (kDebugMode) print('🎬 XMLService: 프리미어 프로 XML 생성 시작');
      
      final segments = isSummary 
          ? _appState.segments.where((s) => selectedSegmentIds.contains(s.id)).toList()
          : _appState.segments;
      
      final xml = _buildPremiereXML(segments, isSummary);
      
      if (kDebugMode) print('✅ XMLService: 프리미어 프로 XML 생성 완료');
      return xml;
    } catch (e) {
      if (kDebugMode) print('❌ XMLService: 프리미어 프로 XML 생성 실패: $e');
      rethrow;
    }
  }

  /// Final Cut Pro XML 생성
  Future<String> generateFCPXML({
    required bool isSummary,
    required List<int> selectedSegmentIds,
  }) async {
    try {
      if (kDebugMode) print('🎬 XMLService: Final Cut Pro XML 생성 시작');
      
      final segments = isSummary 
          ? _appState.segments.where((s) => selectedSegmentIds.contains(s.id)).toList()
          : _appState.segments;
      
      final xml = _buildFCPXML(segments, isSummary);
      
      if (kDebugMode) print('✅ XMLService: Final Cut Pro XML 생성 완료');
      return xml;
    } catch (e) {
      if (kDebugMode) print('❌ XMLService: Final Cut Pro XML 생성 실패: $e');
      rethrow;
    }
  }

  /// DaVinci Resolve XML 생성
  Future<String> generateDaVinciXML({
    required bool isSummary,
    required List<int> selectedSegmentIds,
  }) async {
    try {
      if (kDebugMode) print('🎬 XMLService: DaVinci Resolve XML 생성 시작');
      
      final segments = isSummary 
          ? _appState.segments.where((s) => selectedSegmentIds.contains(s.id)).toList()
          : _appState.segments;
      
      if (kDebugMode) print('🔍 DaVinci XML: isSummary=$isSummary, selectedSegmentIds=$selectedSegmentIds, filteredSegments=${segments.length}');
      
      final xml = _buildDaVinciXML(segments, isSummary);
      
      if (kDebugMode) print('✅ XMLService: DaVinci Resolve XML 생성 완료');
      return xml;
    } catch (e) {
      if (kDebugMode) print('❌ XMLService: DaVinci Resolve XML 생성 실패: $e');
      rethrow;
    }
  }

  /// 비디오 파일명 추출
  String getVideoFileName() {
    final videoPath = _appState.videoPath;
    if (videoPath == null) return 'video.mp4';
    return videoPath.split('/').last;
  }

  /// 비디오 메타데이터 추출
  Map<String, dynamic> _getVideoMetadata() {
    final controller = _appState.videoController;
    if (controller?.value.isInitialized == true) {
      final size = controller!.value.size;
      return {
        'width': size.width.toInt(),
        'height': size.height.toInt(),
        'frameRate': 30.0, // 기본값, 정확한 frame rate를 얻기 어려운 경우
      };
    }
    return {
      'width': 1920,
      'height': 1080,
      'frameRate': 30.0,
    };
  }

  /// 프리미어 프로 XML 구조 생성
  String _buildPremiereXML(List<WhisperSegment> segments, bool isSummary) {
    final buffer = StringBuffer();
    final videoFileName = getVideoFileName();
    final videoName = videoFileName.replaceAll('.mp4', '');
    final metadata = _getVideoMetadata();
    final frameRate = metadata['frameRate'] as double;
    final width = metadata['width'] as int;
    final height = metadata['height'] as int;
    
    // 전체 시간 계산
    double totalDuration = 0.0;
    if (isSummary) {
      for (final segment in segments) {
        totalDuration += (segment.endSec - segment.startSec);
      }
    } else {
      totalDuration = segments.isNotEmpty ? segments.last.endSec : 0.0;
    }
    
    // XMEML 헤더
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln('<xmeml version="5">');
    buffer.writeln('  <sequence id="video">');
    buffer.writeln('    <name>${isSummary ? "${videoName}_Summary" : videoName}</name>');
    buffer.writeln('    <duration>$totalDuration</duration>');
    buffer.writeln('    <rate>');
    buffer.writeln('      <timebase>${frameRate.round()}</timebase>');
    buffer.writeln('      <ntsc>false</ntsc>');
    buffer.writeln('    </rate>');
    buffer.writeln('    <media>');
    
    // 비디오 트랙
    buffer.writeln('      <video>');
    buffer.writeln('        <format>');
    buffer.writeln('          <samplecharacteristics>');
    buffer.writeln('            <width>$width</width>');
    buffer.writeln('            <height>$height</height>');
    buffer.writeln('            <anamorphic>false</anamorphic>');
    buffer.writeln('            <pixelaspectratio>square</pixelaspectratio>');
    buffer.writeln('            <fielddominance>none</fielddominance>');
    buffer.writeln('          </samplecharacteristics>');
    buffer.writeln('        </format>');
    buffer.writeln('        <track>');
    
    // 비디오 클립들 생성 - 세그먼트별로 개별 클립
    if (isSummary) {
      // 요약 모드: 요약 세그먼트만 연속으로 배치
      double timelinePosition = 0.0;
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final inFrames = (segment.startSec * frameRate).round();
        final outFrames = (segment.endSec * frameRate).round();
        final startFrames = (timelinePosition * frameRate).round();
        final endFrames = startFrames + (outFrames - inFrames);
        
        buffer.writeln('          <clipitem>');
        buffer.writeln('            <name>$videoFileName</name>');
        buffer.writeln('            <enabled>true</enabled>');
        buffer.writeln('            <rate>');
        buffer.writeln('              <timebase>${frameRate.round()}</timebase>');
        buffer.writeln('              <ntsc>false</ntsc>');
        buffer.writeln('            </rate>');
        buffer.writeln('            <in>$inFrames</in>');
        buffer.writeln('            <out>$outFrames</out>');
        buffer.writeln('            <start>$startFrames</start>');
        buffer.writeln('            <end>$endFrames</end>');
        buffer.writeln('            <file id="$videoFileName">');
        buffer.writeln('              <name>$videoFileName</name>');
        buffer.writeln('              <pathurl>$videoFileName</pathurl>');
        buffer.writeln('              <media>');
        buffer.writeln('                <video>');
        buffer.writeln('                  <samplecharacteristics>');
        buffer.writeln('                    <width>$width</width>');
        buffer.writeln('                    <height>$height</height>');
        buffer.writeln('                    <anamorphic>true</anamorphic>');
        buffer.writeln('                    <pixelaspectratio>square</pixelaspectratio>');
        buffer.writeln('                    <fielddominance>none</fielddominance>');
        buffer.writeln('                  </samplecharacteristics>');
        buffer.writeln('                </video>');
        buffer.writeln('                <audio>');
        buffer.writeln('                  <in>0</in>');
        buffer.writeln('                  <out>$totalDuration</out>');
        buffer.writeln('                  <channelcount>2</channelcount>');
        buffer.writeln('                  <duration>$totalDuration</duration>');
        buffer.writeln('                </audio>');
        buffer.writeln('              </media>');
        buffer.writeln('            </file>');
        buffer.writeln('            <link>');
        buffer.writeln('              <mediatype>video</mediatype>');
        buffer.writeln('              <trackindex>1</trackindex>');
        buffer.writeln('              <clipindex>${i + 1}</clipindex>');
        buffer.writeln('            </link>');
        buffer.writeln('            <link>');
        buffer.writeln('              <mediatype>audio</mediatype>');
        buffer.writeln('              <trackindex>1</trackindex>');
        buffer.writeln('              <clipindex>${i + 1}</clipindex>');
        buffer.writeln('              <groupindex>${i + 1}</groupindex>');
        buffer.writeln('            </link>');
        buffer.writeln('            <link>');
        buffer.writeln('              <mediatype>audio</mediatype>');
        buffer.writeln('              <trackindex>2</trackindex>');
        buffer.writeln('              <clipindex>${i + 1}</clipindex>');
        buffer.writeln('              <groupindex>${i + 1}</groupindex>');
        buffer.writeln('            </link>');
        buffer.writeln('          </clipitem>');
        
        timelinePosition += (segment.endSec - segment.startSec);
      }
    } else {
      // 전체 모드: 각 세그먼트를 원래 타이밍으로 개별 클립 생성
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final inFrames = (segment.startSec * frameRate).round();
        final outFrames = (segment.endSec * frameRate).round();
        final startFrames = inFrames; // 원래 타이밍 유지
        final endFrames = outFrames;
        
        buffer.writeln('          <clipitem>');
        buffer.writeln('            <name>$videoFileName</name>');
        buffer.writeln('            <enabled>true</enabled>');
        buffer.writeln('            <rate>');
        buffer.writeln('              <timebase>${frameRate.round()}</timebase>');
        buffer.writeln('              <ntsc>false</ntsc>');
        buffer.writeln('            </rate>');
        buffer.writeln('            <in>$inFrames</in>');
        buffer.writeln('            <out>$outFrames</out>');
        buffer.writeln('            <start>$startFrames</start>');
        buffer.writeln('            <end>$endFrames</end>');
        buffer.writeln('            <file id="$videoFileName">');
        buffer.writeln('              <name>$videoFileName</name>');
        buffer.writeln('              <pathurl>$videoFileName</pathurl>');
        buffer.writeln('              <media>');
        buffer.writeln('                <video>');
        buffer.writeln('                  <samplecharacteristics>');
        buffer.writeln('                    <width>$width</width>');
        buffer.writeln('                    <height>$height</height>');
        buffer.writeln('                    <anamorphic>true</anamorphic>');
        buffer.writeln('                    <pixelaspectratio>square</pixelaspectratio>');
        buffer.writeln('                    <fielddominance>none</fielddominance>');
        buffer.writeln('                  </samplecharacteristics>');
        buffer.writeln('                </video>');
        buffer.writeln('                <audio>');
        buffer.writeln('                  <in>0</in>');
        buffer.writeln('                  <out>$totalDuration</out>');
        buffer.writeln('                  <channelcount>2</channelcount>');
        buffer.writeln('                  <duration>$totalDuration</duration>');
        buffer.writeln('                </audio>');
        buffer.writeln('              </media>');
        buffer.writeln('            </file>');
        buffer.writeln('            <link>');
        buffer.writeln('              <mediatype>video</mediatype>');
        buffer.writeln('              <trackindex>1</trackindex>');
        buffer.writeln('              <clipindex>${i + 1}</clipindex>');
        buffer.writeln('            </link>');
        buffer.writeln('            <link>');
        buffer.writeln('              <mediatype>audio</mediatype>');
        buffer.writeln('              <trackindex>1</trackindex>');
        buffer.writeln('              <clipindex>${i + 1}</clipindex>');
        buffer.writeln('              <groupindex>${i + 1}</groupindex>');
        buffer.writeln('            </link>');
        buffer.writeln('            <link>');
        buffer.writeln('              <mediatype>audio</mediatype>');
        buffer.writeln('              <trackindex>2</trackindex>');
        buffer.writeln('              <clipindex>${i + 1}</clipindex>');
        buffer.writeln('              <groupindex>${i + 1}</groupindex>');
        buffer.writeln('            </link>');
        buffer.writeln('          </clipitem>');
      }
    }
    
    buffer.writeln('        </track>');
    
    // 자막 트랙을 비디오 섹션 내 두 번째 트랙으로 추가 (브루 XML과 동일)
    buffer.writeln('        <track>');
    
    // 자막 클립들 생성 - generatoritem으로 자막 효과 생성
    if (isSummary) {
      // 요약 모드: 요약 세그먼트만 연속으로 배치
      double timelinePosition = 0.0;
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final startFrames = (timelinePosition * frameRate).round();
        final durationFrames = ((segment.endSec - segment.startSec) * frameRate).round();
        final endFrames = startFrames + durationFrames;
        
        buffer.writeln('          <generatoritem id="자막${i + 1}">');
        buffer.writeln('            <name>${segment.text}</name>');
        buffer.writeln('            <duration>${segment.endSec - segment.startSec}</duration>');
        buffer.writeln('            <rate>');
        buffer.writeln('              <timebase>${frameRate.round()}</timebase>');
        buffer.writeln('              <ntsc>false</ntsc>');
        buffer.writeln('            </rate>');
        buffer.writeln('            <start>$startFrames</start>');
        buffer.writeln('            <end>$endFrames</end>');
        buffer.writeln('            <in>$startFrames</in>');
        buffer.writeln('            <out>$endFrames</out>');
        buffer.writeln('            <enabled>true</enabled>');
        buffer.writeln('            <anamorphic>false</anamorphic>');
        buffer.writeln('            <alphatype>black</alphatype>');
        buffer.writeln('            <masterclipid>자막${i + 1}</masterclipid>');
        buffer.writeln('            <effect>');
        buffer.writeln('              <name>Outline Text</name>');
        buffer.writeln('              <effectid>Outline Text</effectid>');
        buffer.writeln('              <effectcategory>Text</effectcategory>');
        buffer.writeln('              <effecttype>generator</effecttype>');
        buffer.writeln('              <mediatype>video</mediatype>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>part1</parameterid>');
        buffer.writeln('                <name>Text Settings</name>');
        buffer.writeln('                <value/>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>str</parameterid>');
        buffer.writeln('                <name>Text</name>');
        buffer.writeln('                <value>${segment.text}</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>font</parameterid>');
        buffer.writeln('                <name>Font</name>');
        buffer.writeln('                <value>AppleSDGothicNeo-Regular</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>style</parameterid>');
        buffer.writeln('                <name>Style</name>');
        buffer.writeln('                <valuemin>1</valuemin>');
        buffer.writeln('                <valuemax>1</valuemax>');
        buffer.writeln('                <valuelist>');
        buffer.writeln('                  <valueentry>');
        buffer.writeln('                    <name>Regular</name>');
        buffer.writeln('                    <value>1</value>');
        buffer.writeln('                  </valueentry>');
        buffer.writeln('                </valuelist>');
        buffer.writeln('                <value>1</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>align</parameterid>');
        buffer.writeln('                <name>Alignment</name>');
        buffer.writeln('                <valuemin>1</valuemin>');
        buffer.writeln('                <valuemax>3</valuemax>');
        buffer.writeln('                <valuelist>');
        buffer.writeln('                  <valueentry>');
        buffer.writeln('                    <name>Left</name>');
        buffer.writeln('                    <value>1</value>');
        buffer.writeln('                  </valueentry>');
        buffer.writeln('                  <valueentry>');
        buffer.writeln('                    <name>Center</name>');
        buffer.writeln('                    <value>2</value>');
        buffer.writeln('                  </valueentry>');
        buffer.writeln('                  <valueentry>');
        buffer.writeln('                    <name>Right</name>');
        buffer.writeln('                    <value>3</value>');
        buffer.writeln('                  </valueentry>');
        buffer.writeln('                </valuelist>');
        buffer.writeln('                <value>2</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>size</parameterid>');
        buffer.writeln('                <name>Size</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>200</valuemax>');
        buffer.writeln('                <value>24</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>track</parameterid>');
        buffer.writeln('                <name>Tracking</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>1</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>lead</parameterid>');
        buffer.writeln('                <name>Leading</name>');
        buffer.writeln('                <valuemin>-100</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>0</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>aspect</parameterid>');
        buffer.writeln('                <name>Aspect</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>4</valuemax>');
        buffer.writeln('                <value>1</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>linewidth</parameterid>');
        buffer.writeln('                <name>Line Width</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>200</valuemax>');
        buffer.writeln('                <value>2</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>linesoft</parameterid>');
        buffer.writeln('                <name>Line Softness</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>5</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>textopacity</parameterid>');
        buffer.writeln('                <name>Text Opacity</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>100</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>center</parameterid>');
        buffer.writeln('                <name>Center</name>');
        buffer.writeln('                <value>');
        buffer.writeln('                  <horiz>0</horiz>');
        buffer.writeln('                  <vert>0.4703703703703703</vert>');
        buffer.writeln('                </value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>textcolor</parameterid>');
        buffer.writeln('                <name>Text Color</name>');
        buffer.writeln('                <value>');
        buffer.writeln('                  <alpha>255</alpha>');
        buffer.writeln('                  <red>255</red>');
        buffer.writeln('                  <green>255</green>');
        buffer.writeln('                  <blue>255</blue>');
        buffer.writeln('                </value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>supertext</parameterid>');
        buffer.writeln('                <name>Text Graphic</name>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>linecolor</parameterid>');
        buffer.writeln('                <name>Line Color</name>');
        buffer.writeln('                <value>');
        buffer.writeln('                  <alpha>255</alpha>');
        buffer.writeln('                  <red>0</red>');
        buffer.writeln('                  <green>0</green>');
        buffer.writeln('                  <blue>0</blue>');
        buffer.writeln('                </value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>superline</parameterid>');
        buffer.writeln('                <name>Line Graphic</name>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>part2</parameterid>');
        buffer.writeln('                <name>Background Settings</name>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>xscale</parameterid>');
        buffer.writeln('                <name>Horizontal Size</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>200</valuemax>');
        buffer.writeln('                <value>0</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>yscale</parameterid>');
        buffer.writeln('                <name>Vertical Size</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>200</valuemax>');
        buffer.writeln('                <value>0</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>xoffset</parameterid>');
        buffer.writeln('                <name>Horizontal Offset</name>');
        buffer.writeln('                <valuemin>-100</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>0</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>yoffset</parameterid>');
        buffer.writeln('                <name>Vertical Offset</name>');
        buffer.writeln('                <valuemin>-100</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>0</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>backsoft</parameterid>');
        buffer.writeln('                <name>Back Soft</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>0</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>backopacity</parameterid>');
        buffer.writeln('                <name>Back Opacity</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>50</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>backcolor</parameterid>');
        buffer.writeln('                <name>Back Color</name>');
        buffer.writeln('                <value>');
        buffer.writeln('                  <alpha>255</alpha>');
        buffer.writeln('                  <red>255</red>');
        buffer.writeln('                  <green>255</green>');
        buffer.writeln('                  <blue>255</blue>');
        buffer.writeln('                </value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>superback</parameterid>');
        buffer.writeln('                <name>Back Graphic</name>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>crop</parameterid>');
        buffer.writeln('                <name>Crop</name>');
        buffer.writeln('                <value>false</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>autokern</parameterid>');
        buffer.writeln('                <name>Auto Kerning</name>');
        buffer.writeln('                <value>true</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('            </effect>');
        buffer.writeln('            <sourcetrack>');
        buffer.writeln('              <mediatype>video</mediatype>');
        buffer.writeln('            </sourcetrack>');
        buffer.writeln('          </generatoritem>');
        
        timelinePosition += (segment.endSec - segment.startSec);
      }
    } else {
      // 전체 모드: 각 세그먼트를 원래 타이밍으로 배치
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final startFrames = (segment.startSec * frameRate).round();
        final endFrames = (segment.endSec * frameRate).round();
        
        buffer.writeln('          <generatoritem id="자막${i + 1}">');
        buffer.writeln('            <name>${segment.text}</name>');
        buffer.writeln('            <duration>${segment.endSec - segment.startSec}</duration>');
        buffer.writeln('            <rate>');
        buffer.writeln('              <timebase>${frameRate.round()}</timebase>');
        buffer.writeln('              <ntsc>false</ntsc>');
        buffer.writeln('            </rate>');
        buffer.writeln('            <start>$startFrames</start>');
        buffer.writeln('            <end>$endFrames</end>');
        buffer.writeln('            <in>$startFrames</in>');
        buffer.writeln('            <out>$endFrames</out>');
        buffer.writeln('            <enabled>true</enabled>');
        buffer.writeln('            <anamorphic>false</anamorphic>');
        buffer.writeln('            <alphatype>black</alphatype>');
        buffer.writeln('            <masterclipid>자막${i + 1}</masterclipid>');
        buffer.writeln('            <effect>');
        buffer.writeln('              <name>Outline Text</name>');
        buffer.writeln('              <effectid>Outline Text</effectid>');
        buffer.writeln('              <effectcategory>Text</effectcategory>');
        buffer.writeln('              <effecttype>generator</effecttype>');
        buffer.writeln('              <mediatype>video</mediatype>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>part1</parameterid>');
        buffer.writeln('                <name>Text Settings</name>');
        buffer.writeln('                <value/>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>str</parameterid>');
        buffer.writeln('                <name>Text</name>');
        buffer.writeln('                <value>${segment.text}</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>font</parameterid>');
        buffer.writeln('                <name>Font</name>');
        buffer.writeln('                <value>AppleSDGothicNeo-Regular</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>style</parameterid>');
        buffer.writeln('                <name>Style</name>');
        buffer.writeln('                <valuemin>1</valuemin>');
        buffer.writeln('                <valuemax>1</valuemax>');
        buffer.writeln('                <valuelist>');
        buffer.writeln('                  <valueentry>');
        buffer.writeln('                    <name>Regular</name>');
        buffer.writeln('                    <value>1</value>');
        buffer.writeln('                  </valueentry>');
        buffer.writeln('                </valuelist>');
        buffer.writeln('                <value>1</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>align</parameterid>');
        buffer.writeln('                <name>Alignment</name>');
        buffer.writeln('                <valuemin>1</valuemin>');
        buffer.writeln('                <valuemax>3</valuemax>');
        buffer.writeln('                <valuelist>');
        buffer.writeln('                  <valueentry>');
        buffer.writeln('                    <name>Left</name>');
        buffer.writeln('                    <value>1</value>');
        buffer.writeln('                  </valueentry>');
        buffer.writeln('                  <valueentry>');
        buffer.writeln('                    <name>Center</name>');
        buffer.writeln('                    <value>2</value>');
        buffer.writeln('                  </valueentry>');
        buffer.writeln('                  <valueentry>');
        buffer.writeln('                    <name>Right</name>');
        buffer.writeln('                    <value>3</value>');
        buffer.writeln('                  </valueentry>');
        buffer.writeln('                </valuelist>');
        buffer.writeln('                <value>2</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>size</parameterid>');
        buffer.writeln('                <name>Size</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>200</valuemax>');
        buffer.writeln('                <value>24</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>track</parameterid>');
        buffer.writeln('                <name>Tracking</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>1</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>lead</parameterid>');
        buffer.writeln('                <name>Leading</name>');
        buffer.writeln('                <valuemin>-100</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>0</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>aspect</parameterid>');
        buffer.writeln('                <name>Aspect</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>4</valuemax>');
        buffer.writeln('                <value>1</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>linewidth</parameterid>');
        buffer.writeln('                <name>Line Width</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>200</valuemax>');
        buffer.writeln('                <value>2</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>linesoft</parameterid>');
        buffer.writeln('                <name>Line Softness</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>5</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>textopacity</parameterid>');
        buffer.writeln('                <name>Text Opacity</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>100</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>center</parameterid>');
        buffer.writeln('                <name>Center</name>');
        buffer.writeln('                <value>');
        buffer.writeln('                  <horiz>0</horiz>');
        buffer.writeln('                  <vert>0.4703703703703703</vert>');
        buffer.writeln('                </value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>textcolor</parameterid>');
        buffer.writeln('                <name>Text Color</name>');
        buffer.writeln('                <value>');
        buffer.writeln('                  <alpha>255</alpha>');
        buffer.writeln('                  <red>255</red>');
        buffer.writeln('                  <green>255</green>');
        buffer.writeln('                  <blue>255</blue>');
        buffer.writeln('                </value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>supertext</parameterid>');
        buffer.writeln('                <name>Text Graphic</name>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>linecolor</parameterid>');
        buffer.writeln('                <name>Line Color</name>');
        buffer.writeln('                <value>');
        buffer.writeln('                  <alpha>255</alpha>');
        buffer.writeln('                  <red>0</red>');
        buffer.writeln('                  <green>0</green>');
        buffer.writeln('                  <blue>0</blue>');
        buffer.writeln('                </value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>superline</parameterid>');
        buffer.writeln('                <name>Line Graphic</name>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>part2</parameterid>');
        buffer.writeln('                <name>Background Settings</name>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>xscale</parameterid>');
        buffer.writeln('                <name>Horizontal Size</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>200</valuemax>');
        buffer.writeln('                <value>0</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>yscale</parameterid>');
        buffer.writeln('                <name>Vertical Size</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>200</valuemax>');
        buffer.writeln('                <value>0</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>xoffset</parameterid>');
        buffer.writeln('                <name>Horizontal Offset</name>');
        buffer.writeln('                <valuemin>-100</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>0</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>yoffset</parameterid>');
        buffer.writeln('                <name>Vertical Offset</name>');
        buffer.writeln('                <valuemin>-100</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>0</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>backsoft</parameterid>');
        buffer.writeln('                <name>Back Soft</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>0</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>backopacity</parameterid>');
        buffer.writeln('                <name>Back Opacity</name>');
        buffer.writeln('                <valuemin>0</valuemin>');
        buffer.writeln('                <valuemax>100</valuemax>');
        buffer.writeln('                <value>50</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>backcolor</parameterid>');
        buffer.writeln('                <name>Back Color</name>');
        buffer.writeln('                <value>');
        buffer.writeln('                  <alpha>255</alpha>');
        buffer.writeln('                  <red>255</red>');
        buffer.writeln('                  <green>255</green>');
        buffer.writeln('                  <blue>255</blue>');
        buffer.writeln('                </value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>superback</parameterid>');
        buffer.writeln('                <name>Back Graphic</name>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>crop</parameterid>');
        buffer.writeln('                <name>Crop</name>');
        buffer.writeln('                <value>false</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('              <parameter>');
        buffer.writeln('                <parameterid>autokern</parameterid>');
        buffer.writeln('                <name>Auto Kerning</name>');
        buffer.writeln('                <value>true</value>');
        buffer.writeln('              </parameter>');
        buffer.writeln('            </effect>');
        buffer.writeln('            <sourcetrack>');
        buffer.writeln('              <mediatype>video</mediatype>');
        buffer.writeln('            </sourcetrack>');
        buffer.writeln('          </generatoritem>');
      }
    }
    
    buffer.writeln('        </track>');
    buffer.writeln('      </video>');
    
    // 오디오 트랙 - 정상 파일과 동일한 구조
    buffer.writeln('      <audio>');
    buffer.writeln('        <numOutputChannels>2</numOutputChannels>');
    buffer.writeln('        <format>');
    buffer.writeln('          <samplecharacteristics>');
    buffer.writeln('            <samplerate>48000</samplerate>');
    buffer.writeln('            <depth>16</depth>');
    buffer.writeln('          </samplecharacteristics>');
    buffer.writeln('        </format>');
    buffer.writeln('        <outputs>');
    buffer.writeln('          <group>');
    buffer.writeln('            <index>1</index>');
    buffer.writeln('            <numchannels>2</numchannels>');
    buffer.writeln('            <downmix>0</downmix>');
    buffer.writeln('            <channel>');
    buffer.writeln('              <index>1</index>');
    buffer.writeln('            </channel>');
    buffer.writeln('            <channel>');
    buffer.writeln('              <index>2</index>');
    buffer.writeln('            </channel>');
    buffer.writeln('          </group>');
    buffer.writeln('        </outputs>');
    buffer.writeln('        <track>');
    
    // 첫 번째 오디오 트랙 - 비디오와 동일한 세그먼트별 클립 생성
    if (isSummary) {
      // 요약 모드: 요약 세그먼트만 연속으로 배치
      double timelinePosition = 0.0;
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final inFrames = (segment.startSec * frameRate).round();
        final outFrames = (segment.endSec * frameRate).round();
        final startFrames = (timelinePosition * frameRate).round();
        final endFrames = startFrames + (outFrames - inFrames);
        
        buffer.writeln('          <clipitem>');
        buffer.writeln('            <name>$videoFileName</name>');
        buffer.writeln('            <enabled>true</enabled>');
        buffer.writeln('            <in>$inFrames</in>');
        buffer.writeln('            <out>$outFrames</out>');
        buffer.writeln('            <start>$startFrames</start>');
        buffer.writeln('            <end>$endFrames</end>');
        buffer.writeln('            <file id="$videoFileName"/>');
        buffer.writeln('            <sourcetrack>');
        buffer.writeln('              <mediatype>audio</mediatype>');
        buffer.writeln('              <trackindex>1</trackindex>');
        buffer.writeln('            </sourcetrack>');
        buffer.writeln('          </clipitem>');
        
        timelinePosition += (segment.endSec - segment.startSec);
      }
    } else {
      // 전체 모드: 각 세그먼트를 원래 타이밍으로 개별 클립 생성
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final inFrames = (segment.startSec * frameRate).round();
        final outFrames = (segment.endSec * frameRate).round();
        final startFrames = inFrames; // 원래 타이밍 유지
        final endFrames = outFrames;
        
        buffer.writeln('          <clipitem>');
        buffer.writeln('            <name>$videoFileName</name>');
        buffer.writeln('            <enabled>true</enabled>');
        buffer.writeln('            <in>$inFrames</in>');
        buffer.writeln('            <out>$outFrames</out>');
        buffer.writeln('            <start>$startFrames</start>');
        buffer.writeln('            <end>$endFrames</end>');
        buffer.writeln('            <file id="$videoFileName"/>');
        buffer.writeln('            <sourcetrack>');
        buffer.writeln('              <mediatype>audio</mediatype>');
        buffer.writeln('              <trackindex>1</trackindex>');
        buffer.writeln('            </sourcetrack>');
        buffer.writeln('          </clipitem>');
      }
    }
    
    buffer.writeln('        </track>');
    buffer.writeln('        <track>');
    
    // 두 번째 오디오 트랙 - 첫 번째와 동일하지만 trackindex가 2
    if (isSummary) {
      // 요약 모드: 요약 세그먼트만 연속으로 배치
      double timelinePosition = 0.0;
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final inFrames = (segment.startSec * frameRate).round();
        final outFrames = (segment.endSec * frameRate).round();
        final startFrames = (timelinePosition * frameRate).round();
        final endFrames = startFrames + (outFrames - inFrames);
        
        buffer.writeln('          <clipitem>');
        buffer.writeln('            <name>$videoFileName</name>');
        buffer.writeln('            <enabled>true</enabled>');
        buffer.writeln('            <in>$inFrames</in>');
        buffer.writeln('            <out>$outFrames</out>');
        buffer.writeln('            <start>$startFrames</start>');
        buffer.writeln('            <end>$endFrames</end>');
        buffer.writeln('            <file id="$videoFileName"/>');
        buffer.writeln('            <sourcetrack>');
        buffer.writeln('              <mediatype>audio</mediatype>');
        buffer.writeln('              <trackindex>2</trackindex>');
        buffer.writeln('            </sourcetrack>');
        buffer.writeln('          </clipitem>');
        
        timelinePosition += (segment.endSec - segment.startSec);
      }
    } else {
      // 전체 모드: 각 세그먼트를 원래 타이밍으로 개별 클립 생성
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final inFrames = (segment.startSec * frameRate).round();
        final outFrames = (segment.endSec * frameRate).round();
        final startFrames = inFrames; // 원래 타이밍 유지
        final endFrames = outFrames;
        
        buffer.writeln('          <clipitem>');
        buffer.writeln('            <name>$videoFileName</name>');
        buffer.writeln('            <enabled>true</enabled>');
        buffer.writeln('            <in>$inFrames</in>');
        buffer.writeln('            <out>$outFrames</out>');
        buffer.writeln('            <start>$startFrames</start>');
        buffer.writeln('            <end>$endFrames</end>');
        buffer.writeln('            <file id="$videoFileName"/>');
        buffer.writeln('            <sourcetrack>');
        buffer.writeln('              <mediatype>audio</mediatype>');
        buffer.writeln('              <trackindex>2</trackindex>');
        buffer.writeln('            </sourcetrack>');
        buffer.writeln('          </clipitem>');
      }
    }
    
    buffer.writeln('        </track>');
    buffer.writeln('      </audio>');
    buffer.writeln('    </media>');
    buffer.writeln('  </sequence>');
    buffer.writeln('</xmeml>');
    
    return buffer.toString();
  }

  /// Final Cut Pro XML 구조 생성
  String _buildFCPXML(List<WhisperSegment> segments, bool isSummary) {
    final buffer = StringBuffer();
    final videoFileName = getVideoFileName();
    final videoName = videoFileName.replaceAll('.mp4', '');
    final metadata = _getVideoMetadata();
    final frameRate = metadata['frameRate'] as double;
    final width = metadata['width'] as int;
    final height = metadata['height'] as int;
    
    // FCP XML header (vrew 참조 구조와 동일)
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln('<fcpxml version="1.6">');
    buffer.writeln('  <import-options>');
    buffer.writeln('    <option value="1" key="suppress warnings"/>');
    buffer.writeln('  </import-options>');
    buffer.writeln('  <resources>');
    buffer.writeln('    <format id="f1" frameDuration="1/${frameRate.round()}s" width="$width" height="$height"/>');
    buffer.writeln('    <asset id="a1" src="${Uri.encodeComponent(videoFileName)}" format="f1" duration="${segments.isNotEmpty ? segments.last.endSec : 0}/${frameRate.round()}s" name="$videoFileName" hasAudio="1" hasVideo="1" start="0/${frameRate.round()}s"/>');
    buffer.writeln('    <effect id="e1" name="Custom" uid=".../Titles.localized/Build In:Out.localized/Custom.localized/Custom.moti"/>');
    buffer.writeln('  </resources>');
    
    // FCP 시퀀스 지속시간 계산 (백업 파일 방식)
    double totalDuration = 0.0;
    if (isSummary) {
      // 요약 모드: 원본 영상의 총 시간 (백업 파일과 동일)
      totalDuration = segments.isNotEmpty ? segments.last.endSec : 0.0;
    } else {
      // 전체 모드: 원본 영상의 총 시간
      totalDuration = segments.isNotEmpty ? segments.last.endSec : 0.0;
    }
    final timelineFrames = (totalDuration * frameRate).round();
    
    buffer.writeln('  <library>');
    buffer.writeln('    <event name="Event">');
    buffer.writeln('      <project name="${isSummary ? "${videoName}_Summary" : videoName}">');
    buffer.writeln('        <sequence duration="$timelineFrames/${frameRate.round()}s" format="f1" tcStart="0s">');
    buffer.writeln('          <spine>');
    
    // 세그먼트별로 개별 클립 생성 (비디오와 자막이 1:1 매칭)
    if (isSummary) {
      // 요약 모드: 요약 세그먼트를 원본 위치에 그대로 배치 (백업 파일 방식)
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final startFrames = (segment.startSec * frameRate).round();
        final duration = segment.endSec - segment.startSec;
        final durationFrames = (duration * frameRate).round();
        
        // 백업 파일과 동일: start와 offset 모두 원본 위치 사용
        buffer.writeln('            <asset-clip name="$videoFileName" ref="a1" start="$startFrames/${frameRate.round()}s" offset="$startFrames/${frameRate.round()}s" duration="$durationFrames/${frameRate.round()}s">');
        buffer.writeln('              <title lane="1" name="${segment.text}" ref="e1" offset="$startFrames/${frameRate.round()}s" start="$startFrames/${frameRate.round()}s" duration="$durationFrames/${frameRate.round()}s">');
        buffer.writeln('                <text>');
        buffer.writeln('                  <text-style ref="ts$i">${segment.text}</text-style>');
        buffer.writeln('                </text>');
        buffer.writeln('                <text-style-def id="ts$i">');
        buffer.writeln('                  <text-style alignment="center" fontColor="255 255 255 1" font="Apple SD Gothic Neo" fontSize="70" lineSpacing="-14.0" baseline="-508.0" strokeColor="0 0 0 0" strokeWidth="-6"/>');
        buffer.writeln('                </text-style-def>');
        buffer.writeln('              </title>');
        buffer.writeln('            </asset-clip>');
      }
    } else {
      // 전체 모드: 각 세그먼트를 원래 타이밍으로 개별 클립 생성 (공백 포함)
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final startFrames = (segment.startSec * frameRate).round();
        final duration = segment.endSec - segment.startSec;
        final durationFrames = (duration * frameRate).round();
        
        buffer.writeln('            <asset-clip name="$videoFileName" ref="a1" start="$startFrames/${frameRate.round()}s" offset="$startFrames/${frameRate.round()}s" duration="$durationFrames/${frameRate.round()}s">');
        buffer.writeln('              <title lane="1" name="${segment.text}" ref="e1" offset="$startFrames/${frameRate.round()}s" start="$startFrames/${frameRate.round()}s" duration="$durationFrames/${frameRate.round()}s">');
        buffer.writeln('                <text>');
        buffer.writeln('                  <text-style ref="ts$i">${segment.text}</text-style>');
        buffer.writeln('                </text>');
        buffer.writeln('                <text-style-def id="ts$i">');
        buffer.writeln('                  <text-style alignment="center" fontColor="255 255 255 1" font="Apple SD Gothic Neo" fontSize="70" lineSpacing="-14.0" baseline="-508.0" strokeColor="0 0 0 0" strokeWidth="-6"/>');
        buffer.writeln('                </text-style-def>');
        buffer.writeln('              </title>');
        buffer.writeln('            </asset-clip>');
      }
    }
    
    buffer.writeln('          </spine>');
    buffer.writeln('        </sequence>');
    buffer.writeln('      </project>');
    buffer.writeln('    </event>');
    buffer.writeln('  </library>');
    buffer.writeln('</fcpxml>');
    
    return buffer.toString();
  }

  /// DaVinci Resolve XML 구조 생성  
  String _buildDaVinciXML(List<WhisperSegment> segments, bool isSummary) {
    final buffer = StringBuffer();
    final videoFileName = getVideoFileName();
    final videoName = videoFileName.replaceAll('.mp4', '');
    final metadata = _getVideoMetadata();
    final frameRate = metadata['frameRate'] as double;
    final width = metadata['width'] as int;
    final height = metadata['height'] as int;
    
    // DaVinci XML header (vrew 참조 구조와 동일)
    buffer.writeln('<?xml version="1.0" encoding="utf-8"?>');
    buffer.writeln('<fcpxml version="1.6">');
    buffer.writeln('  <import-options>');
    buffer.writeln('    <option value="1" key="suppress warnings"/>');
    buffer.writeln('  </import-options>');
    buffer.writeln('  <resources>');
    buffer.writeln('    <format id="f1" frameDuration="1/${frameRate.round()}s" width="$width" height="$height"/>');
    // 다빈치용 절대 경로 생성 (백업 파일 방식)
    // 다빈치용: /Volumes/Macintosh HD/ 접두사 제거
    String videoAbsolutePath = videoFileName;
    if (_appState.videoPath != null) {
      String cleanPath = _appState.videoPath!.replaceAll('\\', '/');
      // /Volumes/Macintosh HD/ 완전히 제거
      if (cleanPath.contains('/Volumes/Macintosh HD/')) {
        cleanPath = cleanPath.replaceAll('/Volumes/Macintosh HD', '');
      }
      videoAbsolutePath = 'file://$cleanPath';
    }
    final assetDurationFrames = segments.isNotEmpty ? (segments.last.endSec * frameRate).round() : 0;
    buffer.writeln('    <asset id="a1" src="$videoAbsolutePath" format="f1" duration="$assetDurationFrames/${frameRate.round()}s" name="$videoFileName" hasAudio="1" hasVideo="1" start="0/${frameRate.round()}s"/>');
    buffer.writeln('    <effect id="e1" name="Custom" uid=".../Titles.localized/Build In:Out.localized/Custom.localized/Custom.moti"/>');
    buffer.writeln('  </resources>');
    
    // DaVinci 시퀀스 지속시간 계산 (백업 파일 방식)
    double totalDuration = 0.0;
    if (isSummary) {
      // 요약 모드: 원본 영상의 총 시간 (백업 파일과 동일)
      totalDuration = segments.isNotEmpty ? segments.last.endSec : 0.0;
    } else {
      // 전체 모드: 원본 영상의 총 시간
      totalDuration = segments.isNotEmpty ? segments.last.endSec : 0.0;
    }
    final timelineFrames = (totalDuration * frameRate).round();
    
    buffer.writeln('  <library>');
    buffer.writeln('    <event>');
    buffer.writeln('      <project name="${isSummary ? "${videoName}_Summary" : videoName}">');
    buffer.writeln('        <sequence duration="$timelineFrames/${frameRate.round()}s" format="f1" tcStart="0s">');
    buffer.writeln('          <spine>');
    
    // 세그먼트별로 개별 클립 생성 (비디오와 자막이 1:1 매칭)
    if (isSummary) {
      // 요약 모드: 요약 세그먼트를 원본 위치에 그대로 배치 (백업 파일 방식)
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final startFrames = (segment.startSec * frameRate).round();
        final duration = segment.endSec - segment.startSec;
        final durationFrames = (duration * frameRate).round();
        
        // 다빈치용: start와 offset 모두 원본 위치 사용 (브루와 동일)
        buffer.writeln('            <asset-clip name="$videoFileName" ref="a1" start="$startFrames/${frameRate.round()}s" offset="$startFrames/${frameRate.round()}s" duration="$durationFrames/${frameRate.round()}s">');
        buffer.writeln('              <title lane="1" name="${segment.text}" ref="e1" offset="$startFrames/${frameRate.round()}s" start="$startFrames/${frameRate.round()}s" duration="$durationFrames/${frameRate.round()}s">');
        buffer.writeln('                <text>');
        buffer.writeln('                  <text-style ref="ts$i">${segment.text}</text-style>');
        buffer.writeln('                </text>');
        buffer.writeln('                <text-style-def id="ts$i">');
        buffer.writeln('                  <text-style alignment="center" fontColor="255 255 255 1" font="Apple SD Gothic Neo" fontSize="70" lineSpacing="0" baseline="0" strokeColor="0 0 0 0" strokeWidth="1"/>');
        buffer.writeln('                </text-style-def>');
        buffer.writeln('                <adjust-transform position="0 -43.79629629629629" scale="1 1" anchor="0 0"/>');
        buffer.writeln('              </title>');
        buffer.writeln('            </asset-clip>');
      }
    } else {
      // 전체 모드: 각 세그먼트를 원래 타이밍으로 개별 클립 생성 (공백 포함)
      for (int i = 0; i < segments.length; i++) {
        final segment = segments[i];
        final startFrames = (segment.startSec * frameRate).round();
        final duration = segment.endSec - segment.startSec;
        final durationFrames = (duration * frameRate).round();
        
        buffer.writeln('            <asset-clip name="$videoFileName" ref="a1" start="$startFrames/${frameRate.round()}s" offset="$startFrames/${frameRate.round()}s" duration="$durationFrames/${frameRate.round()}s">');
        buffer.writeln('              <title lane="1" name="${segment.text}" ref="e1" offset="$startFrames/${frameRate.round()}s" start="$startFrames/${frameRate.round()}s" duration="$durationFrames/${frameRate.round()}s">');
        buffer.writeln('                <text>');
        buffer.writeln('                  <text-style ref="ts$i">${segment.text}</text-style>');
        buffer.writeln('                </text>');
        buffer.writeln('                <text-style-def id="ts$i">');
        buffer.writeln('                  <text-style alignment="center" fontColor="255 255 255 1" font="Apple SD Gothic Neo" fontSize="70" lineSpacing="0" baseline="0" strokeColor="0 0 0 0" strokeWidth="1"/>');
        buffer.writeln('                </text-style-def>');
        buffer.writeln('                <adjust-transform position="0 -43.79629629629629" scale="1 1" anchor="0 0"/>');
        buffer.writeln('              </title>');
        buffer.writeln('            </asset-clip>');
      }
    }
    
    buffer.writeln('          </spine>');
    buffer.writeln('        </sequence>');
    buffer.writeln('      </project>');
    buffer.writeln('    </event>');
    buffer.writeln('  </library>');
    buffer.writeln('</fcpxml>');
    
    return buffer.toString();
  }
}