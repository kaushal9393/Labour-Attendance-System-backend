import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class OutsideWindowScreen extends StatefulWidget {
  final String employeeName;
  final String action; // check_in | check_out
  final String windowStart;
  final String windowEnd;

  const OutsideWindowScreen({
    super.key,
    required this.employeeName,
    required this.action,
    required this.windowStart,
    required this.windowEnd,
  });

  @override
  State<OutsideWindowScreen> createState() => _OutsideWindowScreenState();
}

class _OutsideWindowScreenState extends State<OutsideWindowScreen> {
  int _countdown = 4;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _countdown--);
      if (_countdown <= 0) {
        t.cancel();
        if (mounted) context.go('/kiosk/scan');
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _fmtNow() {
    final n = DateTime.now();
    final h12 = n.hour == 0 ? 12 : (n.hour > 12 ? n.hour - 12 : n.hour);
    final m = n.minute.toString().padLeft(2, '0');
    final p = n.hour >= 12 ? 'PM' : 'AM';
    return '$h12:$m $p';
  }

  String _fmtWindow(String t) {
    final parts = t.split(':');
    if (parts.length < 2) return t;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1].padLeft(2, '0');
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final p = h >= 12 ? 'PM' : 'AM';
    return '$h12:$m $p';
  }

  @override
  Widget build(BuildContext context) {
    final isCheckIn = widget.action == 'check_in';
    final label = isCheckIn ? 'Check-in time is' : 'Check-out time is';
    return Scaffold(
      backgroundColor: const Color(0xFFE67E22),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(Icons.access_time,
                      color: Colors.white, size: 72),
                ),
                const SizedBox(height: 28),
                Text('Hello, ${widget.employeeName}!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('You were recognized.',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
                const SizedBox(height: 28),
                Text(label,
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                    '${_fmtWindow(widget.windowStart)} – ${_fmtWindow(widget.windowEnd)}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                Text('Current time: ${_fmtNow()}',
                    style:
                        const TextStyle(color: Colors.white, fontSize: 15)),
                const SizedBox(height: 24),
                const Text(
                    'Please come back during\nthe allowed window.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white, fontSize: 15, height: 1.5)),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () => context.go('/kiosk/scan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFE67E22),
                    minimumSize: const Size(220, 50),
                  ),
                  child: Text('OK — auto-closes in $_countdown sec'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
