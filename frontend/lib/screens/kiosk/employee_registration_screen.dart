import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
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
  final _formKey    = GlobalKey<FormState>();
  final _nameCtrl   = TextEditingController();
  final _phoneCtrl  = TextEditingController();
  final _salaryCtrl = TextEditingController();
  DateTime? _joiningDate;

  // ── Camera / capture ────────────────────────────────────────
  CameraController? _camera;
  bool _cameraReady = false;
  bool _capturing   = false;
  bool _submitting  = false;
  final List<String> _photos = [];
  Timer? _autoTimer;

  // ── Submission status ────────────────────────────────────────
  int _statusIndex = 0;
  Timer? _statusTimer;
  static const List<String> _statusMessages = [
    'Uploading photos...',
    'Analyzing face data...',
    'Saving employee profile...',
  ];

  // ── Pulse animation ──────────────────────────────────────────
  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  // ── Step: 0=photo, 1=details ─────────────────────────────────
  int _step = 0;
  final _pageCtrl = PageController();

  static const int _totalPhotos = 9;
  static const List<String> _angleInstructions = [
    'Look straight at the camera',
    'Slowly turn your head LEFT',
    'Slowly turn your head RIGHT',
  ];
  static const List<int> _angleBoundaries = [3, 6, 9];

  int get _currentAngle {
    if (_photos.length < 3) return 0;
    if (_photos.length < 6) return 1;
    return 2;
  }

  List<String> get _photosForApi {
    if (_photos.length < 9) return _photos;
    final front = _photos.sublist(0, 3);
    final left  = _photos.sublist(3, 6);
    final right = _photos.sublist(6, 9);
    return [
      ...List.generate(9, (i) => front[i % 3]),
      ...List.generate(8, (i) => left[i % 3]),
      ...List.generate(8, (i) => right[i % 3]),
    ];
  }

  String get _angleLabel => ['FRONT', 'LEFT 30°', 'RIGHT 30°'][_currentAngle];
  bool get _allPhotosDone => _photos.length >= _totalPhotos;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.97, end: 1.03)
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
      _camera = CameraController(cam, ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await _camera!.initialize();
      if (!mounted) return;
      setState(() => _cameraReady = true);
      _startAutoCapture();
    } catch (_) {}
  }

  void _startAutoCapture() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (!_capturing && _cameraReady && !_allPhotosDone) _captureOne();
    });
  }

  Future<void> _captureOne() async {
    if (_camera == null || _capturing || _allPhotosDone) return;
    setState(() => _capturing = true);
    HapticFeedback.lightImpact();
    try {
      final xFile = await _camera!.takePicture();
      final bytes = await xFile.readAsBytes();
      final b64   = await _compressToBase64(bytes);
      if (b64.length < 2000) {
        if (mounted) setState(() => _capturing = false);
        return;
      }
      if (!mounted) return;
      setState(() { _photos.add(b64); _capturing = false; });
      if (_allPhotosDone) {
        _autoTimer?.cancel();
        HapticFeedback.mediumImpact();
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
    return base64Encode(img.encodeJpg(resized, quality: 75));
  }

  void _goToDetails() {
    setState(() => _step = 1);
    _pageCtrl.animateToPage(1,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_joiningDate == null) { _showSnack('Please select a joining date'); return; }
    setState(() { _submitting = true; _statusIndex = 0; });
    _statusTimer?.cancel();
    _statusTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      setState(() => _statusIndex = (_statusIndex + 1) % _statusMessages.length);
    });
    try {
      await ApiService().registerEmployee({
        'name':           _nameCtrl.text.trim(),
        'phone':          _phoneCtrl.text.trim(),
        'monthly_salary': double.parse(_salaryCtrl.text.trim()),
        'joining_date':   DateFormat('yyyy-MM-dd').format(_joiningDate!),
        'photos':         _photosForApi,
      });
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Employee registered successfully!'),
            backgroundColor: AppTheme.accent),
      );
      if (widget.fromAdmin) { context.pop(); } else { context.go('/kiosk/admin'); }
    } catch (e) {
      if (mounted) { setState(() => _submitting = false); }
      String errorMsg = e.toString();
      if (e is DioException && e.response?.data != null) {
        final data = e.response!.data;
        if (data is Map) {
          final detail = data['detail'];
          errorMsg = detail is List
              ? detail.map((e) => e['msg'] ?? e.toString()).join(', ')
              : detail?.toString() ?? data['message']?.toString() ?? e.toString();
        }
      }
      _showSnack('Registration failed: $errorMsg');
    }
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating));

  @override
  void dispose() {
    _autoTimer?.cancel();
    _statusTimer?.cancel();
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
      backgroundColor: AppTheme.surface,
      appBar: AppBar(
        title: Text(_step == 0 ? 'Capture Face Photos' : 'Employee Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () {
            if (_step == 1) {
              setState(() => _step = 0);
              _pageCtrl.animateToPage(0,
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeInOut);
              if (!_allPhotosDone) _startAutoCapture();
            } else {
              if (widget.fromAdmin) { context.pop(); } else { context.go('/kiosk/admin'); }
            }
          },
        ),
      ),
      body: Stack(children: [
        PageView(
          controller: _pageCtrl,
          physics: const NeverScrollableScrollPhysics(),
          children: [_buildPhotoStep(), _buildDetailsStep()],
        ),
        if (_submitting) _buildSubmittingOverlay(),
      ]),
    );
  }

  // ── Submitting overlay ───────────────────────────────────────
  Widget _buildSubmittingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(
              width: 52, height: 52,
              child: CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Text(
                _statusMessages[_statusIndex],
                key: ValueKey(_statusIndex),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 10),
            const Text('This may take 15–20 seconds',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 4),
            const Text('Please do not close the app',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          ]),
        ),
      ),
    );
  }

  // ── Step 1: Face photo capture ───────────────────────────────
  Widget _buildPhotoStep() {
    final progress       = _photos.length / _totalPhotos;
    final photosInAngle  = _allPhotosDone ? 0 : _angleBoundaries[_currentAngle] - _photos.length;

    return SingleChildScrollView(
      child: Column(children: [
        // Camera box
        Container(
          color: Colors.black,
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Stack(alignment: Alignment.center, children: [
              // Camera feed or done state
              if (_cameraReady && !_allPhotosDone)
                ClipRect(child: CameraPreview(_camera!))
              else if (_allPhotosDone)
                Container(
                  color: AppTheme.accentLight,
                  child: const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.check_circle_rounded,
                          color: AppTheme.accent, size: 80),
                      SizedBox(height: 14),
                      Text('All photos captured!',
                          style: TextStyle(
                              color: AppTheme.accent,
                              fontSize: 22,
                              fontWeight: FontWeight.w800)),
                      SizedBox(height: 6),
                      Text('Moving to details…',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14)),
                    ]),
                  ),
                )
              else
                const Center(child: CircularProgressIndicator(color: AppTheme.accent)),

              // Animated face ring
              if (!_allPhotosDone)
                ScaleTransition(
                  scale: _pulseAnim,
                  child: CustomPaint(
                    size: Size(MediaQuery.of(context).size.width * 0.58,
                               MediaQuery.of(context).size.width * 0.58),
                    painter: _FaceRingPainter(
                        progress: progress, capturing: _capturing),
                  ),
                ),

              // Angle badge — top left
              if (!_allPhotosDone)
                Positioned(
                  top: 14, left: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_angleLabel,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),

              // Count badge — top right
              if (!_allPhotosDone)
                Positioned(
                  top: 14, right: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('${_photos.length} / $_totalPhotos',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),

              // Capture flash
              if (_capturing)
                Positioned.fill(
                  child: Container(color: Colors.white.withValues(alpha: 0.1)),
                ),
            ]),
          ),
        ),

        // Progress + instructions
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: AppTheme.divider,
                valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${_photos.length} / 9 photos',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              Text('${(progress * 100).round()}%',
                  style: const TextStyle(color: AppTheme.accent,
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 16),

            if (!_allPhotosDone) ...[
              // Instruction card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.cardBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.divider),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                        color: AppTheme.accentLight, shape: BoxShape.circle),
                    child: const Icon(Icons.face_retouching_natural,
                        color: AppTheme.accent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Auto-capturing…',
                          style: TextStyle(color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      const SizedBox(height: 3),
                      Text(_angleInstructions[_currentAngle],
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 13)),
                      if (photosInAngle > 0) ...[
                        const SizedBox(height: 3),
                        Text('$photosInAngle more for this angle',
                            style: const TextStyle(color: AppTheme.accent,
                                fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 14),

              // Angle steps
              Row(children: List.generate(3, (i) {
                final done   = _photos.length >= _angleBoundaries[i];
                final active = _currentAngle == i && !_allPhotosDone;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: i < 2 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: done ? AppTheme.accentLight
                           : active ? AppTheme.surface
                           : AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: done ? AppTheme.accent
                             : active ? AppTheme.accent.withValues(alpha: 0.4)
                             : AppTheme.divider,
                      ),
                    ),
                    child: Column(children: [
                      Icon(
                        done ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: done ? AppTheme.accent
                             : active ? AppTheme.accent
                             : AppTheme.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                      Text(['Front', 'Left', 'Right'][i],
                          style: TextStyle(
                              color: done || active
                                  ? AppTheme.textPrimary
                                  : AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: done || active
                                  ? FontWeight.w700
                                  : FontWeight.normal)),
                    ]),
                  ),
                );
              })),
            ],

            if (_allPhotosDone) ...[
              const SizedBox(height: 16),
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

  // ── Step 2: Employee details form ────────────────────────────
  Widget _buildDetailsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Success banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.accentLight,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.check_circle_rounded, color: AppTheme.accent, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text('9 face photos captured successfully!',
                    style: TextStyle(color: AppTheme.accent,
                        fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ]),
          ),
          const SizedBox(height: 24),

          // Section label
          const Text('Employee Information',
              style: TextStyle(color: AppTheme.textPrimary,
                  fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),

          // Form card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
              boxShadow: [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(children: [
              // Name
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Name is required' : null,
              ),
              const SizedBox(height: 14),

              // Phone
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 14),

              // Salary
              TextFormField(
                controller: _salaryCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppTheme.textPrimary),
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
                        colorScheme: const ColorScheme.light(
                            primary: AppTheme.accent,
                            surface: AppTheme.cardBg),
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) setState(() => _joiningDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _joiningDate != null
                            ? AppTheme.accent
                            : AppTheme.divider),
                  ),
                  child: Row(children: [
                    Icon(Icons.calendar_today,
                        color: _joiningDate != null
                            ? AppTheme.accent
                            : AppTheme.textSecondary,
                        size: 20),
                    const SizedBox(width: 12),
                    Text(
                      _joiningDate != null
                          ? DateFormat('dd MMM yyyy').format(_joiningDate!)
                          : 'Joining Date *',
                      style: TextStyle(
                        color: _joiningDate != null
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                    if (_joiningDate != null) ...[
                      const Spacer(),
                      const Icon(Icons.check_circle,
                          color: AppTheme.accent, size: 18),
                    ],
                  ]),
                ),
              ),
            ]),
          ),

          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 22, width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : const Text('Register Employee',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}

// ── Face ring painter ────────────────────────────────────────────
class _FaceRingPainter extends CustomPainter {
  final double progress;
  final bool   capturing;
  const _FaceRingPainter({required this.progress, required this.capturing});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Background ring
    canvas.drawCircle(center, radius,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);

    // Progress arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.5708,
      progress * 6.2832,
      false,
      Paint()
        ..color = capturing ? Colors.white : AppTheme.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_FaceRingPainter old) =>
      old.progress != progress || old.capturing != capturing;
}
