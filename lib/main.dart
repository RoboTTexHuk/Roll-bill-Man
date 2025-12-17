import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, HttpHeaders, HttpClient, HttpClientRequest, HttpClientResponse;
import 'dart:math' as billMath;
import 'dart:math';
import 'dart:ui';
import 'package:appsflyer_sdk/appsflyer_sdk.dart' as afCore;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodChannel, SystemChrome, SystemUiOverlayStyle, MethodCall;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;


import 'package:package_info_plus/package_info_plus.dart';
import 'package:rollbill/puScript.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timezone/data/latest.dart' as tzData;
import 'package:timezone/timezone.dart' as tzZone;

// ============================================================================
// Константы
// ============================================================================

const String billLoadedOnceKey = 'loaded_once';
const String billStatEndpoint = 'https://api.saleclearens.store/stat';
const String billCachedFcmKey = 'cached_fcm';

// ============================================================================
// Лёгкие сервисы
// ============================================================================

class BillBarrel {
  static final BillBarrel billInstance = BillBarrel._internal();

  BillBarrel._internal();

  factory BillBarrel() => billInstance;

  final Connectivity billConnectivity = Connectivity();

  void billLogInfo(Object billMessage) => debugPrint('[I] $billMessage');
  void billLogWarn(Object billMessage) => debugPrint('[W] $billMessage');
  void billLogError(Object billMessage) => debugPrint('[E] $billMessage');
}

// ============================================================================
// Сеть/данные
// ============================================================================

class BillWire {
  final BillBarrel _billBarrel = BillBarrel();

  Future<bool> isBillOnline() async {
    final ConnectivityResult billConnectivityResult =
    await _billBarrel.billConnectivity.checkConnectivity();
    return billConnectivityResult != ConnectivityResult.none;
  }

  Future<void> postBillJson(
      String billUrl,
      Map<String, dynamic> billData,
      ) async {
    try {
      await http.post(
        Uri.parse(billUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(billData),
      );
    } catch (billError) {
      _billBarrel.billLogError('postGlowJson error: $billError');
    }
  }
}

// ============================================================================
// Досье устройства
// ============================================================================

class BillDeviceDeck {
  String? billDeviceId;
  String? billSessionId = 'roulette-one-off';
  String? billPlatformName; // android/ios
  String? billOsVersion;
  String? billAppVersion;
  String? billLang;
  String? billTimezoneName;
  bool billPushEnabled = true;

  Future<void> initBillDeviceDeck() async {
    final DeviceInfoPlugin billDeviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final AndroidDeviceInfo billAndroidInfo =
      await billDeviceInfoPlugin.androidInfo;
      billDeviceId = billAndroidInfo.id;
      billPlatformName = 'android';
      billOsVersion = billAndroidInfo.version.release;
    } else if (Platform.isIOS) {
      final IosDeviceInfo billIosInfo = await billDeviceInfoPlugin.iosInfo;
      billDeviceId = billIosInfo.identifierForVendor;
      billPlatformName = 'ios';
      billOsVersion = billIosInfo.systemVersion;
    }

    final PackageInfo billPackageInfo = await PackageInfo.fromPlatform();
    billAppVersion = billPackageInfo.version;
    billLang = Platform.localeName.split('_').first;
    billTimezoneName = tzZone.local.name;
    billSessionId = 'roulette-${DateTime.now().millisecondsSinceEpoch}';
  }

  Map<String, dynamic> asBillMap({String? billFcm}) => {
    'fcm_token': billFcm ?? 'missing_token',
    'device_id': billDeviceId ?? 'missing_id',
    'app_name': 'rollbillman',
    'instance_id': billSessionId ?? 'missing_session',
    'platform': billPlatformName ?? 'missing_system',
    'os_version': billOsVersion ?? 'missing_build',
    'app_version': billAppVersion ?? 'missing_app',
    'language': billLang ?? 'en',
    'timezone': billTimezoneName ?? 'UTC',
    'push_enabled': billPushEnabled,
  };
}

// ============================================================================
// AppsFlyer
// ============================================================================

class BillSpy {
  afCore.AppsFlyerOptions? billOptions;
  afCore.AppsflyerSdk? billSdk;

  String billAfUid = '';
  String billAfData = '';

  void startBillSpy({VoidCallback? onBillUpdate}) {
    final afCore.AppsFlyerOptions billConfig = afCore.AppsFlyerOptions(
      afDevKey: 'qsBLmy7dAXDQhowM8V3ca4',
      appId: '6756072063',
      showDebug: true,
      timeToWaitForATTUserAuthorization: 0,
    );

    billOptions = billConfig;
    billSdk = afCore.AppsflyerSdk(billConfig);

    billSdk?.initSdk(
      registerConversionDataCallback: true,
      registerOnAppOpenAttributionCallback: true,
      registerOnDeepLinkingCallback: true,
    );

    billSdk?.startSDK(
      onSuccess: () => BillBarrel().billLogInfo('NeonCinemaSpy started'),
      onError: (billCode, billMsg) =>
          BillBarrel().billLogError('NeonCinemaSpy error $billCode: $billMsg'),
    );

    billSdk?.onInstallConversionData((billValue) {
      billAfData = billValue.toString();
      onBillUpdate?.call();
    });

    billSdk?.getAppsFlyerUID().then((billValue) {
      billAfUid = billValue.toString();
      onBillUpdate?.call();
    });
  }
}

