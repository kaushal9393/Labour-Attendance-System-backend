import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';

class EmployeeRegistrationScreen extends StatefulWidget {
  final bool fromAdmin;
  const EmployeeRegistrationScreen({super.key, this.fromAdmin = false});

  @override
  State<EmployeeRegistrationScreen> createState() =>
      _EmployeeRegistrationScreenState();
}

class _EmployeeRegistrationScreenState
    extends State<EmployeeRegistrationScreen>
    with SingleTickerProviderStateMixin {
  // ── Form ────────────────────────────────────────────────────
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController();
  DateTime? _joiningDate;

  // ── Camera / capture ────────────────────────────────────────
  CameraController? _camera;
  bool _cameraReady   = false;
  bool _capturing     = false;
  bool _submitting    = false;
  final List<String> _photos = [];
  Timer? _autoTimer;

  // ── Animation for face ring ─────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── Step tracking: 0=photo, 1=details ──────────────────────
  int _step = 0;
  final _pageCtrl = PageController();

  static const int _totalPhotos = 25;

  // angle labels and photo boundaries
  static const List<String> _angleInstructions = [
    'Look straight at the camera',
    'Slowly turn your head LEFT',
    'Slowly turn your head RIGHT',
  ];
  static const List<int> _angleBoundaries = [9, 17, 25];

  int get _currentAngle {
    if (_photos.length < 9)  return 0;
    if (_photos.length < 17) return 1;
    return 2;
  }

  String get _angleLabel => ['FRONT', 'LEFT 30°', 'RIGHT 30°'][_currentAngle];

  bool get _allPhotosDone => _photos.length >= _totalPhotos;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _camera = CameraController(
        cam,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _camera!.initialize();
      if (!mounted) return;
      setState(() => _cameraReady = true);
      _startAutoCapture();
    } catch (_) {}
  }

  void _startAutoCapture() {
    _autoTimer?.cancel();
    // Capture one photo every 1.2 seconds automatically
    _autoTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!_capturing && _cameraReady && !_allPhotosDone) {
        _captureOne();
      }
    });
  }

  Future<void> _captureOne() async {
    if (_camera == null || _capturing || _allPhotosDone) return;
    setState(() => _capturing = true);
    try {
      final xFile = await _camera!.takePicture();
      final bytes = await xFile.readAsBytes();

      // Resize to 320×320 and compress to reduce payload size (~10KB per photo)
      final b64 = await _compressToBase64(bytes);

      if (!mounted) return;
      setState(() {
        _photos.add(b64);
        _capturing = false;
      });
      if (_allPhotosDone) {
        _autoTimer?.cancel();
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) _goToDetails();
      }
    } catch (_) {
      if (mounted) setState(() => _capturing = false);
    }
  }

  static Future<String> _compressToBase64(Uint8List bytes) async {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return base64Encode(bytes);
    final resized = img.copyResize(decoded, width: 320, height: 320);
    final compressed = img.encodeJpg(resized, quality: 75);
    return base64Encode(compressed);
  }

  void _goToDetails() {
    setState(() => _step = 1);
    _pageCtrl.animateToPage(1,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_joiningDate == null) {
      _showSnack('Please select a joining date');
      return;
    }
    setState(() => _submitting = true);
    try {
      await ApiService().registerEmployee({
        'name':           _nameCtrl.text.trim(),
        'phone':          _phoneCtrl.text.trim(),
        'monthly_salary': double.parse(_salaryCtrl.text.trim()),
        'joining_date':   DateFormat('yyyy-MM-dd').format(_joiningDate!),
        'photos':         _photos,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Employee registered successfully!'),
          backgroundColor: AppTheme.accent,
        ),
      );
      if (widget.fromAdmin) {
        context.pop();
      } else {
        context.go('/kiosk/admin');
      }
    } catch (e) {
      setState(() => _submitting = false);
      _showSnack('Registration failed: ${e.toString()}');
    }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppTheme.error),
      );

  @override
  void dispose() {
    _autoTimer?.cancel();
    _camera?.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _salaryCtrl.dispose();
    _pulseCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      appBar: AppBar(
        title: Text(_step == 0 ? 'Capture Face Photos' : 'Employee Details'),
        backgroundColor: AppTheme.surface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step == 1) {
              // Go back to photo step (re-enable auto-capture if needed)
              setState(() => _step = 0);
              _pageCtrl.animateToPage(0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut);
              if (!_allPhotosDone) _startAutoCapture();
            } else {
              if (widget.fromAdmin) {
                context.pop();
              } else {
                context.go('/kiosk/admin');
              }
            }
          },
        ),
      ),
      body: PageView(
        controller: _pageCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildPhotoStep(),
          _buildDetailsStep(),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────
  // Step 1: Face photo capture
  // ────────────────────────────────────────────────────────────
  Widget _buildPhotoStep() {
    final progress = _photos.length / _totalPhotos;
    final photosInAngle = _allPhotosDone
        ? 0
        : _angleBoundaries[_currentAngle] - _photos.length;

    return SingleChildScrollView(
      child: Column(children: [
        // Camera preview
        Container(
          color: Colors.black,
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(alignment: Alignment.center, children: [
              // Camera feed
              if (_cameraReady && !_allPhotosDone)
                ClipRect(child: CameraPreview(_camera!))
              else if (_allPhotosDone)
                Container(
                  color: AppTheme.success.withValues(alpha: 0.15),
                  child: const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle_rounded,
                          color: AppTheme.accent, size: 72),
                      SizedBox(height: 12),
                      Text('All photos captured!',
                          style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text('Moving to details…',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14)),
                    ]),
                  ),
                )
              else
                const Center(
                    child: CircularProgressIndicator(color: AppTheme.accent)),

              // Animated face ring
              if (!_allPhotosDone)
                ScaleTransition(
                  scale: _pulseAnim,
                  child: CustomPaint(
                    size: Size(
                      MediaQuery.of(context).size.width * 0.55,
                      MediaQuery.of(context).size.width * 0.55,
                    ),
                    painter: _FaceRingPainter(
                      progress: progress,
                      capturing: _capturing,
                    ),
                  ),
                ),

              // Angle badge top-left
              if (!_allPhotosDone)
                Positioned(
                  top: 12, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_angleLabel,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                ),

              // Photo count badge top-right
              if (!_allPhotosDone)
                Positioned(
                  top: 12, right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${_photos.length} / $_totalPhotos',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                ),

              // Capturing flash indicator
              if (_capturing)
                Positioned.fill(
                  child: Container(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
            ]),
          ),
        ),

        // Progress + instruction
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            // Progress bar with angle segments
            _AngleProgressBar(
              progress: progress,
              photoCount: _photos.length,
            ),
            const SizedBox(height: 16),

            // Instruction
            if (!_allPhotosDone) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.face, color: AppTheme.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('Auto-capturing…',
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(_angleInstructions[_currentAngle],
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                      if (_photos.length < _totalPhotos)
                        Text(
                            '${photosInAngle > 0 ? photosInAngle : 0} more for this angle',
                            style: const TextStyle(
                                color: AppTheme.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 12),

              // Angle steps
              Row(children: List.generate(3, (i) {
                final done = _photos.length >= _angleBoundaries[i];
                final active = _currentAngle == i;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: done
                          ? AppTheme.accent.withValues(alpha: 0.2)
                          : active
                              ? AppTheme.surface
                              : AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: done
                            ? AppTheme.accent
                            : active
                                ? AppTheme.accent.withValues(alpha: 0.5)
                                : AppTheme.divider,
                      ),
                    ),
                    child: Column(children: [
                      Icon(
                        done ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: done
                            ? AppTheme.accent
                            : active
                                ? AppTheme.accent
                                : AppTheme.textSecondary,
                        size: 18,
                      ),
                      const SizedBox(height: 4),
                      Text(['Front', 'Left', 'Right'][i],
                          style: TextStyle(
                              color: done || active
                                  ? AppTheme.textPrimary
                                  : AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: done || active
                                  ? FontWeight.w600
                                  : FontWeight.normal)),
                    ]),
                  ),
                );
              })),
            ],

            // Manual "proceed" button if somehow not all captured but user wants to retry
            if (_allPhotosDone) ...[
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _goToDetails,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue to Details'),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  // ────────────────────────────────────────────────────────────
  // Step 2: Employee details form
  // ────────────────────────────────────────────────────────────
  Widget _buildDetailsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Photos done summary
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
            ),
            child: const Row(children: [
              Icon(Icons.check_circle_rounded,
                  color: AppTheme.accent, size: 24),
              SizedBox(width: 10),
              Expanded(
                child: Text('25 face photos captured — great!',
                    style: TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // Name
          TextFormField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Full Name *',
              prefixIcon: Icon(Icons.person),
            ),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Name is required' : null,
          ),
          const SizedBox(height: 14),

          // Phone
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              prefixIcon: Icon(Icons.phone),
            ),
          ),
          const SizedBox(height: 14),

          // Salary
          TextFormField(
            controller: _salaryCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Monthly Salary (₹) *',
              prefixIcon: Icon(Icons.currency_rupee),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Salary is required';
              if (double.tryParse(v.trim()) == null) return 'Enter a valid number';
              return null;
            },
          ),
          const SizedBox(height: 14),

          // Joining date
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
                builder: (ctx, child) => Theme(
                  data: Theme.of(ctx).copyWith(
                    colorScheme: const ColorScheme.dark(
                        primary: AppTheme.accent,
                        surface: AppTheme.cardBg),
                  ),
                  child: child!,
                ),
              );
              if (picked != null) setState(() => _joiningDate = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today,
                    color: AppTheme.textSecondary, size: 20),
                const SizedBox(width: 12),
                Text(
                  _joiningDate != null
                      ? DateFormat('dd MMM yyyy').format(_joiningDate!)
                      : 'Joining Date *',
                  style: TextStyle(
                    color: _joiningDate != null
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                  ),
                ),
              ]),
            ),
          ),

          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            child: _submitting
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white)),
                      SizedBox(width: 12),
                      Text('Registering…'),
                    ],
                  )
                : const Text('Register Employee'),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}

// ── Face ring painter ──────────────────────────────────────────
class _FaceRingPainter extends CustomPainter {
  final double progress;
  final bool capturing;
  const _FaceRingPainter({required this.progress, required this.capturing});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background ring
    canvas.drawCircle(
      center, radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Progress arc (teal)
    final arcPaint = Paint()
      ..color = capturing ? Colors.white : AppTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708, // start at top
      progress * 6.2832,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_FaceRingPainter old) =>
      old.progress != progress || old.capturing != capturing;
}

// ── Angle progress bar ─────────────────────────────────────────
class _AngleProgressBar extends StatelessWidget {
  final double progress;
  final int photoCount;
  const _AngleProgressBar({required this.progress, required this.photoCount});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          backgroundColor: AppTheme.divider,
          valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
        ),
      ),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('$photoCount / 25 photos',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12)),
        Text('${(progress * 100).round()}%',
            style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ]),
    ]);
  }
}
