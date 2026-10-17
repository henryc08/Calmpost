import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

final photoInputProvider = Provider<PhotoInput>((ref) => PhotoInput());
final recoveredPhotoProvider = FutureProvider<Uint8List?>((ref) => ref.read(photoInputProvider).recover());

class PhotoInput {
  Future<Uint8List?> pick({required bool camera}) async {
    final file = await ImagePicker().pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    return file == null ? null : _read(file);
  }

  Future<Uint8List?> recover() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    LostDataResponse lost;
    try {
      lost = await ImagePicker().retrieveLostData();
    } on MissingPluginException {
      return null;
    }
    if (lost.exception != null) throw lost.exception!;
    final file = lost.files?.firstOrNull;
    return file == null ? null : _read(file);
  }

  Future<Uint8List> _read(XFile file) async {
    if (await file.length() > 20 * 1024 * 1024) throw const FormatException('Choose a smaller image (under 20 MB).');
    return compute(preparePhoto, await file.readAsBytes());
  }
}

/// Normalize orientation, bound dimensions/bytes, and discard EXIF metadata.
Uint8List preparePhoto(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) throw const FormatException('Choose a valid image under 20 MB.');
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 50000000) throw const FormatException('Unsupported image. Choose a smaller JPEG or PNG.');
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) throw const FormatException('Could not read that image. Try a JPEG or PNG.');
  var oriented = img.bakeOrientation(decoded);
  if (oriented.width > 1024 || oriented.height > 1024) {
    oriented = img.copyResize(oriented, width: oriented.width >= oriented.height ? 1024 : null, height: oriented.height > oriented.width ? 1024 : null);
  }
  final clean = img.Image.fromBytes(
    width: oriented.width,
    height: oriented.height,
    bytes: oriented.getBytes(order: img.ChannelOrder.rgb).buffer,
    numChannels: 3,
  );
  for (final quality in [85, 70, 55]) {
    final jpeg = img.encodeJpg(clean, quality: quality);
    if (jpeg.length <= 1400000) return jpeg;
  }
  throw const FormatException('Photo is still too large. Try a simpler or smaller image.');
}