// ============================================================================
// Новый loader: XO золотые буквы
// ============================================================================

class BillXOLoader extends StatefulWidget {
  const BillXOLoader({Key? key}) : super(key: key);

  @override
  State<BillXOLoader> createState() => _BillXOLoaderState();
}

class _BillXOLoaderState extends State<BillXOLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController billAnimationController;
  late Animation<double> billXOProgressAnimation;

  @override
  void initState() {
    super.initState();
    billAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    billXOProgressAnimation =
        CurvedAnimation(parent: billAnimationController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    billAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Size billSize = MediaQuery.of(context).size;
    final double billFontSize = billSize.width * 0.2;

    const Color billDarkGold = Color(0xFF1E1308);
    const Color billGold1 = Color(0xFFFFE082);
    const Color billGold2 = Color(0xFFFFC107);
    const Color billGold3 = Color(0xFFFFA000);

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedBuilder(
        animation: billXOProgressAnimation,
        builder: (BuildContext context, Widget? child) {
          final double billT = billXOProgressAnimation.value;
          final double billXOOpacity = 0.6 + 0.4 * sin(billT * 2 * billMath.pi);
          final double billGlowScale = 1.0 + 0.05 * sin(billT * 2 * billMath.pi);

          return Center(
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // Тёмно-золотой мягкий фон
                Container(
                  width: billSize.width * 0.6,
                  height: billFontSize * 2.0,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Colors.black,
                        billDarkGold,
                        Colors.black,
                      ],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: billGold3.withOpacity(0.35),
                        blurRadius: 28,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),

                Transform.scale(
                  scale: billGlowScale,
                  child: ShaderMask(
                    shaderCallback: (Rect rect) {
                      return const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          billGold1,
                          billGold2,
                          billGold3,
                        ],
                      ).createShader(rect);
                    },
                    blendMode: BlendMode.srcATop,
                    child: Opacity(
                      opacity: billXOOpacity,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          _BillLetter(
                            billLetter: 'X',
                            billFontSize: billFontSize,
                            billPhase: 0.0,
                            billProgress: billT,
                          ),
                          const SizedBox(width: 12),
                          _BillLetter(
                            billLetter: 'O',
                            billFontSize: billFontSize,
                            billPhase: 0.5,
                            billProgress: billT,
                          ),
                        ],
                      ),
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

class _BillLetter extends StatelessWidget {
  const _BillLetter({
    required this.billLetter,
    required this.billFontSize,
    required this.billPhase,
    required this.billProgress,
  });

  final String billLetter;
  final double billFontSize;
  final double billPhase;
  final double billProgress;

  @override
  Widget build(BuildContext context) {
    final double billLocalT =
        (billProgress + billPhase) % 1.0; // немного сдвигаем фазу
    final double billScale = 0.9 + 0.1 * sin(billLocalT * 2 * billMath.pi);
    final double billBlur =
        2 + 6 * (0.5 + 0.5 * sin(billLocalT * 2 * billMath.pi));

    return Transform.scale(
      scale: billScale,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: billBlur, sigmaY: billBlur),
          child: Text(
            billLetter,
            style: TextStyle(
              fontSize: billFontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 4,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// FCM фоновые крики
// ============================================================================

@pragma('vm:entry-point')
Future<void> billFcmBackgroundHandler(RemoteMessage billMessage) async {
  BillBarrel().billLogInfo('bg-fcm: ${billMessage.messageId}');
  BillBarrel().billLogInfo('bg-data: ${billMessage.data}');
}

// ============================================================================
// FCM Bridge
// ============================================================================

class BillFcmBridge {
  final BillBarrel _billBarrel = BillBarrel();
  String? _billToken;
  final List<void Function(String)> _billWaiters = <void Function(String)>[];

  String? get billToken => _billToken;

  BillFcmBridge() {
    const MethodChannel('com.example.fcm/token')
        .setMethodCallHandler((MethodCall billCall) async {
      if (billCall.method == 'setToken') {
        final String billTokenString = billCall.arguments as String;
        if (billTokenString.isNotEmpty) {
          _setBillToken(billTokenString);
        }
      }
    });

    _restoreBillToken();
  }

  Future<void> _restoreBillToken() async {
    try {
      final SharedPreferences billPrefs =
      await SharedPreferences.getInstance();
      final String? billCachedToken = billPrefs.getString(billCachedFcmKey);
      if (billCachedToken != null && billCachedToken.isNotEmpty) {
        _setBillToken(billCachedToken, notify: false);
      }
    } catch (_) {}
  }

  Future<void> _persistBillToken(String billNewToken) async {
    try {
      final SharedPreferences billPrefs =
      await SharedPreferences.getInstance();
      await billPrefs.setString(billCachedFcmKey, billNewToken);
    } catch (_) {}
  }

  void _setBillToken(String billNewToken, {bool notify = true}) {
    _billToken = billNewToken;
    _persistBillToken(billNewToken);
    if (notify) {
      for (final void Function(String) billCallback
      in List<void Function(String)>.from(_billWaiters)) {
        try {
          billCallback(billNewToken);
        } catch (billError) {
          _billBarrel.billLogWarn('fcm waiter error: $billError');
        }
      }
      _billWaiters.clear();
    }
  }

  Future<void> waitBillToken(
      Function(String billToken) onBillToken) async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if ((_billToken ?? '').isNotEmpty) {
        onBillToken(_billToken!);
        return;
      }

      _billWaiters.add(onBillToken);
    } catch (billError) {
      _billBarrel.billLogError('waitGlowToken error: $billError');
    }
  }
}

// ============================================================================
// Splash / Hall
// ============================================================================

class BillHall extends StatefulWidget {
  const BillHall({Key? key}) : super(key: key);

  @override
  State<BillHall> createState() => _BillHallState();
}

class _BillHallState extends State<BillHall> {
  final BillFcmBridge billFcmBridge = BillFcmBridge();
  bool billNavigatedOnce = false;
  Timer? billFallbackTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.black,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ));

    billFcmBridge.waitBillToken((String billTokenValue) {
      _goBillHarbor(billTokenValue);
    });

    billFallbackTimer =
        Timer(const Duration(seconds: 8), () => _goBillHarbor(''));
  }

  void _goBillHarbor(String billSignal) {
    if (billNavigatedOnce) return;
    billNavigatedOnce = true;
    billFallbackTimer?.cancel();

    Navigator.pushReplacement(
      context,
      MaterialPageRoute<Widget>(
        builder: (BuildContext billContext) =>
            BillHarbor(billSignal: billSignal),
      ),
    );
  }

  @override
  void dispose() {
    billFallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: BillXOLoader(),
      ),
    );
  }
}

