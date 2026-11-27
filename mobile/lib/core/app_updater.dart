import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Uygulama içi güncelleme.
///
/// Her imzalı derleme GitHub'da "vX.Y.Z-bNNN" etiketli bir sürüm olarak
/// yayınlanır ve içinde `okeyx.apk` bulunur. Uygulama açılışta en son
/// sürümün derleme numarasını kendi numarasıyla karşılaştırır; yeniyse
/// APK'yı uygulamanın içinden indirip Android kurulum ekranını açar.
/// Sürüm notlarında `[zorunlu]` geçerse "Sonra" seçeneği gösterilmez.
class AppUpdater {
  AppUpdater._();

  static const _repo = 'damnsenshi1/okeyx';
  static const currentBuild = int.fromEnvironment('OKEYX_BUILD', defaultValue: 0);
  static const _channel = MethodChannel('com.senshilabs.okeyx_mobile/share');
  static bool _checkedThisSession = false;
  static bool _lastCheckFailed = false;

  static Future<AppUpdateInfo?> fetchLatest() async {
    if (kIsWeb || !Platform.isAndroid || currentBuild <= 0) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    _lastCheckFailed = false;
    try {
      final req = await client.getUrl(Uri.parse('https://api.github.com/repos/$_repo/releases/latest'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'okeyx-app');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        _lastCheckFailed = true;
        return null;
      }
      final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final tag = '${body['tag_name'] ?? ''}';
      final build = int.tryParse(RegExp(r'-b(\d+)$').firstMatch(tag)?.group(1) ?? '') ?? 0;
      if (build <= currentBuild) return null;
      final assets = (body['assets'] as List? ?? const []).cast<Map<String, dynamic>>();
      final apk = assets.where((a) => '${a['name']}'.endsWith('.apk')).firstOrNull;
      if (apk == null) return null;
      final notes = '${body['body'] ?? ''}';
      return AppUpdateInfo(
        version: RegExp(r'^v([\d.]+)').firstMatch(tag)?.group(1) ?? tag,
        build: build,
        notes: notes.replaceAll('[zorunlu]', '').trim(),
        url: '${apk['browser_download_url']}',
        size: (apk['size'] as num?)?.toInt() ?? 0,
        mandatory: notes.contains('[zorunlu]'),
      );
    } catch (e) {
      debugPrint('OKEYX_UPDATE_CHECK $e');
      _lastCheckFailed = true;
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Açılışta bir kez kontrol eder; güncelleme varsa pencere açar.
  static DateTime? _lastCheck;
  static int _promptedBuild = 0;

  static Future<void> checkAndPrompt(BuildContext context, {bool force = false}) async {
    // Açılışta, uygulamaya geri dönünce ve oyun açıkken 30 dakikada bir bakar.
    final now = DateTime.now();
    if (!force && _lastCheck != null && now.difference(_lastCheck!) < const Duration(minutes: 30)) return;
    _lastCheck = now;
    _checkedThisSession = true;
    if (force && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(duration: Duration(seconds: 2), content: Text('Güncellemeler denetleniyor…')));
    }
    final info = await fetchLatest();
    if (info == null) {
      if (force && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(_lastCheckFailed ? 'Güncelleme sunucusuna ulaşılamadı. İnternetini kontrol edip tekrar dene.' : 'Oyun güncel. En son sürümü kullanıyorsun.')));
      }
      return;
    }
    if (!context.mounted) return;
    // Aynı sürüm için "Sonra" denmişse yarım saatte bir tekrar sormak yerine üstte kısa bildirim göster.
    if (!force && !info.mandatory && _promptedBuild == info.build) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text('Yeni sürüm hazır: OKEYX ${info.version}'),
        action: SnackBarAction(label: 'GÜNCELLE', onPressed: () => checkAndPrompt(context, force: true)),
      ));
      return;
    }
    _promptedBuild = info.build;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: !info.mandatory,
      barrierLabel: 'Güncelleme',
      barrierColor: Colors.black.withValues(alpha: .72),
      transitionDuration: const Duration(milliseconds: 320),
      transitionBuilder: (context, a, _, child) => Transform.scale(scale: .9 + .1 * Curves.easeOutBack.transform(a.value), child: Opacity(opacity: a.value, child: child)),
      pageBuilder: (context, _, __) => PopScope(canPop: !info.mandatory, child: _UpdateDialog(info: info)),
    );
  }

  static Future<String> _download(AppUpdateInfo info, void Function(double) onProgress) async {
    final dir = await _channel.invokeMethod<String>('cacheDir') ?? Directory.systemTemp.path;
    final file = File('$dir/okeyx_update_${info.build}.apk');
    if (await file.exists() && info.size > 0 && await file.length() == info.size) return file.path;
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(info.url));
      req.headers.set(HttpHeaders.userAgentHeader, 'okeyx-app');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('İndirme başarısız (${res.statusCode})');
      final total = res.contentLength > 0 ? res.contentLength : info.size;
      final sink = file.openWrite();
      var got = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress(got / total);
      }
      await sink.close();
      return file.path;
    } finally {
      client.close(force: true);
    }
  }

  static Future<bool> _install(String path) async {
    final allowed = await _channel.invokeMethod<bool>('canInstall') ?? true;
    if (!allowed) {
      await _channel.invokeMethod('openInstallSettings');
      return false;
    }
    await _channel.invokeMethod('installApk', {'path': path});
    return true;
  }
}

