import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Metro Sound Pro: one-time unlock (unlimited books, recorder, no reminders).
///
/// Free tier is fully usable — 1 book, metronome and tuner unrestricted. A
/// polite upgrade reminder appears after the 5th session, at most once a day,
/// and only when a tool session *ends* (never blocking the moment of use).
///
/// Trial/nag state lives in the iOS Keychain (not the app sandbox) so deleting
/// and reinstalling the app doesn't reset the session counter. The purchase
/// itself lives on the Apple ID: entitlements are re-checked against StoreKit
/// on every launch, so a reinstall or new phone silently restores Pro.
class Pro extends ChangeNotifier {
  /// Product id of the non-consumable unlock in App Store Connect.
  static const String productId = 'metrosound_pro_unlock';

  /// Free tier allows this many books.
  static const int freeBookLimit = 1;

  /// Grammatically-correct sentence for the free library cap, used as the Pro
  /// gate reason. Handles the singular case so it never reads "up to 1 books".
  static String get freeLibraryLimitText => freeBookLimit == 1
      ? 'Your first book is free.'
      : 'The free version holds up to $freeBookLimit books.';

  /// The reminder starts after this many sessions.
  static const int nagAfterSessions = 5;

  // Two opens within this window count as one practice session.
  static const Duration _sessionGap = Duration(minutes: 30);

  // Keychain: survives app deletion. Not synchronizable — per-device is fine
  // for nag state; the purchase itself follows the Apple ID via StoreKit.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  static const _kPro = 'pro_unlocked';
  static const _kSessions = 'session_count';
  static const _kLastSession = 'last_session_at';
  static const _kLastNag = 'last_nag_day';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  bool get supported =>
      !kIsWeb && (Platform.isIOS || Platform.isMacOS || Platform.isAndroid);

  bool _isPro = false;
  bool get isPro => _isPro;

  // Whether this is a test build (debug or TestFlight) rather than a production
  // App Store install. Used ONLY to gate the developer/testing tools in Settings
  // (reset cache / data / purchase) — it never affects entitlement. Both
  // TestFlight and App Review run in the sandbox (receipt "sandboxReceipt"),
  // while a production install has a "receipt" receipt; checked natively at init
  // and fails closed to false.
  static const _envChannel = MethodChannel('metro_sound/build_env');
  bool _isTestBuild = kDebugMode;
  bool get isTestBuild => _isTestBuild;

  /// Test-only: clear the local Pro entitlement (Keychain + memory) without
  /// affecting the Apple ID's ownership, so the Restore flow can be exercised on
  /// a single device. No-op outside a test build.
  Future<void> resetPurchaseLocal() async {
    if (!_isTestBuild) return;
    await _setPro(false);
  }

  /// Detect whether this is a test (debug/TestFlight) build so the testing tools
  /// stay hidden in production. Fails closed to production.
  Future<void> _detectTestBuild() async {
    if (kDebugMode) {
      _isTestBuild = true;
      return;
    }
    if (kIsWeb || !Platform.isIOS) return; // only the iOS receipt check exists
    try {
      _isTestBuild = await _envChannel.invokeMethod<bool>('isSandbox') ?? false;
    } catch (e) {
      debugPrint('build env check failed: $e');
      _isTestBuild = false; // fail closed → treat as production
    }
  }

  bool _storeAvailable = false;
  ProductDetails? _product;

  /// Localized price from the store, with a sensible placeholder until loaded.
  String get price => _product?.price ?? '\$2.99';

  bool _purchasing = false;
  bool get purchasing => _purchasing;

  String? _error;
  String? get error => _error;

  int _sessions = 0;
  int get sessions => _sessions;

  DateTime? _lastSessionAt;
  String? _lastNagDay;

  Future<void> init() async {
    // Determine test-vs-production first so the tester bypass is settled before
    // the UI reads isPro. Runs on every platform (unsupported ones just stay in
    // their kDebugMode default).
    await _detectTestBuild();
    notifyListeners();
    if (!supported) return;
    // Keychain first: instant + offline. StoreKit confirms/updates it below.
    try {
      _isPro = await _storage.read(key: _kPro) == 'true';
      _sessions = int.tryParse(await _storage.read(key: _kSessions) ?? '') ?? 0;
      final last = await _storage.read(key: _kLastSession);
      if (last != null) _lastSessionAt = DateTime.tryParse(last);
      _lastNagDay = await _storage.read(key: _kLastNag);
    } catch (e) {
      debugPrint('Pro keychain read failed: $e');
    }
    notifyListeners();

    // The purchase stream delivers new buys, restores, and (on iOS) existing
    // transactions replayed at startup — one handler covers them all.
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => debugPrint('purchaseStream error: $e'),
    );

