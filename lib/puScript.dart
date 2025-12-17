// *****************************************************************************
// BILL-styled refactor with XO golden loader
// *****************************************************************************

// ВАЖНО:
// - ВСЕ строковые литералы и raw-строки ОСТАВЛЕНЫ КАК ЕСТЬ ("" / '').
// - Переименованы ВСЕ классы, методы, поля и локальные переменные в стиле BILL.
// - Сохранён исходный функционал + добавлен новый загрузчик XO.
// *****************************************************************************

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appsflyer_sdk/appsflyer_sdk.dart'
    show AppsFlyerOptions, AppsflyerSdk;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodCall, MethodChannel, SystemUiOverlayStyle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

// Если эти классы есть в main.dart – оставь импорт.
import 'main.dart' show MafiaHarbor, CaptainHarbor, BillHarbor;

// ============================================================================
// BILL инфраструктура и паттерны
// ============================================================================

class BillCoreLog {
  const BillCoreLog();

  void billCoreLogInfo(Object billCoreMsg) =>
      debugPrint('[WheelLogger] $billCoreMsg');

  void billCoreLogWarn(Object billCoreMsg) =>
      debugPrint('[WheelLogger/WARN] $billCoreMsg');

  void billCoreLogErr(Object billCoreMsg) =>
      debugPrint('[WheelLogger/ERR] $billCoreMsg');
}

class BillCoreVault {
  static final BillCoreVault _billCoreSingleton = BillCoreVault._billCoreInternal();
  BillCoreVault._billCoreInternal();
  factory BillCoreVault() => _billCoreSingleton;

  final BillCoreLog billCoreLogger = const BillCoreLog();
}

// ============================================================================
// Константы (статистика/кеш)
// ============================================================================

const String kBillCoreLoadedOnceKey = 'wheel_loaded_once';
const String kBillCoreStatEndpoint =
    'https://getgame.portalroullete.bar/stat';
const String kBillCoreCachedFcmKey = 'wheel_cached_fcm';

// ============================================================================
// BILL утилиты: BillCoreKit
// ============================================================================

class BillCoreKit {
  static bool billCoreLooksLikeBareMail(Uri billCoreUri) {
    final billCoreScheme = billCoreUri.scheme;
    if (billCoreScheme.isNotEmpty) return false;
    final billCoreRaw = billCoreUri.toString();
    return billCoreRaw.contains('@') && !billCoreRaw.contains(' ');
  }

  static Uri billCoreToMailto(Uri billCoreUri) {
    final billCoreFull = billCoreUri.toString();
    final billCoreBits = billCoreFull.split('?');
    final billCoreWho = billCoreBits.first;
    final billCoreQuery = billCoreBits.length > 1
        ? Uri.splitQueryString(billCoreBits[1])
        : <String, String>{};
    return Uri(
      scheme: 'mailto',
      path: billCoreWho,
      queryParameters: billCoreQuery.isEmpty ? null : billCoreQuery,
    );
  }

  static Uri billCoreGmailize(Uri billCoreMail) {
    final billCoreQp = billCoreMail.queryParameters;
    final billCoreParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (billCoreMail.path.isNotEmpty) 'to': billCoreMail.path,
      if ((billCoreQp['subject'] ?? '').isNotEmpty)
        'su': billCoreQp['subject']!,
      if ((billCoreQp['body'] ?? '').isNotEmpty)
        'body': billCoreQp['body']!,
      if ((billCoreQp['cc'] ?? '').isNotEmpty)
        'cc': billCoreQp['cc']!,
      if ((billCoreQp['bcc'] ?? '').isNotEmpty)
        'bcc': billCoreQp['bcc']!,
    };
    return Uri.https('mail.google.com', '/mail/', billCoreParams);
  }

  static String billCoreOnlyDigits(String billCoreSource) =>
      billCoreSource.replaceAll(RegExp(r'[^0-9+]'), '');
}

// ============================================================================
// Сервис открытия внешних ссылок/протоколов (BillCoreLinker)
// ============================================================================