class AppUpdateInfo {
  const AppUpdateInfo({required this.version, required this.build, required this.notes, required this.url, required this.size, required this.mandatory});
  final String version;
  final int build;
  final String notes;
  final String url;
  final int size;
  final bool mandatory;
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});
  final AppUpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String _status = '';
  String? _apkPath;

  Future<void> _start() async {
    setState(() {
      _progress = 0;
      _status = 'İndiriliyor…';
    });
    try {
      _apkPath ??= await AppUpdater._download(widget.info, (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() => _status = 'Kurulum açılıyor…');
      final ok = await AppUpdater._install(_apkPath!);
      if (!mounted) return;
      setState(() => _status = ok
          ? 'Kurulum ekranında "Güncelle"ye bas.'
          : 'Ayarlarda "Bu kaynaktan izin ver"i aç, sonra geri dönüp tekrar GÜNCELLE\'ye bas.');
      setState(() => _progress = null);
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _status = 'İndirilemedi. İnternetini kontrol edip tekrar dene.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    final mb = info.size > 0 ? '${(info.size / 1048576).toStringAsFixed(0)} MB' : '';
    final busy = _progress != null;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 560,
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9, maxWidth: MediaQuery.sizeOf(context).width * .9),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2A1B6E), Color(0xFF0E3A6B), Color(0xFF0B5E57)]),
            border: Border.all(color: const Color(0x66FFFFFF)),
            boxShadow: const [BoxShadow(color: Color(0x997C4DFF), blurRadius: 40, spreadRadius: -6), BoxShadow(color: Color(0xAA000000), blurRadius: 30, offset: Offset(0, 14))],
          ),
          // Butonlar her zaman görünür: yalnızca sürüm notları kayar.
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFFFFD25A), Color(0xFFFF7A3D)])),
                  child: const Icon(Icons.system_update_rounded, color: Colors.white, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Yeni sürüm hazır!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                    Text('OKEYX ${info.version}${mb.isEmpty ? '' : ' • $mb'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFB9E8FF))),
                  ]),
                ),
              ]),
              if (info.notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Flexible(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0x33000000), borderRadius: BorderRadius.circular(14)),
                    child: SingleChildScrollView(child: Text(info.notes, style: const TextStyle(fontSize: 13, height: 1.4, color: Color(0xFFEAF2FF)))),
                  ),
                ),
              ],
              if (info.mandatory) ...[
                const SizedBox(height: 10),
                const Text('Bu güncelleme zorunlu: oynamaya devam etmek için güncellemelisin.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFFFC46B))),
              ],
              const SizedBox(height: 12),
              if (busy) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: _progress == 0 ? null : _progress, minHeight: 10, backgroundColor: const Color(0x33FFFFFF), valueColor: const AlwaysStoppedAnimation(Color(0xFF4DF2C2))),
                ),
                const SizedBox(height: 8),
              ],
              if (_status.isNotEmpty) Text(busy && (_progress ?? 0) > 0 ? '$_status %${((_progress ?? 0) * 100).round()}' : _status, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white70)),
              const SizedBox(height: 12),
              Row(children: [
                if (!info.mandatory)
                  Expanded(
                    child: TextButton(
                      onPressed: busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('SONRA', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white70, letterSpacing: 1)),
                    ),
                  ),
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: busy ? null : _start,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: busy ? .55 : 1,
                      child: Container(
                        height: 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(colors: [Color(0xFF3DF5B0), Color(0xFF14B8A6)]),
                          boxShadow: const [BoxShadow(color: Color(0x8014B8A6), blurRadius: 16, offset: Offset(0, 6))],
                        ),
                        child: Text(_apkPath == null ? 'GÜNCELLE' : 'KURULUMU AÇ', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: Color(0xFF06302A))),
                      ),
                    ),
                  ),
                ),
              ]),
            ]),
        ),
      ),
    );
  }
}