    await loadProduct();

    await maybeCountSession();
  }

  /// (Re)fetch the product from the store. Safe to call repeatedly — used at
  /// launch and every time the paywall opens, so a product that wasn't yet
  /// available at launch (e.g. App Store Connect propagation delay after a new
  /// IAP / agreement, or a flaky network) self-heals without an app restart.
  Future<void> loadProduct() async {
    if (!supported) return;
    try {
      _storeAvailable = await _iap.isAvailable();
      if (!_storeAvailable) return;
      final resp = await _iap.queryProductDetails({productId});
      if (resp.productDetails.isNotEmpty) {
        _product = resp.productDetails.first;
        notifyListeners();
      } else {
        debugPrint('Pro product not found: ${resp.notFoundIDs}');
      }
    } catch (e) {
      debugPrint('Pro store query failed: $e');
    }
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      if (p.productID != productId) continue;
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _setPro(true);
          _purchasing = false;
          _error = null;
        case PurchaseStatus.error:
          _purchasing = false;
          // Cancellations surface as errors on iOS — keep the message quiet.
          _error = p.error?.message;
          debugPrint('Pro purchase error: ${p.error}');
        case PurchaseStatus.canceled:
          _purchasing = false;
          _error = null;
        case PurchaseStatus.pending:
          _purchasing = true;
      }
      if (p.pendingCompletePurchase) {
        _iap.completePurchase(p).catchError(
              (Object e) => debugPrint('completePurchase failed: $e'),
            );
      }
    }
    notifyListeners();
  }

  Future<void> _setPro(bool v) async {
    if (_isPro == v) return;
    _isPro = v;
    try {
      await _storage.write(key: _kPro, value: v ? 'true' : 'false');
    } catch (e) {
      debugPrint('Pro keychain write failed: $e');
    }
    notifyListeners();
  }

  /// Kick off the App Store purchase. Result arrives via the purchase stream.
  Future<void> buy() async {
    if (!supported || _isPro || _purchasing) return;
    // One more fetch in case the product wasn't available at launch (store
    // propagation / network) — avoids a dead "unavailable" button after a wait.
    if (_product == null) await loadProduct();
    if (_product == null) {
      _error = 'The App Store is unavailable right now — try again later.';
      notifyListeners();
      return;
    }
    _purchasing = true;
    _error = null;
    notifyListeners();
    try {
      await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: _product!),
      );
    } catch (e) {
      _purchasing = false;
      _error = '$e';
      notifyListeners();
    }
  }

  /// Re-deliver past purchases (new phone, reinstall, family member's device).
  Future<void> restore() async {
    if (!supported) return;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      _error = '$e';
      notifyListeners();
    }
  }

  // ─── Sessions + reminder ───

  /// Count a practice session, at most one per [_sessionGap]. Called on app
  /// launch and on foreground resume.
  Future<void> maybeCountSession() async {
    if (!supported || _isPro) return;
    final now = DateTime.now();
    if (_lastSessionAt != null &&
        now.difference(_lastSessionAt!) < _sessionGap) {
      return;
    }
    _lastSessionAt = now;
    _sessions += 1;
    try {
      await _storage.write(key: _kSessions, value: '$_sessions');
      await _storage.write(key: _kLastSession, value: now.toIso8601String());
    } catch (e) {
      debugPrint('Pro keychain write failed: $e');
    }
  }

  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  /// Whether the polite reminder should show right now (call when a metronome
  /// or tuner session ends). Never for Pro users, never before session 5,
  /// never twice in a day.
  bool get shouldNag =>
      supported && !_isPro && _sessions >= nagAfterSessions &&
      _lastNagDay != _today();

  /// Record that the reminder was shown (whatever the user chose).
  Future<void> markNagged() async {
    _lastNagDay = _today();
    try {
      await _storage.write(key: _kLastNag, value: _lastNagDay!);
    } catch (e) {
      debugPrint('Pro keychain write failed: $e');
    }
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }
}