class BillCoreLinker {
  static Future<bool> billCoreOpen(Uri billCoreUri) async {
    try {
      if (await launchUrl(
        billCoreUri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }
      return await launchUrl(
        billCoreUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (billCoreError) {
      debugPrint('WheelLinker error: $billCoreError; url=$billCoreUri');
      try {
        return await launchUrl(
          billCoreUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }
}

// ============================================================================
// FCM Background Handler — BILL крупье в бэкграунде
// ============================================================================

@pragma('vm:entry-point')
Future<void> billCoreBgDealer(RemoteMessage billCoreMessage) async {
  debugPrint("Spin ID: ${billCoreMessage.messageId}");
  debugPrint("Spin Data: ${billCoreMessage.data}");
}

// ============================================================================
// BILL Device Deck: информация об устройстве
// ============================================================================

class BillCoreDeviceInfoDeck {
  String? billCoreDeviceId;
  String? billCoreSessionId = 'wheel-one-off';
  String? billCorePlatformKind;
  String? billCoreOsBuild;
  String? billCoreAppVersion;
  String? billCoreLocale;
  String? billCoreTimezone;
  bool billCorePushEnabled = true;

  Future<void> billCoreInit() async {
    final billCoreInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final billCoreAndroid = await billCoreInfo.androidInfo;
      billCoreDeviceId = billCoreAndroid.id;
      billCorePlatformKind = 'android';
      billCoreOsBuild = billCoreAndroid.version.release;
    } else if (Platform.isIOS) {
      final billCoreIos = await billCoreInfo.iosInfo;
      billCoreDeviceId = billCoreIos.identifierForVendor;
      billCorePlatformKind = 'ios';
      billCoreOsBuild = billCoreIos.systemVersion;
    }

    final billCorePackageInfo = await PackageInfo.fromPlatform();
    billCoreAppVersion = billCorePackageInfo.version;
    billCoreLocale = Platform.localeName.split('_').first;
    billCoreTimezone = timezone.local.name;
    billCoreSessionId =
    'wheel-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> billCoreAsMap({String? billCoreFcm}) => {
    'fcm_token': billCoreFcm ?? 'missing_token',
    'device_id': billCoreDeviceId ?? 'missing_id',
    'app_name': 'bestoffers',
    'instance_id': billCoreSessionId ?? 'missing_session',
    'platform': billCorePlatformKind ?? 'missing_system',
    'os_version': billCoreOsBuild ?? 'missing_build',
    'app_version': billCoreAppVersion ?? 'missing_app',
    'language': billCoreLocale ?? 'en',
    'timezone': billCoreTimezone ?? 'UTC',
    'push_enabled': billCorePushEnabled,
  };
}

// ============================================================================
// BILL шпион: AppsFlyer (BillCoreSpy)
// ============================================================================

class BillCoreSpy {
  AppsFlyerOptions? billCoreOptions;
  AppsflyerSdk? billCoreSdk;

  String billCoreAfUid = '';
  String billCoreAfData = '';

  void billCoreStart({VoidCallback? billCoreOnUpdate}) {
    final billCoreOpts = AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6756072063',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    billCoreOptions = billCoreOpts;
    billCoreSdk = AppsflyerSdk(billCoreOpts);

    billCoreSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    billCoreSdk?.startSDK(
      onSuccess: () =>
          BillCoreVault().billCoreLogger.billCoreLogInfo('WheelSpy started'),
      onError: (billCoreCode, billCoreMsg) =>
          BillCoreVault().billCoreLogger.billCoreLogErr(
              'WheelSpy error $billCoreCode: $billCoreMsg'),
    );

    billCoreSdk?.onInstallConversionData((billCoreValue) {
      billCoreAfData = billCoreValue.toString();
      billCoreOnUpdate?.call();
    });

    billCoreSdk?.getAppsFlyerUID().then((billCoreValue) {
      billCoreAfUid = billCoreValue.toString();
      billCoreOnUpdate?.call();
    });
  }
}

// ============================================================================
// BILL мост для FCM токена (BillCoreFcmBridge)
// ============================================================================

class BillCoreFcmBridge {
  final BillCoreLog _billCoreLog = const BillCoreLog();
  String? _billCoreToken;
  final List<void Function(String)> _billCoreWaiters =
  <void Function(String)>[];

  String? get billCoreToken => _billCoreToken;

  BillCoreFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall billCoreCall) async {
      if (billCoreCall.method == 'setToken') {
        final String billCoreTokenString =
        billCoreCall.arguments as String;
        if (billCoreTokenString.isNotEmpty) {
          _billCoreSetToken(billCoreTokenString);
        }
      }
    });

    _billCoreRestoreToken();
  }

  Future<void> _billCoreRestoreToken() async {
    try {
      final billCorePrefs = await SharedPreferences.getInstance();
      final billCoreCached =
      billCorePrefs.getString(kBillCoreCachedFcmKey);
      if (billCoreCached != null && billCoreCached.isNotEmpty) {
        _billCoreSetToken(billCoreCached, billCoreNotify: false);
      }
    } catch (_) {}
  }

  Future<void> _billCorePersistToken(String billCoreToken) async {
    try {
      final billCorePrefs = await SharedPreferences.getInstance();
      await billCorePrefs.setString(kBillCoreCachedFcmKey, billCoreToken);
    } catch (_) {}
  }

  void _billCoreSetToken(String billCoreToken, {bool billCoreNotify = true}) {
    _billCoreToken = billCoreToken;
    _billCorePersistToken(billCoreToken);
    if (billCoreNotify) {
      for (final billCoreCallback
      in List<void Function(String)>.from(_billCoreWaiters)) {
        try {
          billCoreCallback(billCoreToken);
        } catch (billCoreErr) {
          _billCoreLog.billCoreLogWarn('fcm waiter error: $billCoreErr');
        }
      }
      _billCoreWaiters.clear();
    }
  }

  Future<void> billCoreWaitToken(
      Function(String billCoreToken) billCoreOnToken) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((_billCoreToken ?? '').isNotEmpty) {
        billCoreOnToken(_billCoreToken!);
        return;
      }

      _billCoreWaiters.add(billCoreOnToken);
    } catch (billCoreErr) {
      _billCoreLog.billCoreLogErr('wheelWaitToken error: $billCoreErr');
    }
  }
}

