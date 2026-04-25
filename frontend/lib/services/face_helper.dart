import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;

/// Singleton ML Kit face detector — created once, reused forever.
final _detector = FaceDetector(
  options: FaceDetectorOptions(
    performanceMode: FaceDetectorMode.fast,
    enableContours: false,
    enableClassification: false,
    enableLandmarks: false,
    enableTracking: false,
    minFaceSize: 0.15,
  ),
);

/// Takes an [XFile] from the camera, detects the largest face using ML Kit,
/// crops + resizes it to 224×224, and returns a base64 JPEG string.
///
/// Returns `null` if no face is found or image cannot be decoded.
/// The caller should skip this photo and try again.
Future<String?> cropFaceToBase64(XFile xFile) async {
  final bytes = await xFile.readAsBytes();

  // ML Kit needs InputImage
  final inputImage = InputImage.fromFilePath(xFile.path);
  final faces = await _detector.processImage(inputImage);

  if (faces.isEmpty) return null;

  // Pick largest face by bounding box area
  final face = faces.reduce((a, b) {
    final aArea = a.boundingBox.width * a.boundingBox.height;
    final bArea = b.boundingBox.width * b.boundingBox.height;
    return aArea >= bArea ? a : b;
  });

  // Decode image
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // Bounding box from ML Kit (in original image coords)
  final box = face.boundingBox;
  final iw = decoded.width.toDouble();
  final ih = decoded.height.toDouble();

  // Add 20% padding around the face for ArcFace accuracy
  final pad = (box.width + box.height) / 2 * 0.20;
  final x1 = (box.left   - pad).clamp(0.0, iw - 1).toInt();
  final y1 = (box.top    - pad).clamp(0.0, ih - 1).toInt();
  final x2 = (box.right  + pad).clamp(1.0, iw).toInt();
  final y2 = (box.bottom + pad).clamp(1.0, ih).toInt();
  final cw = (x2 - x1).clamp(1, decoded.width);
  final ch = (y2 - y1).clamp(1, decoded.height);

  // Crop and resize to 224×224 (ArcFace works best at this size)
  final cropped = img.copyCrop(decoded, x: x1, y: y1, width: cw, height: ch);
  final resized  = img.copyResize(cropped, width: 224, height: 224);
  final jpgBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 85));

  return base64Encode(jpgBytes);
}

/// Dispose the detector when app exits. Call from main or lifecycle observer.
void disposeFaceDetector() => _detector.close();
