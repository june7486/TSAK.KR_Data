import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart' show TsakApp; // [turn66] 전역 네비게이터(navKey) 사용
import '../services/app_state.dart';
import '../services/apk_updater.dart';
import '../services/build_info.dart';
import '../services/web_nav.dart';
import '../theme/app_theme.dart';
import '../widgets/apk_update_banner.dart';
import '../widgets/busy_overlay.dart';
import '../widgets/ip_multi_account_dialog.dart';
import '../widgets/privacy_consent.dart';
import 'merch_shop_screen.dart';

/// 앱 잠금(인증) 화면
///  - 범스카우트 접근: ID "tiger+인가번호" + 개인 비밀번호 (예: tiger415)
///    · 관리자 로그인 창은 제거됨 — 같은 ID 칸에 관리자 아이디(task/tsak437 등)를
///      입력하면 서버가 관리자 계정으로 인증한다(통합 로그인).
///  - 비인가자 접근: ID "휴대폰 전화번호" + 비밀번호(뒤 4자리) / 신규회원 생성
///  - 마스터 접근: Corbuser7!@@ (모든 기능/통제, 불변)
class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    this.onUnlocked,
    this.initialTier = 'personal',
    this.initialId = '',
  });

  final VoidCallback? onUnlocked;

  /// 시작 탭 (QR 딥링크 등에서 지정)
  final String initialTier;

  /// 시작 시 프리필할 ID (QR 인가번호 등)
  final String initialId;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  late String _tier = widget.initialTier;
  final _ctrl = TextEditingController();
  late final TextEditingController _idCtrl = TextEditingController(
    text: widget.initialId,
  );
  bool _obscure = true;
  bool _busy = false;

  /// 로그인 진행 단계(작업중 오버레이 진행문구 갱신용).
  int _busyStep = 0;
  Timer? _busyTimer;
  bool _cacheBusy = false;
  bool _verBusy = false;
  bool _updating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 로그인 화면 진입 시: 구버전이면 캐시 자동 삭제 후 최신 버전을 재다운로드.
    //  (인터넷이 안 되면 아무 것도 하지 않고 기존 버전으로 그대로 진행)
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoUpdateCheck());
    // APK 자기 업데이트: 서버의 최신 APK 정보를 조회해 더 최신이면 배너 노출.
    //  (웹에서는 supportsApkSelfUpdate=false → 즉시 종료, 기존 방식 유지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ApkUpdater.instance.check();
    });
  }

  /// 구버전 감지 시 1회성으로 캐시를 지우고 최신 자산을 다시 받는다.
  ///
  /// - 오프라인/서버 오류 → [serverHasNewerVersion] 이 false → 그대로 진행.
  /// - 이미 이번 세션에서 재로드했으면 무한 루프 방지를 위해 건너뛴다.
  Future<void> _autoUpdateCheck() async {
    if (!mounted) return;
    bool newer;
    try {
      newer = await serverHasNewerVersion();
    } catch (_) {
      newer = false;
    }
    if (!mounted || !newer) return;

    // 세션당 1회만 자동 캐시삭제+재로드 (루프 방지)
    bool allowed = true;
    try {
      if (isWebRuntime && !guardAutoReloadOnce()) allowed = false;
    } catch (_) {}
    if (!allowed) return;

    // 새 버전이 있으면 무조건 캐시 삭제 후 최신 버전을 다시 다운로드한다.
    setState(() => _updating = true);
    try {
      await clearAppCache();
    } catch (_) {}
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 700));
    reloadPage(); // 최신 버전을 다시 다운로드
  }

  @override
  void dispose() {
    _busyTimer?.cancel();
    _ctrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  /// 로그인 대기 중 보여줄 진행 안내 문구(2~3줄).
  List<String> get _loginBusyLines {
    const steps = [
      '비밀번호를 확인하고 있습니다...',
      '서버(NAS)에 접속하여 인증하는 중...',
      '회원 정보와 권한을 불러오는 중...',
      '화면을 준비하고 있습니다...',
    ];
    final n = _busyStep.clamp(0, steps.length - 1);
    return steps.sublist(0, n + 1);
  }

  /// 로그인 대기 시작 — 오버레이를 띄우고 단계 문구를 자동 진행시킨다.
  void _startLoginBusy() {
    _busyStep = 0;
    _busyTimer?.cancel();
    _busyTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted || !_busy) return;
      if (_busyStep < 3) setState(() => _busyStep++);
    });
  }

  void _stopLoginBusy() {
    _busyTimer?.cancel();
    _busyTimer = null;
    _busyStep = 0;
  }

  Future<void> _submit() async {
    final v = _ctrl.text.trim();
    if (v.isEmpty) {
      setState(() => _error = '비밀번호를 입력하세요');
      return;
    }
    if (_tier != 'master' && _idCtrl.text.trim().isEmpty) {
      setState(() => _error = 'ID를 입력하세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _startLoginBusy();
    final state = context.read<AppState>();
    // (요구) 관리자 로그인 창 제거 — 범스카우트 탭의 ID 칸 하나로 관리자
    //  아이디(task/tsak437 등)도 받는다. 서버가 인가번호/관리자 계정을 모두 검증.
    final idInput = _idCtrl.text.trim();
    // 은하스카우트는 개인 로그인이지만 소속(corps)이 달라 별도 검증된다.
    final ok = _tier == 'eunha'
        ? await state.login('personal', v, id: idInput, corps: 'eunha')
        : await state.login(_tier, v, id: idInput);
    if (!mounted) return;
    _stopLoginBusy();
    setState(() => _busy = false);
    if (ok) {
      // [turn65] 같은 IP 다계정 접속 경고 — 로그인에 성공했더라도,
      //  최근 15분 안에 같은 회선에서 서로 다른 3개 이상 계정이 접속했다면
      //  한 번은 읽고 넘어가게 한다(차단·불이익 없음, 경고창만).
      //
      // [turn66] "확인하면 다시 로그인 창이 열림" 버그 수정
      //  원인: `state.login()` 안에서 notifyListeners() 가 이미 실행되어
      //        AuthGate 가 LockScreen → HomeScreen 으로 교체한다.
      //        즉 이 지점의 `context` 는 곧 트리에서 사라지는 "죽은 context"
      //        이고, 그 context 로 다이얼로그를 띄우면 닫히는 순간
      //        로그인 화면이 다시 그려졌다.
      //  해결: (1) 먼저 HomeScreen 으로 넘긴다.
      //        (2) 살아 있는 전역 Navigator(TsakApp.navKey) 로 경고창을 띄운다.
      final ipNotice = state.ipNotice;
      widget.onUnlocked?.call();
      if (ipNotice != null) {
        state.clearIpNotice(); // 한 번만 띄운다(뒤로 갔다 와도 반복 금지)
        final rootCtx = TsakApp.navKey.currentContext;
        // rootCtx 는 LockScreen 의 State.mounted 와 무관한 별도 context 이므로
        //  반드시 rootCtx 자체의 mounted 로 검사한다(analyzer 지적 반영).
        if (rootCtx != null && rootCtx.mounted) {
          await showIpMultiAccountDialog(rootCtx, ipNotice);
        }
      }
    } else {
      setState(() => _error = _hintForTier());
    }
  }

  /// 비인가자 신규회원 생성 → 생성 직후 자동 로그인
  Future<void> _createRegular() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    bool agreed = false;
    final created = await showDialog<Map<String, String>?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          // (요구) 키보드가 창을 줄여도 입력칸이 잘리지 않도록 스크롤.
          scrollable: true,
          title: const Text('신규회원 생성'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ID는 휴대폰 전화번호, 비밀번호는 전화번호 뒤 4자리로 자동 생성됩니다.',
                    style: TextStyle(fontSize: 12, color: AppColors.textGray),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '이름 (실명)',
                      helperText: '실명을 입력하세요 (닉네임 불가)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: '휴대폰 전화번호'),
                  ),
                  const SizedBox(height: 12),
                  // 개인정보 수집·이용 동의 (필수) — 동의해야 가입 가능
                  PrivacyConsentField(
                    agreed: agreed,
                    onChanged: (v) => setLocal(() => agreed = v),
                    showTitle: false,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
              onPressed: agreed
                  ? () => Navigator.pop(ctx, {
                      'name': nameCtrl.text.trim(),
                      'phone': phoneCtrl.text.trim(),
                    })
                  : null,
              child: const Text('생성'),
            ),
          ],
        ),
      ),
    );
    if (created == null || !mounted) return;
    final name = created['name'] ?? '';
    final phone = created['phone'] ?? '';
    if (name.isEmpty || phone.replaceAll(RegExp(r'[^0-9]'), '').length < 4) {
      setState(() => _error = '이름과 전화번호를 정확히 입력하세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _startLoginBusy();
    final state = context.read<AppState>();
    final m = await state.createRegularMember(name, phone);
    if (!mounted) return;
    if (m == null) {
      _stopLoginBusy();
      setState(() {
        _busy = false;
        _error = '이미 등록된 번호이거나 입력이 올바르지 않습니다';
      });
      return;
    }
    // 생성된 비밀번호 = 뒤 4자리
    final ok = await state.login('guest', m.phoneLast4, id: m.loginId);
    if (!mounted) return;
    _stopLoginBusy();
    setState(() => _busy = false);
    if (ok) {
      widget.onUnlocked?.call();
    } else {
      setState(() => _error = '생성 후 로그인에 실패했습니다. 다시 시도해 주세요');
    }
  }

  String _hintForTier() {
    switch (_tier) {
      case 'master':
        return '마스터 비밀번호가 올바르지 않습니다';
      case 'eunha':
        return 'ID(은하번호) 또는 비밀번호가 올바르지 않습니다';
      case 'personal':
        // ## 안내 개선: 'tiger416' 처럼 접두어를 붙여야 한다는 사실을 알려준다.
        //  서버는 접두어 없는 맨 인가번호('416') 로그인을 취약 로그인으로
        //  차단한다. 그래서 ID 형식을 안내하지 않으면 원인을 알 수 없다.
        return 'ID(예: tiger416 · 관리자 아이디) 또는 비밀번호가 올바르지 않습니다';
      case 'guest':
        return 'ID(전화번호) 또는 비밀번호(뒤 4자리)가 올바르지 않습니다';
      default:
        return 'ID 또는 앱 비밀번호가 올바르지 않습니다';
    }
  }

  /// 브라우저 캐시·서비스워커를 정리하고 페이지를 새로 고침한다.
  /// (업데이트가 반영되지 않을 때 사용)
  Future<void> _clearCache() async {
    if (_cacheBusy) return;
    setState(() => _cacheBusy = true);
    String msg;
    try {
      msg = await clearAppCache();
    } catch (_) {
      msg = '캐시 정리를 완료했습니다';
    }
    if (!mounted) return;
    setState(() => _cacheBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$msg · 새로 고침합니다'),
        backgroundColor: AppColors.purple,
        duration: const Duration(seconds: 2),
      ),
    );
    // 정리 후 최신 자산으로 페이지 재로드
    await Future<void>.delayed(const Duration(milliseconds: 450));
    reloadPage();
  }

  /// 서버(프록시)의 최신 빌드 버전과 현재 앱 버전을 비교해 안내한다.
  Future<void> _checkVersion() async {
    if (_verBusy) return;
    setState(() => _verBusy = true);
    VersionStatus st;
    try {
      st = await checkVersion();
    } catch (_) {
      st = VersionStatus.unknown;
    }
    if (!mounted) return;
    setState(() => _verBusy = false);
    String msg;
    Color bg = AppColors.purple;
    switch (st) {
      case VersionStatus.upToDate:
        msg = '최신 버전입니다 ($kBuildShort)';
        bg = AppColors.scoutGreen;
        break;
      case VersionStatus.serverNewer:
        msg = '새로운 버전이 있어 자동으로 다운로드합니다 (캐시 삭제)';
        bg = AppColors.taegeukRed;
        break;
      case VersionStatus.serverOlder:
        msg = '현재 버전이 서버보다 앞서 있습니다 ($kBuildShort)';
        break;
      case VersionStatus.unknown:
        msg = '버전을 확인할 수 없습니다 (오프라인?)';
        break;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        duration: const Duration(seconds: 3),
      ),
    );
    // 요구: 버전체크 결과 새 버전이 있으면 무조건 캐시 삭제(+최신 재다운로드).
    if (st == VersionStatus.serverNewer) {
      setState(() => _updating = true);
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await _clearCache();
    }
  }

  void _switchTier(String t) {
    setState(() {
      _tier = t;
      _error = null;
      _ctrl.clear();
      _idCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(gradient: AppColors.brandGradient),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/tsak_emblem.png',
                        width: 96,
                        height: 96,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.shield,
                          size: 84,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        '한국 범스카우트중앙회',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'TSAK 인가자 · 회원 통합 관리',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      if (_updating) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.8,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text(
                                '새로운 버전이 있어 다운로드 중입니다',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _tierTabs(),
                            const SizedBox(height: 16),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: _tierHelp(),
                            ),
                            const SizedBox(height: 12),
                            // ID 입력 — 관리자·범스카우트·비인가자 표시 (마스터만 비밀번호 전용)
                            if (_tier != 'master') ...[
                              TextField(
                                controller: _idCtrl,
                                autofocus: true,
                                // (요구) ID는 숫자뿐 아니라 영문·한글·외국어·특수문자도 허용
                                //  → 어떤 티어에서도 항상 쿼티(문자) 키보드를 노출한다.
                                keyboardType: TextInputType.text,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: _tier == 'guest'
                                      ? 'ID (전화번호)'
                                      : (_tier == 'personal'
                                            ? 'ID (tiger+인가번호, 예: tiger415)'
                                            : 'ID (은하+인가번호, 예: 은하100)'),
                                  prefixIcon: const Icon(Icons.badge_outlined),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextField(
                              controller: _ctrl,
                              obscureText: _obscure,
                              autofocus: _tier == 'master',
                              textInputAction: TextInputAction.go,
                              onSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: _tier == 'guest'
                                    ? '비밀번호 (뒤 4자리)'
                                    : '비밀번호',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: AppColors.taegeukRed,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        color: AppColors.taegeukRed,
                                        fontSize: 12.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.purple,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: (_busy || _updating)
                                    ? null
                                    : _submit,
                                icon: _busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.login),
                                label: const Text('접속'),
                              ),
                            ),
                            if (_tier == 'guest') ...[
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.scoutGreen,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 13,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: _busy ? null : _createRegular,
                                  icon: const Icon(
                                    Icons.person_add_alt_1,
                                    size: 20,
                                  ),
                                  label: const Text(
                                    '신규회원 가입 (ID=전화번호 · PW=뒤 4자리)',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // 로그인 없이 수품구매(굿즈) 열람·주문
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.6),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MerchShopScreen(),
                            ),
                          ),
                          icon: const Icon(
                            Icons.shopping_bag_outlined,
                            size: 19,
                          ),
                          label: const Text(
                            '수품구매 (로그인 없이 주문)',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '개발: 이승준 · 범스카우트415 · june7558@gmail.com',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '한국 범스카우트중앙회 $versionShortLabel',
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // APK 원격 업데이트 배너 (새 버전이 있으면 표시)
                      AnimatedBuilder(
                        animation: ApkUpdater.instance,
                        builder: (context, _) {
                          final up = ApkUpdater.instance;
                          if (!up.showBanner) return const SizedBox.shrink();
                          return ApkUpdateBanner(
                            update: up.update,
                            busy: up.isBusy,
                            progress: up.progress,
                            compact: true,
                            onUpdate: () => up.downloadAndInstall(context),
                          );
                        },
                      ),
                      // 바로가기 — 3분할: 홈페이지 / 네이버 카페 / 故 노경하 추모관
                      //  [요구 2026-11-04] "노경하 추모관 위치를 메인화면 하단을
                      //   3분할 하여 Homepage/Naver Cafe/노경하추모관 이렇게
                      //   구분하고 바로가기 링크를 넣어줘"
                      //
                      //  추모관은 외부 사이트가 아니라 **같은 웹서버의
                      //  `memorial.html`** 이다(빌드 시 web_custom_backup 에서 복사).
                      //  그래서 현재 접속 origin 을 붙여 열어야 하며,
                      //  네이티브(APK)에는 memorial.html 이 없으므로 NAS 주소를 쓴다.
                      Row(
                        children: [
                          Expanded(
                            child: _shortcutBtn(
                              icon: Icons.public,
                              label: 'Homepage',
                              url: 'https://www.tigerscout.kr',
                              color: AppColors.taegeukBlue,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _shortcutBtn(
                              icon: Icons.forum_outlined,
                              label: 'Naver Cafe',
                              url: 'https://cafe.naver.com/tigerscoutkr',
                              color: AppColors.scoutGreen,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _shortcutBtn(
                              icon: Icons.local_florist,
                              label: '노경하 추모관',
                              url: _memorialUrl,
                              color: AppColors.purple,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // 업데이트 반영: 캐시 정리 / 버전 확인 (작게)
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 4,
                        children: [
                          TextButton.icon(
                            onPressed: _cacheBusy ? null : _clearCache,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white.withValues(
                                alpha: 0.8,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: _cacheBusy
                                ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.6,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.refresh, size: 13),
                            label: const Text(
                              '캐시 삭제',
                              style: TextStyle(fontSize: 10.5),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _checkVersion,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white.withValues(
                                alpha: 0.8,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              minimumSize: const Size(0, 28),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            icon: const Icon(Icons.verified_outlined, size: 13),
                            label: const Text(
                              '버전 확인',
                              style: TextStyle(fontSize: 10.5),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 로그인/회원생성 대기 — 멈춘 것이 아님을 보여주는 공통 작업중 오버레이
          BusyOverlay(
            visible: _busy,
            title: _tier == 'guest' ? '회원 확인 중입니다' : '로그인 중입니다',
            lines: _loginBusyLines,
          ),
        ],
      ),
    );
  }

  /// 하단 바로가기 버튼 — 클릭 시 새창으로 외부 링크를 연다.
  /// 故 노경하 선배님 추모관 주소.
  ///
  /// 추모관은 외부 도메인이 아니라 **이 앱과 같은 웹서버의 `memorial.html`** 이다.
  /// (빌드 마지막 단계에서 `web_custom_backup/memorial.html` 을 `build/web` 으로 복사)
  ///
  /// · 웹  : 현재 접속 origin + `/memorial.html`  (novita·gabia 어디서 열어도 맞다)
  /// · 네이티브(APK) : `memorial.html` 이 앱에 없으므로 NAS 공개 주소로 연다.
  static const String _memorialFallbackUrl =
      'https://5071-i0wgdg3il1ohzxyvietj8-0e616f0a.sandbox.novita.ai/memorial.html';

  String get _memorialUrl {
    final origin = webOrigin();
    if (origin.trim().isEmpty) return _memorialFallbackUrl;
    return '${origin.replaceAll(RegExp(r'/+$'), '')}/memorial.html';
  }

  /// 하단 바로가기 버튼.
  ///
  /// [요구 2026-11-04] "추모관 → 노경하 추모관" 으로 이름이 길어졌다.
  /// 3분할 폭(좁은 휴대폰에서 약 95px)에 '노경하 추모관'(6자) + 아이콘을
  /// **가로로** 넣으면 반드시 잘린다. 그래서 아이콘을 **위**로 올려
  /// 세로 2줄로 쌓고, 글자는 한 줄에 다 들어가게 했다.
  /// (OutlinedButton.icon 은 아이콘이 항상 앞에 오므로 Column 으로 직접 만든다)
  Widget _shortcutBtn({
    required IconData icon,
    required String label,
    required String url,
    required Color color,
  }) {
    return OutlinedButton(
      onPressed: () => _openExternal(url),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
        backgroundColor: color.withValues(alpha: 0.28),
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 3),
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(height: 3),
          // FittedBox 로 폭에 맞춰 자동 축소 — 아주 좁은 화면에서도 안 잘린다.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 외부 링크를 새창(웹) / 기본 브라우저(네이티브)로 연다.
  Future<void> _openExternal(String url) async {
    try {
      if (isWebRuntime) {
        openUrlInNewTab(url);
        return;
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('링크를 열 수 없습니다: $url')));
        }
      }
    }
  }

  Widget _tierTabs() {
    // 첫 화면 로그인 위치 — 사용 빈도순으로 재배치하여 관리자 로그인 탭을
    //  맨 앞에서 뒤쪽으로 옮긴다.
    //  범스카우트(다수) → 비인가자 → 관리자 → 마스터(최소)  ※ 4개 버튼 단일 행.
    //  ※ 은하스카우트는 **첫 화면 버튼에서 제외**한다(요구) — 관리자·마스터는
    //     마스터 관리창 > '은하스카우트' 메뉴에서 별도 진입한다.
    final tabs = [
      ('personal', '범스카우트', Icons.person),
      ('guest', '비인가자', Icons.person_outline),
      ('master', '마스터', Icons.workspace_premium),
    ];
    return Row(children: [for (final t in tabs) _tierChip(t)]);
  }

  Widget _tierChip((String, String, IconData) t) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: GestureDetector(
          onTap: () => _switchTier(t.$1),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: _tier == t.$1
                  ? AppColors.purple
                  : AppColors.purple.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(
                  t.$3,
                  size: 18,
                  color: _tier == t.$1 ? Colors.white : AppColors.purple,
                ),
                const SizedBox(height: 4),
                Text(
                  t.$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _tier == t.$1 ? Colors.white : AppColors.purple,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tierHelp() {
    String text;
    switch (_tier) {
      case 'master':
        text = '모든 기능·초기화·통제 권한 (변경 불가)';
        break;
      case 'personal':
        // (요구) 문구 변경 — 최초 비밀번호는 관리자 문의, 접속 후 변경 가능.
        text = 'ID = tiger + 본인 인가번호 (예: tiger415)\n'
            '비밀번호는 본인 설정: 최초 비밀번호는 관리자께 문의 '
            '→ 접속 후 비밀번호 변경 가능';
        break;
      case 'eunha':
        // 은하스카우트 — ID 형식(은하+인가번호)만 안내, 비밀번호 규칙은 노출하지 않는다(요구).
        text = 'ID = 은하 + 본인 인가번호 (예: 은하100)';
        break;
      case 'guest':
        text = 'ID=휴대폰 전화번호 · 비밀번호=전화번호 뒤 4자리';
        break;
      default:
        text = 'ID와 비밀번호를 입력하세요 (불법접속은 처벌됩니다.)';
    }
    return Row(
      key: ValueKey(_tier),
      children: [
        const Icon(Icons.info_outline, size: 15, color: AppColors.textGray),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: AppColors.textGray),
          ),
        ),
      ],
    );
  }
}
