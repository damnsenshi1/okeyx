import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommerceResult {
  final bool ok;
  final String message;
  final Map<String, dynamic> data;
  const CommerceResult(this.ok, this.message, [this.data = const {}]);
}

class CommerceService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final Map<String, ProductDetails> _products = {};
  void Function(Map<String, dynamic>)? onVerified;
  void Function(String)? onStatus;
  /// Oyun sunucusu doğrulaması (cüzdan orada tutulur). Verilmezse eski Supabase fonksiyonuna düşer.
  Future<Map<String, dynamic>> Function(String productId, String purchaseToken)? serverVerify;

  Future<void> initialize({
    void Function(Map<String, dynamic>)? onVerified,
    void Function(String)? onStatus,
  }) async {
    this.onVerified = onVerified;
    this.onStatus = onStatus;
    _subscription ??= _iap.purchaseStream.listen(
      _handlePurchases,
      onError: (Object error) => onStatus?.call('Satın alma akışı: $error'),
    );
  }

  Future<Map<String, ProductDetails>> loadProducts(Iterable<String> ids) async {
    final clean = ids.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (clean.isEmpty) return _products;
    if (!await _iap.isAvailable()) {
      onStatus?.call('Google Play satın alma servisi bu cihazda kullanılamıyor.');
      return _products;
    }
    final response = await _iap.queryProductDetails(clean);
    if (response.error != null) {
      onStatus?.call(response.error!.message);
    }
    for (final product in response.productDetails) {
      _products[product.id] = product;
    }
    return Map.unmodifiable(_products);
  }

  ProductDetails? product(String sku) => _products[sku];

  Future<CommerceResult> buy(String sku, {required bool consumable}) async {
    final product = _products[sku];
    if (product == null) {
      return const CommerceResult(false, 'Ürün Google Play test kanalında bulunamadı.');
    }
    final param = PurchaseParam(productDetails: product);
    final started = consumable
        ? await _iap.buyConsumable(purchaseParam: param, autoConsume: true)
        : await _iap.buyNonConsumable(purchaseParam: param);
    return CommerceResult(started, started ? 'Google Play açıldı.' : 'Satın alma başlatılamadı.');
  }

  Future<void> restore() => _iap.restorePurchases();

  Future<void> _handlePurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        onStatus?.call('Satın alma onayı bekleniyor…');
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        onStatus?.call(purchase.error?.message ?? 'Satın alma başarısız.');
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        onStatus?.call('Satın alma iptal edildi.');
        continue;
      }
      if (purchase.status == PurchaseStatus.purchased || purchase.status == PurchaseStatus.restored) {
        final verified = await _verifyOnServer(purchase);
        if (!verified.ok) {
          onStatus?.call(verified.message);
          continue;
        }
        onVerified?.call(verified.data);
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      }
    }
  }

  Future<CommerceResult> _verifyOnServer(PurchaseDetails purchase) async {
    try {
      final verify = serverVerify;
      if (verify != null) {
        final data = await verify(purchase.productID, purchase.verificationData.serverVerificationData);
        if (data['ok'] != true) {
          return CommerceResult(false, '${data['code'] ?? 'Satın alma sunucuda doğrulanamadı.'}', data);
        }
        return CommerceResult(true, 'Satın alma doğrulandı.', data);
      }
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) {
        return const CommerceResult(false, 'Satın alma için hesabını bağlamalısın.');
      }
      final response = await client.functions.invoke(
        'okeyx-play-verify',
        body: {
          'product_id': purchase.productID,
          'purchase_token': purchase.verificationData.serverVerificationData,
          'purchase_id': purchase.purchaseID,
          'source': 'flutter_google_play',
        },
      );
      final raw = response.data;
      final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      if (response.status < 200 || response.status >= 300 || data['ok'] != true) {
        return CommerceResult(false, '${data['code'] ?? 'Satın alma sunucuda doğrulanamadı.'}', data);
      }
      return CommerceResult(true, 'Satın alma doğrulandı.', data);
    } catch (error) {
      return CommerceResult(false, 'Satın alma doğrulama hatası: $error');
    }
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