// ============================================================================
// ViewModel + Courier
// ============================================================================

class BillBosun {
  final BillDeviceDeck billDeviceDeck;
  final BillSpy billSpy;

  BillBosun({
    required this.billDeviceDeck,
    required this.billSpy,
  });

  Map<String, dynamic> billDeviceMap(String? billToken) =>
      billDeviceDeck.asBillMap(billFcm: billToken);

  Map<String, dynamic> billAfMap(String? billToken) => {
    'content': {
      'af_data': billSpy.billAfData,
      'af_id': billSpy.billAfUid,
      'fb_app_name': 'rollbillman',
      'app_name': 'rollbillman',
      'deep': null,
      'bundle_identifier': 'com.bill.rollbill.rollbill',
      'app_version': '1.0.0',
      'apple_id': '6756072063',
      'fcm_token': billToken ?? 'no_token',
      'device_id': billDeviceDeck.billDeviceId ?? 'no_device',
      'instance_id': billDeviceDeck.billSessionId ?? 'no_instance',
      'platform': billDeviceDeck.billPlatformName ?? 'no_type',
      'os_version': billDeviceDeck.billOsVersion ?? 'no_os',
      'app_version': billDeviceDeck.billAppVersion ?? 'no_app',
      'language': billDeviceDeck.billLang ?? 'en',
      'timezone': billDeviceDeck.billTimezoneName ?? 'UTC',
      'push_enabled': billDeviceDeck.billPushEnabled,
      'useruid': billSpy.billAfUid,
    },
  };
}

class BillCourier {
  final BillBosun billBosun;
  final InAppWebViewController Function() getBillWebView;

  BillCourier({
    required this.billBosun,
    required this.getBillWebView,
  });

  Future<void> putBillDeviceToLocalStorage(String? billToken) async {
    final Map<String, dynamic> billMap = billBosun.billDeviceMap(billToken);
    await getBillWebView().evaluateJavascript(
      source: '''
localStorage.setItem('app_data', JSON.stringify(${jsonEncode(billMap)}));
''',
    );
  }

  Future<void> sendBillRawToPage(String? billToken) async {
    final Map<String, dynamic> billPayload = billBosun.billAfMap(billToken);
    final String billJsonString = jsonEncode(billPayload);

    print('load stry$billJsonString');
    BillBarrel().billLogInfo('SendGlowRawData: $billJsonString');

    await getBillWebView().evaluateJavascript(
      source: 'sendRawData(${jsonEncode(billJsonString)});',
    );
  }
}

// ============================================================================
// Переходы/статистика
// ============================================================================

Future<String> billFinalUrl(
    String billStartUrl, {
      int billMaxHops = 10,
    }) async {
  final HttpClient billHttpClient = HttpClient();

  try {
    Uri billCurrentUri = Uri.parse(billStartUrl);

    for (int billIndex = 0; billIndex < billMaxHops; billIndex++) {
      final HttpClientRequest billRequest =
      await billHttpClient.getUrl(billCurrentUri);
      billRequest.followRedirects = false;
      final HttpClientResponse billResponse = await billRequest.close();

      if (billResponse.isRedirect) {
        final String? billLocationHeader =
        billResponse.headers.value(HttpHeaders.locationHeader);
        if (billLocationHeader == null || billLocationHeader.isEmpty) {
          break;
        }

        final Uri billNextUri = Uri.parse(billLocationHeader);
        billCurrentUri = billNextUri.hasScheme
            ? billNextUri
            : billCurrentUri.resolveUri(billNextUri);
        continue;
      }

      return billCurrentUri.toString();
    }

    return billCurrentUri.toString();
  } catch (billError) {
    debugPrint('neonCinemaFinalUrl error: $billError');
    return billStartUrl;
  } finally {
    billHttpClient.close(force: true);
  }
}

