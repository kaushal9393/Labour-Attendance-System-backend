import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

final _detector = FaceDetector(
  options: FaceDetectorOptions(
    performanceMode: FaceDetectorMode.fast,
    enableContours: false,
    enableClassification: true,   // needed for eye-open probability (liveness)
    enableLandmarks: false,
    enableTracking: true,         // stable trackingId across frames
    minFaceSize: 0.10,
  ),
);

class FaceFrameResult {
  final String? base64Image;
  final double? leftEyeOpen;   // 0.0 = closed, 1.0 = open
  final double? rightEyeOpen;
  final bool    faceDetected;

  const FaceFrameResult({
    this.base64Image,
    this.leftEyeOpen,
    this.rightEyeOpen,
    required this.faceDetected,
  });
}

/// Detect face, capture eye-open probabilities for liveness, crop to 224×224.
Future<FaceFrameResult> detectFaceFrame(XFile xFile) async {
  final bytes   = await xFile.readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return const FaceFrameResult(faceDetected: false);

  final inputImage = InputImage.fromFilePath(xFile.path);
  final faces      = await _detector.processImage(inputImage);

  if (faces.isEmpty) return const FaceFrameResult(faceDetected: false);

  final face = faces.reduce((a, b) {
    final aArea = a.boundingBox.width * a.boundingBox.height;
    final bArea = b.boundingBox.width * b.boundingBox.height;
    return aArea >= bArea ? a : b;
  });

  final b64 = _cropAndEncode(decoded, face);

  return FaceFrameResult(
    base64Image:  b64,
    leftEyeOpen:  face.leftEyeOpenProbability,
    rightEyeOpen: face.rightEyeOpenProbability,
    faceDetected: true,
  );
}

/// Crop detected face region from [decoded] image and return base64 JPEG.
String _cropAndEncode(img.Image decoded, Face face) {
  final box = face.boundingBox;
  final iw  = decoded.width.toDouble();
  final ih  = decoded.height.toDouble();
  final pad = (box.width + box.height) / 2 * 0.20;

  final x1 = (box.left   - pad).clamp(0.0, iw - 1).toInt();
  final y1 = (box.top    - pad).clamp(0.0, ih - 1).toInt();
  final x2 = (box.right  + pad).clamp(1.0, iw).toInt();
  final y2 = (box.bottom + pad).clamp(1.0, ih).toInt();
  final cw  = (x2 - x1).clamp(1, decoded.width);
  final ch  = (y2 - y1).clamp(1, decoded.height);

  final cropped  = img.copyCrop(decoded, x: x1, y: y1, width: cw, height: ch);
  final resized  = img.copyResize(cropped, width: 224, height: 224);
  final jpgBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  return base64Encode(jpgBytes);
}

/// Detect face with ML Kit, crop to 224×224, return base64 JPEG.
/// Returns null only if image bytes cannot be decoded.
Future<String?> cropFaceToBase64(XFile xFile) async {
  final bytes   = await xFile.readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  final faces = await _detector.processImage(InputImage.fromFilePath(xFile.path));

  if (faces.isNotEmpty) {
    final face = faces.reduce((a, b) {
      final aArea = a.boundingBox.width * a.boundingBox.height;
      final bArea = b.boundingBox.width * b.boundingBox.height;
      return aArea >= bArea ? a : b;
    });
    return _cropAndEncode(decoded, face);
  }

  // Fallback: center square crop
  final size = decoded.width < decoded.height ? decoded.width : decoded.height;
  final x1   = (decoded.width  - size) ~/ 2;
  final y1   = (decoded.height - size) ~/ 2;
  final cropped  = img.copyCrop(decoded, x: x1, y: y1, width: size, height: size);
  final resized  = img.copyResize(cropped, width: 224, height: 224);
  final jpgBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
  return base64Encode(jpgBytes);
}

void disposeFaceDetector() => _detector.close();
