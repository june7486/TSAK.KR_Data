import 'package:flutter/material.dart';

import 'build_info.dart';
import 'installer.dart';

/// APK 원격 업데이트 상태.
enum ApkUpdatePhase {
  idle,
  available,
  downloading,
  verifying,
  installing,
  done,
  error,
}

/// APK 자기 업데이트 컨트롤러 (앱 전역 싱글턴).
///
/// 사용 흐름:
///   1) [check] — 서버 `/apk.json` 조회 → 더 최신이면 phase=available.
///   2) [downloadAndInstall] — 다운로드 → SHA-256 검증 → 설치화면 호출.
///
/// · 웹([supportsApkSelfUpdate]==false)에서는 [check] 가 즉시 idle 로 끝난다
///   (웹은 기존 캐시 재로드 방식 사용).
class ApkUpdater extends ChangeNotifier {
  ApkUpdater._();
  static final ApkUpdater instance = ApkUpdater._();

  ApkUpdate? _update;
  ApkUpdate? get update => _update;

  ApkUpdatePhase _phase = ApkUpdatePhase.idle;
  ApkUpdatePhase get phase => _phase;

  double _progress = -1; // 0~1, 음수=미상
  double get progress => _progress;

  String _message = '';
  String get message => _message;

  bool get isBusy =>
      _phase == ApkUpdatePhase.downloading ||
      _phase == ApkUpdatePhase.verifying ||
      _phase == ApkUpdatePhase.installing;

  bool get hasUpdate => _phase == ApkUpdatePhase.available && _update != null;

  /// 배너를 그릴 조건 — 새 버전이 있거나, 진행 중일 때.
  bool get showBanner =>
      _update != null && (_phase == ApkUpdatePhase.available || isBusy);

  /// 서버에서 최신 APK 정보를 조회한다. (조용히 실패)
  Future<void> check({bool force = false}) async {
    if (!supportsApkSelfUpdate) return;
    if (_phase == ApkUpdatePhase.downloading ||
        _phase == ApkUpdatePhase.verifying ||
        _phase == ApkUpdatePhase.installing) {
      return; // 진행 중엔 재조회 금지
    }
    try {
      final u = await fetchApkUpdate();
      if (u == null) {
        // 정보 없음(오프라인/미배포) → 조용히 넘어간다.
        if (_phase != ApkUpdatePhase.done) {
          _phase = ApkUpdatePhase.idle;
          notifyListeners();
        }
        return;
      }
      _update = u;
      if (u.isNewer) {
        _phase = ApkUpdatePhase.available;
        _message = '새 버전 ${u.version} 을(를) 사용할 수 있습니다.';
      } else {
        _phase = ApkUpdatePhase.idle;
        _message = '최신 버전입니다.';
      }
      notifyListeners();
    } catch (_) {
      // 네트워크 실패 등 → 무시
    }
  }

  /// 다운로드 → 검증 → 설치 화면 호출.
  Future<void> downloadAndInstall(BuildContext context) async {
    final u = _update;
    if (u == null) return;
    if (isBusy) return;

    final messenger = ScaffoldMessenger.maybeOf(context);

    // 설치 권한(O+) 확인 — 없으면 설정 화면 안내
    final can = await canRequestInstall();
    if (!can) {
      _message = "'출처를 알 수 없는 앱 설치 허용'이 필요합니다. 설정에서 허용해 주세요.";
      notifyListeners();
      await openInstallPermissionSettings();
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('설정 → 이 앱의 "출처를 알 수 없는 앱 설치 허용"을 켜주세요.'),
          duration: Duration(seconds: 4),
        ),
      );
      // 허용 후 다시 시도하도록 안내만 하고 종료(사용자가 다시 버튼).
      return;
    }

    try {
      _phase = ApkUpdatePhase.downloading;
      _progress = -1;
      _message = '다운로드 중…';
      notifyListeners();

      final path = await downloadApkToTemp(
        u.url,
        onProgress: (recv, total) {
          _progress = total > 0 ? (recv / total).clamp(0.0, 1.0) : -1;
          notifyListeners();
        },
      );
      if (path.isEmpty) {
        throw Exception('다운로드 결과가 비어 있습니다.');
      }

      _phase = ApkUpdatePhase.verifying;
      _message = '무결성 검증 중…';
      notifyListeners();

      final ok = await verifyFileSha256(path, u.sha256);
      if (!ok) {
        _phase = ApkUpdatePhase.error;
        _message = '다운로드 파일이 손상되었습니다(서명/해시 불일치). 다시 시도해 주세요.';
        notifyListeners();
        messenger?.showSnackBar(SnackBar(content: Text(_message)));
        return;
      }

      _phase = ApkUpdatePhase.installing;
      _message = '설치 화면을 여는 중…';
      notifyListeners();

      final opened = await installApkFile(path);
      if (!opened) {
        _phase = ApkUpdatePhase.error;
        _message = '설치 화면을 열 수 없습니다. 설정에서 "출처를 알 수 없는 앱 설치 허용"을 확인하세요.';
        notifyListeners();
        messenger?.showSnackBar(SnackBar(content: Text(_message)));
        return;
      }

      _phase = ApkUpdatePhase.done;
      _message = '설치 화면에서 "설치"를 눌러 완료하세요.';
      notifyListeners();
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('설치 화면이 열렸습니다. "설치"를 눌러 완료하세요.'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      _phase = ApkUpdatePhase.error;
      _message = '업데이트 실패: $e';
      notifyListeners();
      messenger?.showSnackBar(SnackBar(content: Text(_message)));
    }
  }

  /// 사용자가 나중에 하도록 배너를 닫는다(세션 내).
  void dismiss() {
    if (_phase == ApkUpdatePhase.available) {
      _phase = ApkUpdatePhase.idle;
      notifyListeners();
    }
  }
}
