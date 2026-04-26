import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../services/face_helper.dart';

class FaceScanScreen extends StatefulWidget {
  const FaceScanScreen({super.key});

  @override
  State<FaceScanScreen> createState() => _FaceScanScreenState();
}

class _FaceScanScreenState extends State<FaceScanScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  bool _isScanning  = false;
  bool _cameraReady = false;
  String _statusText = 'Position your face in the circle';
  Timer? _autoCapture;
  Timer? _dotTimer;
  int _dotCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() => _statusText = 'No camera found');
      return;
    }
    final cam = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _camera = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
    await _camera!.initialize();
    if (!mounted) return;
    setState(() => _cameraReady = true);

    _autoCapture = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!_isScanning && _cameraReady) _capture();
    });
  }

  Future<void> _capture() async {
    if (_camera == null || _isScanning) return;
    HapticFeedback.mediumImpact();
    _dotCount = 0;
    setState(() { _isScanning = true; _statusText = 'Scanning.'; });
    _dotTimer?.cancel();
    _dotTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (!mounted) return;
      _dotCount = (_dotCount + 1) % 4;
      setState(() => _statusText = 'Scanning${'.' * (_dotCount + 1)}');
    });

    try {
      final xFile = await _camera!.takePicture();

      // ML Kit: detect face and crop to 224×224 on device
      final b64 = await cropFaceToBase64(xFile);
      if (b64 == null) {
        // No face detected — retry silently
        _dotTimer?.cancel();
        if (mounted) {
          setState(() { _isScanning = false; _statusText = 'Position your face in the circle'; });
        }
        return;
      }

      // Send cropped face to server — server runs only ArcFace (no detection)
      final response = await ApiService().scanFace(b64, AppConstants.companyCode);
      final data     = response.data as Map<String, dynamic>;

      _dotTimer?.cancel();
      if (!mounted) return;

      if (data['success'] == true) {
        context.go('/kiosk/success', extra: {
          'employee_name': data['employee_name'],
          'time':          data['time'],
          'action':        data['action'],
        });
      } else if (data['reason'] == 'outside_checkin_window' ||
                 data['reason'] == 'outside_checkout_window') {
        context.go('/kiosk/outside-window', extra: {
          'employee_name': data['employee_name'],
          'action':        data['action'],
          'window_start':  data['window_start'],
          'window_end':    data['window_end'],
        });
      } else {
        context.go('/kiosk/failed');
      }
    } catch (_) {
      _dotTimer?.cancel();
      if (mounted) {
        setState(() { _isScanning = false; _statusText = 'Position your face in the circle'; });
      }
    }
  }

  @override
  void dispose() {
    _autoCapture?.cancel();
    _dotTimer?.cancel();
    _camera?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) _camera?.dispose();
    if (state == AppLifecycleState.resumed)  _initCamera();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(fit: StackFit.expand, children: [
        if (_cameraReady && _camera != null)
          CameraPreview(_camera!)
        else
          const Center(child: CircularProgressIndicator(color: AppTheme.accent)),

        Positioned(
          top: 0, left: 0, right: 0, height: 160,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
              ),
            ),
          ),
        ),

        Positioned(
          top: 0, left: 0, right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('ATTENDANCE',
                      style: TextStyle(color: Colors.white, fontSize: 18,
                          fontWeight: FontWeight.w800, letterSpacing: 3)),
                  GestureDetector(
                    onTap: _showAdminDialog,
                    child: const Icon(Icons.settings, color: Colors.white54, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ),

        Center(
          child: CustomPaint(
            size: Size(size.width * 0.65, size.width * 0.65),
            painter: _FaceGuidePainter(scanning: _isScanning, color: AppTheme.accent),
          ),
        ),

        Positioned(
          bottom: 0, left: 0, right: 0, height: 200,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha: 0.85), Colors.transparent],
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isScanning)
                  const SizedBox(width: 32, height: 32,
                      child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 3))
                else
                  const Icon(Icons.face, color: AppTheme.accent, size: 36),
                const SizedBox(height: 12),
                Text(_statusText,
                    style: const TextStyle(color: Colors.white, fontSize: 18,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                const Text('Auto-detecting face…',
                    style: TextStyle(color: Colors.white54, fontSize: 13)),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  void _showAdminDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        title: const Text('Admin Access', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Admin PIN', hintText: 'Enter PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove(AppConstants.keyMode);
              if (mounted) context.go('/mode-select');
            },
            child: const Text('Switch Mode', style: TextStyle(color: Color(0xFF1565C0))),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (controller.text == '1234') context.go('/kiosk/admin');
            },
            child: const Text('Enter'),
          ),
        ],
      ),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  final bool  scanning;
  final Color color;
  const _FaceGuidePainter({required this.scanning, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    canvas.drawCircle(center, radius,
        Paint()
          ..color = scanning ? Colors.white : color
          ..style = PaintingStyle.stroke
          ..strokeWidth = scanning ? 3.5 : 2.5);
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const sweep = 0.4;
    for (var i = 0; i < 4; i++) {
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          (i * 3.14159 / 2) - 0.2, sweep, false, arcPaint);
    }
  }

  @override
  bool shouldRepaint(_FaceGuidePainter old) =>
      old.scanning != scanning || old.color != color;
}
