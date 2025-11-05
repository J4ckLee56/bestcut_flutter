import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'firestore_service.dart';
import 'firebase_functions_service.dart';
import '../theme/cursor_theme.dart';

class VersionService {
  static final VersionService _instance = VersionService._internal();
  factory VersionService() => _instance;
  VersionService._internal();

  final FirestoreService _firestoreService = FirestoreService();
  final FirebaseFunctionsService _functionsService = FirebaseFunctionsService();

  // 현재 앱 버전 정보
  String _currentVersion = '1.0.0';
  String _currentBuildNumber = '1';

  // 버전 정보 초기화
  Future<void> initialize() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
      _currentBuildNumber = packageInfo.buildNumber;
      
      if (kDebugMode) print('📱 VersionService: 현재 버전 - $_currentVersion ($_currentBuildNumber)');
    } catch (e) {
      if (kDebugMode) print('❌ VersionService: 버전 정보 초기화 실패: $e');
    }
  }

  // 현재 버전 정보 가져오기
  String get currentVersion => _currentVersion;
  String get currentBuildNumber => _currentBuildNumber;

  // 서버와 버전 비교하여 업데이트 필요 여부 확인
  Future<Map<String, dynamic>> checkForUpdates() async {
    try {
      // 1. Firebase Functions를 통한 업데이트 정보 조회 시도
      if (kDebugMode) print('📱 VersionService: Firebase Functions로 업데이트 정보 조회 시도');
      
      final platform = defaultTargetPlatform == TargetPlatform.macOS ? 'mac' : 'win';
      final functionsResult = await _functionsService.getUpdateInfo(platform: platform);
      
      if (functionsResult['success']) {
        final data = functionsResult['data'] as Map<String, dynamic>;
        final serverVersion = data['version'] as String?;
        final downloadUrl = data['url'] as String?;
        
        if (serverVersion != null) {
          // Firebase Functions에서 성공적으로 데이터를 가져온 경우
          final hasUpdate = _isNewerVersion(serverVersion, _currentVersion);
          
          if (kDebugMode) {
            print('📱 VersionService: Firebase Functions 버전 비교 결과');
            print('   - 현재 버전: $_currentVersion');
            print('   - 서버 버전: $serverVersion');
            print('   - 업데이트 필요: $hasUpdate');
          }

          return {
            'hasUpdate': hasUpdate,
            'currentVersion': _currentVersion,
            'serverVersion': serverVersion,
            'downloadUrl': downloadUrl,
            'message': hasUpdate 
              ? '새로운 버전($serverVersion)이 사용 가능합니다.'
              : '최신 버전을 사용 중입니다.',
          };
        }
      }
      
      // 2. Firebase Functions 실패 시 기존 Firestore 방식으로 fallback
      if (kDebugMode) print('⚠️ VersionService: Firebase Functions 실패, Firestore로 fallback');
      
      final updateInfo = await _firestoreService.getUpdateInfo();
      
      if (updateInfo == null) {
        if (kDebugMode) print('⚠️ VersionService: 서버에서 업데이트 정보를 가져올 수 없음');
        return {
          'hasUpdate': false,
          'message': '업데이트 정보를 확인할 수 없습니다.',
        };
      }

      final serverVersionMac = updateInfo['version_mac'] as String?;
      final serverVersionWin = updateInfo['version_win'] as String?;
      final urlMac = updateInfo['url_mac'] as String?;
      final urlWin = updateInfo['url_win'] as String?;

      // 플랫폼별 서버 버전 선택
      String? serverVersion;
      String? downloadUrl;
      
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        serverVersion = serverVersionMac;
        downloadUrl = urlMac;
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        serverVersion = serverVersionWin;
        downloadUrl = urlWin;
      }

      if (serverVersion == null) {
        if (kDebugMode) print('⚠️ VersionService: 현재 플랫폼에 대한 서버 버전 정보가 없음');
        return {
          'hasUpdate': false,
          'message': '현재 플랫폼에 대한 업데이트 정보가 없습니다.',
        };
      }

      // 버전 비교
      final hasUpdate = _isNewerVersion(serverVersion, _currentVersion);
      
      if (kDebugMode) {
        print('📱 VersionService: Firestore 버전 비교 결과');
        print('   - 현재 버전: $_currentVersion');
        print('   - 서버 버전: $serverVersion');
        print('   - 업데이트 필요: $hasUpdate');
      }

      return {
        'hasUpdate': hasUpdate,
        'currentVersion': _currentVersion,
        'serverVersion': serverVersion,
        'downloadUrl': downloadUrl,
        'message': hasUpdate 
          ? '새로운 버전($serverVersion)이 사용 가능합니다.'
          : '최신 버전을 사용 중입니다.',
      };
    } catch (e) {
      if (kDebugMode) print('❌ VersionService: 업데이트 확인 실패: $e');
      return {
        'hasUpdate': false,
        'message': '업데이트 확인 중 오류가 발생했습니다: $e',
      };
    }
  }

  // 버전 문자열 비교 (새로운 버전인지 확인)
  bool _isNewerVersion(String serverVersion, String currentVersion) {
    try {
      final serverParts = serverVersion.split('.').map(int.parse).toList();
      final currentParts = currentVersion.split('.').map(int.parse).toList();

      // 버전 부분 수 맞추기
      while (serverParts.length < 3) serverParts.add(0);
      while (currentParts.length < 3) currentParts.add(0);

      // 각 부분별로 비교
      for (int i = 0; i < 3; i++) {
        if (serverParts[i] > currentParts[i]) {
          return true; // 서버 버전이 더 높음
        } else if (serverParts[i] < currentParts[i]) {
          return false; // 현재 버전이 더 높음
        }
      }

      return false; // 동일한 버전
    } catch (e) {
      if (kDebugMode) print('❌ VersionService: 버전 비교 실패: $e');
      return false;
    }
  }

  // 업데이트 알림 다이얼로그 표시
  Future<void> showUpdateDialog(BuildContext context, Map<String, dynamic> updateInfo) async {
    if (!updateInfo['hasUpdate']) return;

    final serverVersion = updateInfo['serverVersion'] as String;
    final downloadUrl = updateInfo['downloadUrl'] as String?;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: CursorTheme.backgroundSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CursorTheme.radiusMedium),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: CursorTheme.cursorBlue,
                  borderRadius: BorderRadius.circular(CursorTheme.radiusSmall),
                ),
                child: const Icon(
                  Icons.system_update,
                  color: CursorTheme.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: CursorTheme.spacingM),
              Expanded(
                child: Text(
                  '업데이트 사용 가능',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: CursorTheme.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '새로운 버전이 사용 가능합니다.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: CursorTheme.textSecondary,
                ),
              ),
              const SizedBox(height: CursorTheme.spacingM),
              Container(
                padding: const EdgeInsets.all(CursorTheme.spacingM),
                decoration: CursorTheme.containerDecoration(
                  backgroundColor: CursorTheme.backgroundTertiary,
                  borderColor: CursorTheme.borderSecondary,
                  borderRadius: CursorTheme.radiusSmall,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildVersionRow('현재 버전', updateInfo['currentVersion'] as String, context),
                    const SizedBox(height: CursorTheme.spacingS),
                    _buildVersionRow('새 버전', serverVersion, context),
                  ],
                ),
              ),
              if (downloadUrl != null) ...[
                const SizedBox(height: CursorTheme.spacingM),
                Container(
                  padding: const EdgeInsets.all(CursorTheme.spacingM),
                  decoration: CursorTheme.containerDecoration(
                    backgroundColor: CursorTheme.cursorBlue.withOpacity(0.1),
                    borderColor: CursorTheme.cursorBlue,
                    borderRadius: CursorTheme.radiusSmall,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: CursorTheme.cursorBlue, size: 16),
                      const SizedBox(width: CursorTheme.spacingS),
                      Expanded(
                        child: Text(
                          '업데이트를 다운로드하여 최신 기능을 사용하세요.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: CursorTheme.cursorBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                '나중에',
                style: TextStyle(color: CursorTheme.textSecondary),
              ),
            ),
            if (downloadUrl != null)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openDownloadUrl(downloadUrl);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: CursorTheme.cursorBlue,
                  foregroundColor: CursorTheme.textPrimary,
                ),
                child: const Text('다운로드'),
              ),
          ],
        );
      },
    );
  }

  // 버전 정보 행 빌더
  Widget _buildVersionRow(String label, String version, BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: CursorTheme.textTertiary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: CursorTheme.spacingS),
        Text(
          version,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: CursorTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  // 다운로드 URL 열기
  void _openDownloadUrl(String url) {
    // 실제로는 url_launcher 패키지를 사용해야 함
    if (kDebugMode) print('🔗 VersionService: 다운로드 URL 열기: $url');
    // TODO: url_launcher 패키지 추가 후 구현
  }

  // 앱 시작 시 업데이트 확인
  Future<void> checkUpdatesOnStartup(BuildContext context) async {
    try {
      await initialize();
      final updateInfo = await checkForUpdates();
      
      if (updateInfo['hasUpdate']) {
        // 잠시 후 다이얼로그 표시 (앱 초기화 완료 후)
        Future.delayed(const Duration(seconds: 2), () {
          if (context.mounted) {
            showUpdateDialog(context, updateInfo);
          }
        });
      }
    } catch (e) {
      if (kDebugMode) print('❌ VersionService: 시작 시 업데이트 확인 실패: $e');
    }
  }
}