Future<void> billPostStat({
  required String billEvent,
  required int billTimeStart,
  required String billUrl,
  required int billTimeFinish,
  required String billAppSid,
  int? billFirstPageLoadTs,
}) async {
  try {
    final String billResolvedUrl = await billFinalUrl(billUrl);

    final Map<String, dynamic> billPayload = <String, dynamic>{
      'event': billEvent,
      'timestart': billTimeStart,
      'timefinsh': billTimeFinish,
      'url': billResolvedUrl,
      'appleID': '6756072063',
      'open_count': '$billAppSid/$billTimeStart',
    };

    debugPrint('neonCinemaStat $billPayload');

    final http.Response billResponse = await http.post(
      Uri.parse('$billStatEndpoint/$billAppSid'),
      headers: <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(billPayload),
    );

    debugPrint(
        'neonCinemaStat resp=${billResponse.statusCode} body=${billResponse.body}');
  } catch (billError) {
    debugPrint('neonCinemaPostStat error: $billError');
  }
}

// ============================================================================
// Главный WebView — Harbor
// ============================================================================

class BillHarbor extends StatefulWidget {
  final String? billSignal;

  const BillHarbor({super.key, required this.billSignal});

  @override
  State<BillHarbor> createState() => _BillHarborState();
}

class _BillHarborState extends State<BillHarbor> with WidgetsBindingObserver {
  late InAppWebViewController billWebViewController;
  final String billHomeUrl = 'https://api.saleclearens.store/';

  int billHatchCounter = 0;
  DateTime? billSleepAt;
  bool billVeilVisible = false;
  double billWarmProgress = 0.0;
  late Timer billWarmTimer;
  final int billWarmSeconds = 6;
  bool billCoverVisible = true;

  bool billLoadedOnceSent = false;
  int? billFirstPageTimestamp;

  BillCourier? billCourier;
  BillBosun? billBosun;

  String billCurrentUrl = '';
  int billStartLoadTimestamp = 0;

  final BillDeviceDeck billDeviceDeck = BillDeviceDeck();
  final BillSpy billSpy = BillSpy();
  bool billUseSafeArea = false;
  final Set<String> billSchemes = <String>{
    'tg',
    'telegram',
    'whatsapp',
    'viber',
    'skype',
    'fb-messenger',
    'sgnl',
    'tel',
    'mailto',
    'bnl',
  };

