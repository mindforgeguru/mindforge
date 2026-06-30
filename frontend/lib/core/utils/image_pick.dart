import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

/// Picks an image and returns its bytes + filename, or `null` if the user
/// cancelled.
///
/// Web caveat: we deliberately skip client-side `imageQuality` downscaling on
/// web. `image_picker_for_web`'s resizer re-encodes the picked file via a
/// canvas and then calls `URL.revokeObjectURL(...)` on the picked blob URL.
/// Because `XFile.readAsBytes()` on web lazily re-fetches that blob URL, the
/// read then fails with "Could not load Blob from its URL. Has it been
/// revoked?". Skipping the resize keeps the original blob URL alive so the
/// read succeeds. We lose nothing meaningful: the backend strips EXIF,
/// re-encodes the image, and enforces the size cap server-side. Native
/// platforms keep client-side downscaling, where the picker works correctly.
Future<({Uint8List bytes, String name})?> pickImageBytes(
  ImagePicker picker, {
  ImageSource source = ImageSource.gallery,
  int imageQuality = 85,
}) async {
  final picked = await picker.pickImage(
    source: source,
    imageQuality: kIsWeb ? null : imageQuality,
  );
  if (picked == null) return null;
  final bytes = await picked.readAsBytes();
  return (bytes: bytes, name: picked.name);
}
