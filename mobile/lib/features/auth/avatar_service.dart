import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AvatarService {
  AvatarService(this.client);
  final SupabaseClient client;
  final ImagePicker _picker = ImagePicker();
  static const bucket = 'okeyx-avatars';

  Future<String?> pickAndUpload({ImageSource source = ImageSource.gallery}) async {
    final user = client.auth.currentUser;
    if (user == null) throw StateError('auth_session_missing');

    final picked = await _picker.pickImage(
      source: source,
      maxWidth: 1400,
      maxHeight: 1400,
      imageQuality: 86,
      requestFullMetadata: false,
    );
    if (picked == null) return null;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 78,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Profil fotoğrafını kırp',
          toolbarColor: const Color(0xFF160F3C),
          toolbarWidgetColor: Colors.white,
          backgroundColor: const Color(0xFF0E0927),
          activeControlsWidgetColor: const Color(0xFF54E2BE),
          lockAspectRatio: true,
          hideBottomControls: false,
          initAspectRatio: CropAspectRatioPreset.square,
        ),
        IOSUiSettings(
          title: 'Profil fotoğrafını kırp',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
        ),
      ],
    );
    if (cropped == null) return null;

    final bytes = await cropped.readAsBytes();
    if (bytes.isEmpty) throw const FormatException('avatar_empty');
    if (bytes.length > 2800 * 1024) throw const FormatException('avatar_too_large');

    final path = '${user.id}/avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await client.storage.from(bucket).uploadBinary(
            path,
            Uint8List.fromList(bytes),
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false, cacheControl: '3600'),
          );
      final url = client.storage.from(bucket).getPublicUrl(path);
      debugPrint('OKEYX_AVATAR_UPLOAD_OK bytes=${bytes.length} path=$path');
      return url;
    } catch (e, st) {
      debugPrint('OKEYX_AVATAR_UPLOAD_ERROR bytes=${bytes.length} path=$path error=$e');
      debugPrintStack(stackTrace: st);
      rethrow;
    }
  }

  Future<void> deleteOwned(String? url) async {
    final user = client.auth.currentUser;
    if (user == null || url == null) return;
    const marker = '/storage/v1/object/public/okeyx-avatars/';
    final index = url.indexOf(marker);
    if (index < 0) return;
    final path = Uri.decodeComponent(url.substring(index + marker.length));
    if (path.startsWith('${user.id}/')) {
      try {
        await client.storage.from(bucket).remove([path]);
      } catch (_) {}
    }
  }
}