// ============================================================================
// BILL XO Loader: золотые буквы "X" и "O" на черном фоне
// ============================================================================

class BillCoreXoLoader extends StatefulWidget {
  const BillCoreXoLoader({Key? key}) : super(key: key);

  @override
  State<BillCoreXoLoader> createState() => _BillCoreXoLoaderState();
}

class _BillCoreXoLoaderState extends State<BillCoreXoLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController billCoreAnimController;
  late Animation<double> billCoreGlowAnim;
  late Animation<double> billCoreSpacingAnim;

  @override
  void initState() {
    super.initState();
    billCoreAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    billCoreGlowAnim = CurvedAnimation(
      parent: billCoreAnimController,
      curve: Curves.easeInOutSine,
    );

    billCoreSpacingAnim = CurvedAnimation(
      parent: billCoreAnimController,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    billCoreAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext billCoreContext) {
    final billCoreSize = MediaQuery.of(billCoreContext).size;
    final billCoreFontSize = billCoreSize.width * 0.22;
    final billCorePrimaryGold = const Color(0xFFFFD700);
    final billCoreDeepGold = const Color(0xFFB8860B);
    final billCoreDarkGold = const Color(0xFF4A3200);

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: billCoreAnimController,
        builder: (billCoreCtx, billCoreChild) {
          final billCoreGlow = 0.35 + billCoreGlowAnim.value * 0.65;
          final billCoreBlurRadius = 25.0 * billCoreGlow;
          final billCoreLetterSpacing = 4.0 + 22.0 * billCoreSpacingAnim.value;

          return Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Тёмное золотое пятно-фон
                Container(
                  width: billCoreSize.width * 0.7,
                  height: billCoreSize.width * 0.7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        billCoreDarkGold.withOpacity(0.0),
                        billCoreDarkGold.withOpacity(0.7 * billCoreGlow),
                        Colors.black,
                      ],
                      stops: const [0.0, 0.6, 1.0],
                    ),
                  ),
                ),
                // Буквы XO
                ShaderMask(
                  shaderCallback: (billCoreRect) {
                    return LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.9),
                        billCorePrimaryGold,
                        billCoreDeepGold,
                      ],
                    ).createShader(billCoreRect);
                  },
                  blendMode: BlendMode.srcATop,
                  child: Text(
                    'XO',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: billCoreFontSize,
                      fontWeight: FontWeight.w900,
                      letterSpacing: billCoreLetterSpacing,
                      color: billCorePrimaryGold,
                      shadows: [
                        Shadow(
                          color: billCorePrimaryGold.withOpacity(0.9),
                          blurRadius: billCoreBlurRadius,
                        ),
                        Shadow(
                          color: billCoreDeepGold.withOpacity(0.9),
                          blurRadius: billCoreBlurRadius * 0.7,
                        ),
                        Shadow(
                          color: Colors.black.withOpacity(0.8),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                // Лёгкое свечение дугой вокруг
                IgnorePointer(
                  child: CustomPaint(
                    size: Size.square(billCoreSize.width * 0.5),
                    painter: _BillCoreXoHaloPainter(
                      billCoreIntensity: billCoreGlow,
                      billCorePrimaryGold: billCorePrimaryGold,
                      billCoreDeepGold: billCoreDeepGold,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BillCoreXoHaloPainter extends CustomPainter {
  _BillCoreXoHaloPainter({
    required this.billCoreIntensity,
    required this.billCorePrimaryGold,
    required this.billCoreDeepGold,
  });

  final double billCoreIntensity;
  final Color billCorePrimaryGold;
  final Color billCoreDeepGold;

  @override
  void paint(Canvas billCoreCanvas, Size billCoreSize) {
    final billCoreCenter =
    Offset(billCoreSize.width / 2, billCoreSize.height / 2);
    final billCoreRadius = billCoreSize.width / 2.2;

    final billCorePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 + 4 * billCoreIntensity
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          billCorePrimaryGold.withOpacity(0.0),
          billCorePrimaryGold.withOpacity(0.4 * billCoreIntensity),
          billCoreDeepGold.withOpacity(0.8 * billCoreIntensity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.35, 0.55, 0.8, 1.0],
      ).createShader(
        Rect.fromCircle(center: billCoreCenter, radius: billCoreRadius),
      )
      ..maskFilter =
      MaskFilter.blur(BlurStyle.outer, 18 * billCoreIntensity);

    billCoreCanvas.drawArc(
      Rect.fromCircle(center: billCoreCenter, radius: billCoreRadius),
      -0.4,
      3.6,
      false,
      billCorePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _BillCoreXoHaloPainter billCoreOld) =>
      billCoreOld.billCoreIntensity != billCoreIntensity;
}

// ============================================================================
// BILL статистика (аналог wheelFinalUrl / wheelPostStat)
// ============================================================================

Future<String> billCoreFinalUrl(
    String billCoreStartUrl, {
      int billCoreMaxHops = 10,
    }) async {
  final billCoreHttpClient = HttpClient();

  try {
    Uri billCoreCurrentUri = Uri.parse(billCoreStartUrl);

    for (int billCoreI = 0; billCoreI < billCoreMaxHops; billCoreI++) {
      final billCoreReq = await billCoreHttpClient.getUrl(billCoreCurrentUri);
      billCoreReq.followRedirects = false;
      final billCoreResp = await billCoreReq.close();

      if (billCoreResp.isRedirect) {
        final billCoreLoc =
        billCoreResp.headers.value(HttpHeaders.locationHeader);
        if (billCoreLoc == null || billCoreLoc.isEmpty) break;

        final billCoreNextUri = Uri.parse(billCoreLoc);
        billCoreCurrentUri = billCoreNextUri.hasScheme
            ? billCoreNextUri
            : billCoreCurrentUri.resolveUri(billCoreNextUri);
        continue;
      }

      return billCoreCurrentUri.toString();
    }

    return billCoreCurrentUri.toString();
  } catch (billCoreErr) {
    debugPrint('wheelFinalUrl error: $billCoreErr');
    return billCoreStartUrl;
  } finally {
    billCoreHttpClient.close(force: true);
  }
}

Future<void> billCorePostStat({
  required String billCoreEvent,
  required int billCoreTimeStart,
  required String billCoreUrl,
  required int billCoreTimeFinish,
  required String billCoreAppSid,
  int? billCoreFirstPageTs,
}) async {
  try {
    final billCoreResolved = await billCoreFinalUrl(billCoreUrl);
    final billCorePayload = <String, dynamic>{
      'event': billCoreEvent,
      'timestart': billCoreTimeStart,
      'timefinsh': billCoreTimeFinish,
      'url': billCoreResolved,
      'appleID': '6755681349',
      'open_count': '$billCoreAppSid/$billCoreTimeStart',
    };

    debugPrint('wheelStat $billCorePayload');

    final billCoreResp = await http.post(
      Uri.parse('$kBillCoreStatEndpoint/$billCoreAppSid'),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(billCorePayload),
    );

    debugPrint(
        'wheelStat resp=${billCoreResp.statusCode} body=${billCoreResp.body}');
  } catch (billCoreErr) {
    debugPrint('wheelPostStat error: $billCoreErr');
  }
}

// ============================================================================
// BILL WebView-стол — BillCoreTableView
// ============================================================================

class BillCoreTableView extends StatefulWidget with WidgetsBindingObserver {
  String billCoreStartingLane;
  BillCoreTableView(this.billCoreStartingLane, {super.key});

  @override
  State<BillCoreTableView> createState() =>
      _BillCoreTableViewState(billCoreStartingLane);
}

class _BillCoreTableViewState extends State<BillCoreTableView>
    with WidgetsBindingObserver {
  _BillCoreTableViewState(this._billCoreCurrentLane);

  final BillCoreVault _billCoreVault = BillCoreVault();

  late InAppWebViewController _billCoreWebController;
  String? _billCorePushToken;
  final BillCoreDeviceInfoDeck _billCoreDeviceDeck =
  BillCoreDeviceInfoDeck();
  final BillCoreSpy _billCoreSpy = BillCoreSpy();

  bool _billCoreOverlayBusy = false;
  String _billCoreCurrentLane;
  DateTime? _billCoreLastPausedAt;

  bool _billCoreLoadedOnceSent = false;
  int? _billCoreFirstPageTs;
  int _billCoreStartLoadTs = 0;

  final Set<String> _billCoreExternalHosts = {
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'bnl.com',
    'www.bnl.com',
    'facebook.com',
    'www.facebook.com',
    'm.facebook.com',
    'instagram.com',
    'www.instagram.com',
    'twitter.com',
    'www.twitter.com',
    'x.com',
    'www.x.com',
  };

  final Set<String> _billCoreExternalSchemes = {
    'tg',
    'telegram',
    'whatsapp',
    'bnl',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
  };

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    FirebaseMessaging.onBackgroundMessage(billCoreBgDealer);

    _billCoreFirstPageTs = DateTime.now().millisecondsSinceEpoch;

    _billCoreInitPushAndGetToken();
    _billCoreDeviceDeck.billCoreInit();
    _billCoreWireForegroundPushHandlers();
    _billCoreBindPlatformNotificationTap();
    _billCoreSpy.billCoreStart(billCoreOnUpdate: () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState billCoreState) {
    if (billCoreState == AppLifecycleState.paused) {
      _billCoreLastPausedAt = DateTime.now();
    }
    if (billCoreState == AppLifecycleState.resumed) {
      if (Platform.isIOS && _billCoreLastPausedAt != null) {
        final billCoreNow = DateTime.now();
        final billCoreDrift = billCoreNow.difference(_billCoreLastPausedAt!);
        if (billCoreDrift > const Duration(minutes: 25)) {
          _billCoreForceReloadToLobby();
        }
      }
      _billCoreLastPausedAt = null;
    }
  }

  void _billCoreForceReloadToLobby() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => BillHarbor( billSignal: '',),
        ),
            (billCoreRoute) => false,
      );
    });
  }

  // --------------------------------------------------------------------------
  // Push / FCM
  // --------------------------------------------------------------------------
  void _billCoreWireForegroundPushHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage billCoreMsg) {
      if (billCoreMsg.data['uri'] != null) {
        _billCoreNavigateTo(billCoreMsg.data['uri'].toString());
      } else {
        _billCoreReturnToCurrentLane();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage billCoreMsg) {
      if (billCoreMsg.data['uri'] != null) {
        _billCoreNavigateTo(billCoreMsg.data['uri'].toString());
      } else {
        _billCoreReturnToCurrentLane();
      }
    });
  }

  void _billCoreNavigateTo(String billCoreNewLane) async {
    await _billCoreWebController.loadUrl(
      urlRequest: URLRequest(url: WebUri(billCoreNewLane)),
    );
  }

  void _billCoreReturnToCurrentLane() async {
    Future.delayed(const Duration(seconds: 3), () {
      _billCoreWebController.loadUrl(
        urlRequest: URLRequest(url: WebUri(_billCoreCurrentLane)),
      );
    });
  }

  Future<void> _billCoreInitPushAndGetToken() async {
    final billCoreFm = FirebaseMessaging.instance;
    await billCoreFm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _billCorePushToken = await billCoreFm.getToken();
  }

  // --------------------------------------------------------------------------
  // Привязка канала: тап по уведомлению из native
  // --------------------------------------------------------------------------
  void _billCoreBindPlatformNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall billCoreCall) async {
      if (billCoreCall.method == "onNotificationTap") {
        final Map<String, dynamic> billCorePayload =
        Map<String, dynamic>.from(billCoreCall.arguments);
        debugPrint("URI from platform tap: ${billCorePayload['uri']}");
        final billCoreUriString = billCorePayload["uri"]?.toString();
        if (billCoreUriString != null &&
            !billCoreUriString.contains("Нет URI")) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (billCoreContext) =>
                  BillCoreTableView(billCoreUriString),
            ),
                (billCoreRoute) => false,
          );
        }
      }
    });
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------
  @override
  Widget build(BuildContext billCoreContext) {
    _billCoreBindPlatformNotificationTap();

    final billCoreIsDark =
        MediaQuery.of(billCoreContext).platformBrightness ==
            Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: billCoreIsDark
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            InAppWebView(
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                disableDefaultErrorPage: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                allowsPictureInPictureMediaPlayback: true,
                useOnDownloadStart: true,
                javaScriptCanOpenWindowsAutomatically: true,
                useShouldOverrideUrlLoading: true,
                supportMultipleWindows: true,
              ),
              initialUrlRequest: URLRequest(
                url: WebUri(_billCoreCurrentLane),
              ),
              onWebViewCreated:
                  (InAppWebViewController billCoreController) {
                _billCoreWebController = billCoreController;

                _billCoreWebController.addJavaScriptHandler(
                  handlerName: 'onServerResponse',
                  callback: (billCoreArgs) {
                    _billCoreVault.billCoreLogger
                        .billCoreLogInfo("JS Args: $billCoreArgs");
                    try {
                      return billCoreArgs.reduce(
                              (billCoreV, billCoreE) => billCoreV + billCoreE);
                    } catch (_) {
                      return billCoreArgs.toString();
                    }
                  },
                );
              },
              onLoadStart:
                  (InAppWebViewController billCoreController,
                  Uri? billCoreUri) async {
                _billCoreStartLoadTs =
                    DateTime.now().millisecondsSinceEpoch;

                if (billCoreUri != null) {
                  if (BillCoreKit.billCoreLooksLikeBareMail(billCoreUri)) {
                    try {
                      await billCoreController.stopLoading();
                    } catch (_) {}
                    final billCoreMailto =
                    BillCoreKit.billCoreToMailto(billCoreUri);
                    await BillCoreLinker.billCoreOpen(
                      BillCoreKit.billCoreGmailize(billCoreMailto),
                    );
                    return;
                  }

                  final billCoreScheme =
                  billCoreUri.scheme.toLowerCase();
                  if (billCoreScheme != 'http' &&
                      billCoreScheme != 'https') {
                    try {
                      await billCoreController.stopLoading();
                    } catch (_) {}
                  }
                }
              },
              onLoadStop:
                  (InAppWebViewController billCoreController,
                  Uri? billCoreUri) async {
                await billCoreController.evaluateJavascript(
                  source:
                  "console.log('Hello from Roulette JS!');",
                );

                setState(() {
                  _billCoreCurrentLane =
                      billCoreUri?.toString() ?? _billCoreCurrentLane;
                });

                Future.delayed(const Duration(seconds: 20), () {
                  _billCoreSendLoadedOnce();
                });
              },
              shouldOverrideUrlLoading:
                  (InAppWebViewController billCoreController,
                  NavigationAction billCoreNav) async {
                final billCoreUri = billCoreNav.request.url;
                if (billCoreUri == null) {
                  return NavigationActionPolicy.ALLOW;
                }

                if (BillCoreKit.billCoreLooksLikeBareMail(billCoreUri)) {
                  final billCoreMailto =
                  BillCoreKit.billCoreToMailto(billCoreUri);
                  await BillCoreLinker.billCoreOpen(
                    BillCoreKit.billCoreGmailize(billCoreMailto),
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                final billCoreScheme =
                billCoreUri.scheme.toLowerCase();

                if (billCoreScheme == 'mailto') {
                  await BillCoreLinker.billCoreOpen(
                    BillCoreKit.billCoreGmailize(billCoreUri),
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                if (billCoreScheme == 'tel') {
                  await launchUrl(
                    billCoreUri,
                    mode: LaunchMode.externalApplication,
                  );
                  return NavigationActionPolicy.CANCEL;
                }

                final billCoreHost =
                billCoreUri.host.toLowerCase();
                final bool billCoreIsSocial =
                    billCoreHost.endsWith('facebook.com') ||
                        billCoreHost.endsWith('instagram.com') ||
                        billCoreHost.endsWith('twitter.com') ||
                        billCoreHost.endsWith('x.com');

                if (billCoreIsSocial) {
                  await BillCoreLinker.billCoreOpen(billCoreUri);
                  return NavigationActionPolicy.CANCEL;
                }

                if (_billCoreIsExternalTable(billCoreUri)) {
                  final billCoreMapped =
                  _billCoreMapExternalToHttp(billCoreUri);
                  await BillCoreLinker.billCoreOpen(billCoreMapped);
                  return NavigationActionPolicy.CANCEL;
                }

                if (billCoreScheme != 'http' &&
                    billCoreScheme != 'https') {
                  return NavigationActionPolicy.CANCEL;
                }

                return NavigationActionPolicy.ALLOW;
              },
              onCreateWindow:
                  (InAppWebViewController billCoreController,
                  CreateWindowAction billCoreReq) async {
                final billCoreUrl = billCoreReq.request.url;
                if (billCoreUrl == null) return false;

                if (BillCoreKit.billCoreLooksLikeBareMail(billCoreUrl)) {
                  final billCoreMail =
                  BillCoreKit.billCoreToMailto(billCoreUrl);
                  await BillCoreLinker.billCoreOpen(
                    BillCoreKit.billCoreGmailize(billCoreMail),
                  );
                  return false;
                }

                final billCoreScheme =
                billCoreUrl.scheme.toLowerCase();

                if (billCoreScheme == 'mailto') {
                  await BillCoreLinker.billCoreOpen(
                    BillCoreKit.billCoreGmailize(billCoreUrl),
                  );
                  return false;
                }

                if (billCoreScheme == 'tel') {
                  await launchUrl(
                    billCoreUrl,
                    mode: LaunchMode.externalApplication,
                  );
                  return false;
                }

                final billCoreHost =
                billCoreUrl.host.toLowerCase();
                final bool billCoreIsSocial =
                    billCoreHost.endsWith('facebook.com') ||
                        billCoreHost.endsWith('instagram.com') ||
                        billCoreHost.endsWith('twitter.com') ||
                        billCoreHost.endsWith('x.com');

                if (billCoreIsSocial) {
                  await BillCoreLinker.billCoreOpen(billCoreUrl);
                  return false;
                }

                if (_billCoreIsExternalTable(billCoreUrl)) {
                  final billCoreMapped =
                  _billCoreMapExternalToHttp(billCoreUrl);
                  await BillCoreLinker.billCoreOpen(billCoreMapped);
                  return false;
                }

                if (billCoreScheme == 'http' || billCoreScheme == 'https') {
                  billCoreController.loadUrl(
                    urlRequest: URLRequest(url: billCoreUrl),
                  );
                }

                return false;
              },
            ),

            if (_billCoreOverlayBusy)
              Positioned.fill(
                child: Container(
                  color: Colors.black87,
                  child: const Center(
                    child: BillCoreXoLoader(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ========================================================================
  // BILL утилиты маршрутов (протоколы/внешние “столы”)
  // ========================================================================
  bool _billCoreIsExternalTable(Uri billCoreUri) {
    final billCoreScheme = billCoreUri.scheme.toLowerCase();
    if (_billCoreExternalSchemes.contains(billCoreScheme)) {
      return true;
    }

    if (billCoreScheme == 'http' || billCoreScheme == 'https') {
      final billCoreHost = billCoreUri.host.toLowerCase();
      if (_billCoreExternalHosts.contains(billCoreHost)) {
        return true;
      }
      if (billCoreHost.endsWith('t.me')) return true;
      if (billCoreHost.endsWith('wa.me')) return true;
      if (billCoreHost.endsWith('m.me')) return true;
      if (billCoreHost.endsWith('signal.me')) return true;
      if (billCoreHost.endsWith('facebook.com')) return true;
      if (billCoreHost.endsWith('instagram.com')) return true;
      if (billCoreHost.endsWith('twitter.com')) return true;
      if (billCoreHost.endsWith('x.com')) return true;
    }

    return false;
  }

  Uri _billCoreMapExternalToHttp(Uri billCoreUri) {
    final billCoreScheme = billCoreUri.scheme.toLowerCase();

    if (billCoreScheme == 'tg' || billCoreScheme == 'telegram') {
      final billCoreQp = billCoreUri.queryParameters;
      final billCoreDomain = billCoreQp['domain'];
      if (billCoreDomain != null && billCoreDomain.isNotEmpty) {
        return Uri.https('t.me', '/$billCoreDomain', {
          if (billCoreQp['start'] != null) 'start': billCoreQp['start']!,
        });
      }
      final billCorePath =
      billCoreUri.path.isNotEmpty ? billCoreUri.path : '';
      return Uri.https(
        't.me',
        '/$billCorePath',
        billCoreUri.queryParameters.isEmpty
            ? null
            : billCoreUri.queryParameters,
      );
    }

    if (billCoreScheme == 'whatsapp') {
      final billCoreQp = billCoreUri.queryParameters;
      final billCorePhone = billCoreQp['phone'];
      final billCoreText = billCoreQp['text'];
      if (billCorePhone != null && billCorePhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${BillCoreKit.billCoreOnlyDigits(billCorePhone)}',
          {
            if (billCoreText != null && billCoreText.isNotEmpty)
              'text': billCoreText,
          },
        );
      }
      return Uri.https(
        'wa.me',
        '/',
        {
          if (billCoreText != null && billCoreText.isNotEmpty)
            'text': billCoreText,
        },
      );
    }

    if (billCoreScheme == 'bnl') {
      final billCoreNewPath =
      billCoreUri.path.isNotEmpty ? billCoreUri.path : '';
      return Uri.https(
        'bnl.com',
        '/$billCoreNewPath',
        billCoreUri.queryParameters.isEmpty
            ? null
            : billCoreUri.queryParameters,
      );
    }

    return billCoreUri;
  }

  Future<void> _billCoreSendLoadedOnce() async {
    if (_billCoreLoadedOnceSent) {
      debugPrint('Wheel Loaded already sent, skip');
      return;
    }

    final billCoreNow = DateTime.now().millisecondsSinceEpoch;

    await billCorePostStat(
      billCoreEvent: 'Loaded',
      billCoreTimeStart: _billCoreStartLoadTs,
      billCoreTimeFinish: billCoreNow,
      billCoreUrl: _billCoreCurrentLane,
      billCoreAppSid: _billCoreSpy.billCoreAfUid,
      billCoreFirstPageTs: _billCoreFirstPageTs,
    );

    _billCoreLoadedOnceSent = true;
  }
}

// ============================================================================
// Пример main, если нужно интегрировать:
// ============================================================================