  final Set<String> billExternalHosts = <String>{
    't.me',
    'telegram.me',
    'telegram.dog',
    'wa.me',
    'api.whatsapp.com',
    'chat.whatsapp.com',
    'm.me',
    'signal.me',
    'bnl.com',
    'www.bnl.com',
    // Новые соцсети
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    billFirstPageTimestamp = DateTime.now().millisecondsSinceEpoch;

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          billCoverVisible = false;
        });
      }
    });

    Future<void>.delayed(const Duration(seconds: 7), () {
      if (!mounted) return;
      setState(() {
        billVeilVisible = true;
      });
    });

    _bootBill();
  }

  Future<void> _loadBillLoadedFlag() async {
    final SharedPreferences billPrefs =
    await SharedPreferences.getInstance();
    billLoadedOnceSent = billPrefs.getBool(billLoadedOnceKey) ?? false;
  }

  Future<void> _saveBillLoadedFlag() async {
    final SharedPreferences billPrefs =
    await SharedPreferences.getInstance();
    await billPrefs.setBool(billLoadedOnceKey, true);
    billLoadedOnceSent = true;
  }

  Future<void> sendBillLoadedOnce({
    required String billUrl,
    required int billTimestart,
  }) async {
    if (billLoadedOnceSent) {
      debugPrint('Loaded already sent, skip');
      return;
    }

    final int billNow = DateTime.now().millisecondsSinceEpoch;

    await billPostStat(
      billEvent: 'Loaded',
      billTimeStart: billTimestart,
      billTimeFinish: billNow,
      billUrl: billUrl,
      billAppSid: billSpy.billAfUid,
      billFirstPageLoadTs: billFirstPageTimestamp,
    );

    await _saveBillLoadedFlag();
  }

  void _bootBill() {
    _startBillWarmProgress();
    _wireBillFcm();
    billSpy.startBillSpy(
      onBillUpdate: () => setState(() {}),
    );
    _bindBillNotificationTap();
    _prepareBillDeck();

    Future<void>.delayed(const Duration(seconds: 6), () async {
      await _pushBillDevice();
      await _pushBillAfData();
    });
  }

  void _wireBillFcm() {
    FirebaseMessaging.onMessage.listen((RemoteMessage billMessage) {
      final dynamic billLink = billMessage.data['uri'];
      if (billLink != null) {
        _navigateBill(billLink.toString());
      } else {
        _resetBillHome();
      }
    });

    FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage billMessage) {
      final dynamic billLink = billMessage.data['uri'];
      if (billLink != null) {
        _navigateBill(billLink.toString());
      } else {
        _resetBillHome();
      }
    });
  }

  void _bindBillNotificationTap() {
    MethodChannel('com.example.fcm/notification')
        .setMethodCallHandler((MethodCall billCall) async {
      if (billCall.method == 'onNotificationTap') {
        final Map<String, dynamic> billPayload =
        Map<String, dynamic>.from(billCall.arguments);
        if (billPayload['uri'] != null &&
            !billPayload['uri'].toString().contains('Нет URI')) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<Widget>(
              builder: (BuildContext billContext) =>
                  BillCoreTableView (billPayload['uri'].toString()),
            ),
                (Route<dynamic> billRoute) => false,
          );
        }
      }
    });
  }

  Future<void> _prepareBillDeck() async {
    try {
      await billDeviceDeck.initBillDeviceDeck();
      await _askBillPushPermissions();

      billBosun = BillBosun(
        billDeviceDeck: billDeviceDeck,
        billSpy: billSpy,
      );

      billCourier = BillCourier(
        billBosun: billBosun!,
        getBillWebView: () => billWebViewController,
      );

      await _loadBillLoadedFlag();
    } catch (billError) {
      BillBarrel().billLogError('prepare fail: $billError');
    }
  }

  Future<void> _askBillPushPermissions() async {
    final FirebaseMessaging billMessaging = FirebaseMessaging.instance;
    await billMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  void _navigateBill(String billLink) async {
    try {
      await billWebViewController.loadUrl(
        urlRequest: URLRequest(url: WebUri(billLink)),
      );
    } catch (billError) {
      BillBarrel().billLogError('navigate error: $billError');
    }
  }

  void _resetBillHome() {
    Future<void>.delayed(const Duration(seconds: 3), () {
      try {
        billWebViewController.loadUrl(
          urlRequest: URLRequest(url: WebUri(billHomeUrl)),
        );
      } catch (_) {}
    });
  }

  Future<void> _pushBillDevice() async {
    BillBarrel().billLogInfo('TOKEN ship ${widget.billSignal}');
    try {
      await billCourier?.putBillDeviceToLocalStorage(widget.billSignal);
    } catch (billError) {
      BillBarrel().billLogError('pushGlowDevice error: $billError');
    }
  }

  Future<void> _pushBillAfData() async {
    try {
      await billCourier?.sendBillRawToPage(widget.billSignal);
    } catch (billError) {
      BillBarrel().billLogError('pushGlowAf error: $billError');
    }
  }

  void _startBillWarmProgress() {
    int billTick = 0;
    billWarmProgress = 0.0;

    billWarmTimer =
        Timer.periodic(const Duration(milliseconds: 100), (Timer billTimer) {
          if (!mounted) return;

          setState(() {
            billTick++;
            billWarmProgress = billTick / (billWarmSeconds * 10);

            if (billWarmProgress >= 1.0) {
              billWarmProgress = 1.0;
              billWarmTimer.cancel();
            }
          });
        });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState billState) {
    if (billState == AppLifecycleState.paused) {
      billSleepAt = DateTime.now();
    }

    if (billState == AppLifecycleState.resumed) {
      if (Platform.isIOS && billSleepAt != null) {
        final DateTime billNow = DateTime.now();
        final Duration billDrift = billNow.difference(billSleepAt!);

        if (billDrift > const Duration(minutes: 25)) {
          reboardBill();
        }
      }
      billSleepAt = null;
    }
  }

  void reboardBill() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<Widget>(
          builder: (BuildContext billContext) =>
              BillHarbor(billSignal: widget.billSignal),
        ),
            (Route<dynamic> billRoute) => false,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    billWarmTimer.cancel();
    super.dispose();
  }

  // ================== URL helpers ==================

  bool _isBillBareEmail(Uri billUri) {
    final String billScheme = billUri.scheme;
    if (billScheme.isNotEmpty) return false;
    final String billRaw = billUri.toString();
    return billRaw.contains('@') && !billRaw.contains(' ');
  }

  Uri _toBillMailto(Uri billUri) {
    final String billFull = billUri.toString();
    final List<String> billParts = billFull.split('?');
    final String billEmail = billParts.first;
    final Map<String, String> billQueryParams = billParts.length > 1
        ? Uri.splitQueryString(billParts[1])
        : <String, String>{};

    return Uri(
      scheme: 'mailto',
      path: billEmail,
      queryParameters:
      billQueryParams.isEmpty ? null : billQueryParams,
    );
  }

  bool _isBillPlatformish(Uri billUri) {
    final String billScheme = billUri.scheme.toLowerCase();
    if (billSchemes.contains(billScheme)) {
      return true;
    }

    if (billScheme == 'http' || billScheme == 'https') {
      final String billHost = billUri.host.toLowerCase();

      if (billExternalHosts.contains(billHost)) {
        return true;
      }

      if (billHost.endsWith('t.me')) return true;
      if (billHost.endsWith('wa.me')) return true;
      if (billHost.endsWith('m.me')) return true;
      if (billHost.endsWith('signal.me')) return true;
      if (billHost.endsWith('facebook.com')) return true;
      if (billHost.endsWith('instagram.com')) return true;
      if (billHost.endsWith('twitter.com')) return true;
      if (billHost.endsWith('x.com')) return true;
    }

    return false;
  }

  String _billDigitsOnly(String billSource) =>
      billSource.replaceAll(RegExp(r'[^0-9+]'), '');

  Uri _billHttpize(Uri billUri) {
    final String billScheme = billUri.scheme.toLowerCase();

    if (billScheme == 'tg' || billScheme == 'telegram') {
      final Map<String, String> billQp = billUri.queryParameters;
      final String? billDomain = billQp['domain'];

      if (billDomain != null && billDomain.isNotEmpty) {
        return Uri.https(
          't.me',
          '/$billDomain',
          <String, String>{
            if (billQp['start'] != null) 'start': billQp['start']!,
          },
        );
      }

      final String billPath =
      billUri.path.isNotEmpty ? billUri.path : '';

      return Uri.https(
        't.me',
        '/$billPath',
        billUri.queryParameters.isEmpty
            ? null
            : billUri.queryParameters,
      );
    }

    if ((billScheme == 'http' || billScheme == 'https') &&
        billUri.host.toLowerCase().endsWith('t.me')) {
      return billUri;
    }

    if (billScheme == 'viber') {
      return billUri;
    }

    if (billScheme == 'whatsapp') {
      final Map<String, String> billQp = billUri.queryParameters;
      final String? billPhone = billQp['phone'];
      final String? billText = billQp['text'];

      if (billPhone != null && billPhone.isNotEmpty) {
        return Uri.https(
          'wa.me',
          '/${_billDigitsOnly(billPhone)}',
          <String, String>{
            if (billText != null && billText.isNotEmpty)
              'text': billText,
          },
        );
      }

      return Uri.https(
        'wa.me',
        '/',
        <String, String>{
          if (billText != null && billText.isNotEmpty)
            'text': billText,
        },
      );
    }

    if ((billScheme == 'http' || billScheme == 'https') &&
        (billUri.host.toLowerCase().endsWith('wa.me') ||
            billUri.host.toLowerCase().endsWith('whatsapp.com'))) {
      return billUri;
    }

    if (billScheme == 'skype') {
      return billUri;
    }

    if (billScheme == 'fb-messenger') {
      final String billPath = billUri.pathSegments.isNotEmpty
          ? billUri.pathSegments.join('/')
          : '';
      final Map<String, String> billQp = billUri.queryParameters;

      final String billId =
          billQp['id'] ?? billQp['user'] ?? billPath;

      if (billId.isNotEmpty) {
        return Uri.https(
          'm.me',
          '/$billId',
          billUri.queryParameters.isEmpty
              ? null
              : billUri.queryParameters,
        );
      }

      return Uri.https(
        'm.me',
        '/',
        billUri.queryParameters.isEmpty
            ? null
            : billUri.queryParameters,
      );
    }

    if (billScheme == 'sgnl') {
      final Map<String, String> billQp = billUri.queryParameters;
      final String? billPhone = billQp['phone'];
      final String? billUsername = billQp['username'];

      if (billPhone != null && billPhone.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#p/${_billDigitsOnly(billPhone)}',
        );
      }

      if (billUsername != null && billUsername.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/#u/$billUsername',
        );
      }

      final String billPath = billUri.pathSegments.join('/');
      if (billPath.isNotEmpty) {
        return Uri.https(
          'signal.me',
          '/$billPath',
          billUri.queryParameters.isEmpty
              ? null
              : billUri.queryParameters,
        );
      }

      return billUri;
    }

    if (billScheme == 'tel') {
      return Uri.parse('tel:${_billDigitsOnly(billUri.path)}');
    }

    if (billScheme == 'mailto') {
      return billUri;
    }

    if (billScheme == 'bnl') {
      final String billNewPath =
      billUri.path.isNotEmpty ? billUri.path : '';
      return Uri.https(
        'bnl.com',
        '/$billNewPath',
        billUri.queryParameters.isEmpty
            ? null
            : billUri.queryParameters,
      );
    }

    return billUri;
  }

  Future<bool> _openBillMailWeb(Uri billMailto) async {
    final Uri billGmailUri = _billGmailize(billMailto);
    return await _openBillWeb(billGmailUri);
  }

  Uri _billGmailize(Uri billMailUri) {
    final Map<String, String> billQueryParams =
        billMailUri.queryParameters;

    final Map<String, String> billParams = <String, String>{
      'view': 'cm',
      'fs': '1',
      if (billMailUri.path.isNotEmpty) 'to': billMailUri.path,
      if ((billQueryParams['subject'] ?? '').isNotEmpty)
        'su': billQueryParams['subject']!,
      if ((billQueryParams['body'] ?? '').isNotEmpty)
        'body': billQueryParams['body']!,
      if ((billQueryParams['cc'] ?? '').isNotEmpty)
        'cc': billQueryParams['cc']!,
      if ((billQueryParams['bcc'] ?? '').isNotEmpty)
        'bcc': billQueryParams['bcc']!,
    };

    return Uri.https('mail.google.com', '/mail/', billParams);
  }

  Future<bool> _openBillWeb(Uri billUri) async {
    try {
      if (await launchUrl(
        billUri,
        mode: LaunchMode.inAppBrowserView,
      )) {
        return true;
      }

      return await launchUrl(
        billUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (billError) {
      debugPrint('openInAppBrowser error: $billError; url=$billUri');
      try {
        return await launchUrl(
          billUri,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }

  Future<bool> _openBillExternal(Uri billUri) async {
    try {
      return await launchUrl(
        billUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (billError) {
      debugPrint('openExternal error: $billError; url=$billUri');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _bindBillNotificationTap(); // повторная привязка

    Widget billContent = Stack(
      children: <Widget>[
        if (billCoverVisible)
          const BillXOLoader()
        else
          Container(
            color: Colors.black,
            child: Stack(
              children: <Widget>[
                InAppWebView(
                  key: ValueKey<int>(billHatchCounter),
                  initialSettings:  InAppWebViewSettings(
                    javaScriptEnabled: true,
                    disableDefaultErrorPage: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback: true,
                    allowsPictureInPictureMediaPlayback: true,
                    useOnDownloadStart: true,
                    javaScriptCanOpenWindowsAutomatically: true,
                    useShouldOverrideUrlLoading: true,
                    supportMultipleWindows: true,
                    transparentBackground: true,
                  ),
                  initialUrlRequest: URLRequest(
                    url: WebUri(billHomeUrl),
                  ),
                  onWebViewCreated:
                      (InAppWebViewController billController) {
                    billWebViewController = billController;

                    billBosun ??= BillBosun(
                      billDeviceDeck: billDeviceDeck,
                      billSpy: billSpy,
                    );

                    billCourier ??= BillCourier(
                      billBosun: billBosun!,
                      getBillWebView: () => billWebViewController,
                    );

                    billWebViewController.addJavaScriptHandler(
                      handlerName: 'onServerResponse',
                      callback: (List<dynamic> billArgs) {
                        try {
                          if (billArgs.isNotEmpty &&
                              billArgs[0] is Map) {
                            final dynamic billRaw =
                            billArgs[0]['savedata'];
                            final String billSavedata =
                                billRaw?.toString() ?? '';

                            print("Server response: $billSavedata");

                            // savedata == "false" → ВКЛЮЧИТЬ SafeArea
                            // savedata == "true"  → ВЫКЛЮЧИТЬ SafeArea
                            if (billSavedata == "false") {
                              setState(() {
                                billUseSafeArea = true;
                              });
                            } else if (billSavedata == "true") {
                              setState(() {
                                billUseSafeArea = false;
                              });
                            }
                          }
                        } catch (_) {}

                        if (billArgs.isEmpty) {
                          return null;
                        }

                        try {
                          return billArgs.reduce(
                                (dynamic current, dynamic next) =>
                            current + next,
                          );
                        } catch (_) {
                          return billArgs.first;
                        }
                      },
                    );
                  },
                  onLoadStart: (InAppWebViewController billC,
                      Uri? billUri) async {
                    setState(() {
                      billStartLoadTimestamp =
                          DateTime.now().millisecondsSinceEpoch;
                    });

                    final Uri? billViewUri = billUri;
                    if (billViewUri != null) {
                      if (_isBillBareEmail(billViewUri)) {
                        try {
                          await billC.stopLoading();
                        } catch (_) {}
                        final Uri billMailto =
                        _toBillMailto(billViewUri);
                        await _openBillMailWeb(billMailto);
                        return;
                      }

                      final String billScheme =
                      billViewUri.scheme.toLowerCase();
                      if (billScheme != 'http' &&
                          billScheme != 'https') {
                        try {
                          await billC.stopLoading();
                        } catch (_) {}
                      }
                    }
                  },
                  onLoadError: (
                      InAppWebViewController billController,
                      Uri? billUrl,
                      int billCode,
                      String billMessage,
                      ) async {
                    final int billNow =
                        DateTime.now().millisecondsSinceEpoch;
                    final String billEvent =
                        'InAppWebViewError(code=$billCode, message=$billMessage)';

                    await billPostStat(
                      billEvent: billEvent,
                      billTimeStart: billNow,
                      billTimeFinish: billNow,
                      billUrl: billUrl?.toString() ?? '',
                      billAppSid: billSpy.billAfUid,
                      billFirstPageLoadTs: billFirstPageTimestamp,
                    );
                  },
                  onReceivedError: (
                      InAppWebViewController billController,
                      WebResourceRequest billRequest,
                      WebResourceError billError,
                      ) async {
                    final int billNow =
                        DateTime.now().millisecondsSinceEpoch;
                    final String billDescription =
                    (billError.description ?? '').toString();
                    final String billEvent =
                        'WebResourceError(code=$billError, message=$billDescription)';

                    await billPostStat(
                      billEvent: billEvent,
                      billTimeStart: billNow,
                      billTimeFinish: billNow,
                      billUrl: billRequest.url?.toString() ?? '',
                      billAppSid: billSpy.billAfUid,
                      billFirstPageLoadTs: billFirstPageTimestamp,
                    );
                  },
                  onLoadStop: (InAppWebViewController billC,
                      Uri? billUri) async {
                    await billC.evaluateJavascript(
                      source: 'console.log(\'NeonCinema harbor up!\');',
                    );

                    await _pushBillDevice();
                    await _pushBillAfData();

                    setState(() {
                      billCurrentUrl = billUri.toString();
                    });

                    Future<void>.delayed(
                      const Duration(seconds: 20),
                          () {
                        sendBillLoadedOnce(
                          billUrl: billCurrentUrl.toString(),
                          billTimestart: billStartLoadTimestamp,
                        );
                      },
                    );
                  },
                  shouldOverrideUrlLoading: (
                      InAppWebViewController billC,
                      NavigationAction billAction,
                      ) async {
                    final Uri? billUri = billAction.request.url;
                    if (billUri == null) {
                      return NavigationActionPolicy.ALLOW;
                    }

                    if (_isBillBareEmail(billUri)) {
                      final Uri billMailto =
                      _toBillMailto(billUri);
                      await _openBillMailWeb(billMailto);
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String billScheme =
                    billUri.scheme.toLowerCase();

                    if (billScheme == 'mailto') {
                      await _openBillMailWeb(billUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (billScheme == 'tel') {
                      await launchUrl(
                        billUri,
                        mode: LaunchMode.externalApplication,
                      );
                      return NavigationActionPolicy.CANCEL;
                    }

                    final String billHost =
                    billUri.host.toLowerCase();
                    final bool billIsSocial =
                        billHost.endsWith('facebook.com') ||
                            billHost.endsWith('instagram.com') ||
                            billHost.endsWith('twitter.com') ||
                            billHost.endsWith('x.com');

                    if (billIsSocial) {
                      await _openBillExternal(billUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (_isBillPlatformish(billUri)) {
                      final Uri billWebUri = _billHttpize(billUri);
                      await _openBillExternal(billWebUri);
                      return NavigationActionPolicy.CANCEL;
                    }

                    if (billScheme != 'http' &&
                        billScheme != 'https') {
                      return NavigationActionPolicy.CANCEL;
                    }

                    return NavigationActionPolicy.ALLOW;
                  },
                  onCreateWindow: (
                      InAppWebViewController billC,
                      CreateWindowAction billRequest,
                      ) async {
                    final Uri? billUri = billRequest.request.url;
                    if (billUri == null) {
                      return false;
                    }

                    if (_isBillBareEmail(billUri)) {
                      final Uri billMailto =
                      _toBillMailto(billUri);
                      await _openBillMailWeb(billMailto);
                      return false;
                    }

                    final String billScheme =
                    billUri.scheme.toLowerCase();

                    if (billScheme == 'mailto') {
                      await _openBillMailWeb(billUri);
                      return false;
                    }

                    if (billScheme == 'tel') {
                      await launchUrl(
                        billUri,
                        mode: LaunchMode.externalApplication,
                      );
                      return false;
                    }

                    final String billHost =
                    billUri.host.toLowerCase();
                    final bool billIsSocial =
                        billHost.endsWith('facebook.com') ||
                            billHost.endsWith('instagram.com') ||
                            billHost.endsWith('twitter.com') ||
                            billHost.endsWith('x.com');

                    if (billIsSocial) {
                      await _openBillExternal(billUri);
                      return false;
                    }

                    if (_isBillPlatformish(billUri)) {
                      final Uri billWebUri = _billHttpize(billUri);
                      await _openBillExternal(billWebUri);
                      return false;
                    }

                    if (billScheme == 'http' ||
                        billScheme == 'https') {
                      billC.loadUrl(
                        urlRequest: URLRequest(
                          url: WebUri(billUri.toString()),
                        ),
                      );
                    }

                    return false;
                  },
                  onDownloadStartRequest: (
                      InAppWebViewController billC,
                      DownloadStartRequest billReq,
                      ) async {
                    await _openBillExternal(billReq.url);
                  },
                ),
                Visibility(
                  visible: !billVeilVisible,
                  child: const BillXOLoader(),
                ),
              ],
            ),
          ),
      ],
    );

    if (billUseSafeArea) {
      billContent = SafeArea(child: billContent);
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: billContent,
      ),
    );
  }
}

// ============================================================================
// Отдельный WebView для внешней ссылки (из уведомлений)
// ============================================================================

class BillExternalScreen extends StatefulWidget with WidgetsBindingObserver {
  final String billLane;

  const BillExternalScreen(this.billLane, {super.key});

  @override
  State<BillExternalScreen> createState() => _BillExternalScreenState();
}

class _BillExternalScreenState extends State<BillExternalScreen>
    with WidgetsBindingObserver {
  late InAppWebViewController billExternalWebView;

  @override
  Widget build(BuildContext context) {
    final bool billIsDark =
        MediaQuery.of(context).platformBrightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: billIsDark
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: InAppWebView(
          initialSettings:  InAppWebViewSettings(
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
          initialUrlRequest:
          URLRequest(url: WebUri(widget.billLane)),
          onWebViewCreated:
              (InAppWebViewController billC) {
            billExternalWebView = billC;
          },
        ),
      ),
    );
  }
}


// ============================================================================
// main()
// ============================================================================

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(billFcmBackgroundHandler);

  if (Platform.isAndroid) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  tzData.initializeTimeZones();

  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: BillHall(),
    ),
  );
}