import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

final _detector = FaceDetector(
  options: FaceDetectorOptions(
    performanceMode: FaceDetectorMode.fast,
    enableContours: false,
    enableClassification: false,
    enableLandmarks: false,
    enableTracking: false,
    minFaceSize: 0.10,
  ),
);

/// Detect face with ML Kit, crop to 224×224, return base64 JPEG.
/// If no face detected, falls back to center crop so photo is never skipped.
/// Returns null only if image bytes cannot be decoded.
Future<String?> cropFaceToBase64(XFile xFile) async {
  final bytes = await xFile.readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // Run ML Kit face detection
  final inputImage = InputImage.fromFilePath(xFile.path);
  final faces = await _detector.processImage(inputImage);

  img.Image cropped;

  if (faces.isNotEmpty) {
    // Pick largest face
    final face = faces.reduce((a, b) {
      final aArea = a.boundingBox.width * a.boundingBox.height;
      final bArea = b.boundingBox.width * b.boundingBox.height;
      return aArea >= bArea ? a : b;
    });

    final box = face.boundingBox;
    final iw = decoded.width.toDouble();
    final ih = decoded.height.toDouble();
    final pad = (box.width + box.height) / 2 * 0.20;

    final x1 = (box.left   - pad).clamp(0.0, iw - 1).toInt();
    final y1 = (box.top    - pad).clamp(0.0, ih - 1).toInt();
    final x2 = (box.right  + pad).clamp(1.0, iw).toInt();
    final y2 = (box.bottom + pad).clamp(1.0, ih).toInt();
    final cw = (x2 - x1).clamp(1, decoded.width);
    final ch = (y2 - y1).clamp(1, decoded.height);

    cropped = img.copyCrop(decoded, x: x1, y: y1, width: cw, height: ch);
  } else {
    // Fallback: center square crop (face guide circle is centered)
    final size = decoded.width < decoded.height ? decoded.width : decoded.height;
    final x1 = (decoded.width  - size) ~/ 2;
    final y1 = (decoded.height - size) ~/ 2;
    cropped = img.copyCrop(decoded, x: x1, y: y1, width: size, height: size);
  }

  final resized  = img.copyResize(cropped, width: 224, height: 224);
  final jpgBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  return base64Encode(jpgBytes);
}

void disposeFaceDetector() => _detector.close();
