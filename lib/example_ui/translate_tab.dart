// translate_tab.dart
// Demonstrates the core pipeline: start a session, stream simulated gestures
// (each writes a gestureReading + a realtimeMessage), then end the session and
// see the computed aggregates (duration, totalGestures, averageConfidence).

import 'dart:math';

import 'package:flutter/material.dart';

import '../backend/backend.dart';

class TranslateTab extends StatefulWidget {
  final GloveBackend backend;
  final String uid;
  const TranslateTab({super.key, required this.backend, required this.uid});

  @override
  State<TranslateTab> createState() => _TranslateTabState();
}

class _TranslateTabState extends State<TranslateTab> {
  static const _words = ['سلام', 'كيف', 'حالك', 'شكراً', 'نعم', 'لا', 'من فضلك'];
  final _rnd = Random();

  TranslationSession? _session;
  String? _deviceId;
  bool _busy = false;

  Future<void> _start(List<GloveDevice> devices) async {
    final device = devices.firstWhere(
      (d) => d.deviceId == _deviceId,
      orElse: () => devices.first,
    );
    setState(() => _busy = true);
    final session = await widget.backend.startTranslation(
      deviceId: device.deviceId,
      deviceName: device.deviceName,
    );
    setState(() {
      _session = session;
      _busy = false;
    });
  }

  Future<void> _simulateGesture() async {
    final s = _session;
    if (s == null) return;
    await widget.backend.recordGesture(
      sessionId: s.sessionId,
      deviceId: s.deviceId,
      rawSensorData: {
        'flex': List.generate(5, (_) => _rnd.nextInt(1024)),
      },
      detectedGesture: _words[_rnd.nextInt(_words.length)],
      confidenceScore: 0.7 + _rnd.nextDouble() * 0.29,
    );
  }

  Future<void> _end() async {
    final s = _session;
    if (s == null) return;
    setState(() => _busy = true);
    final done = await widget.backend.endTranslation(s.sessionId);
    setState(() {
      _session = null;
      _busy = false;
    });
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Session complete'),
        content: Text(
          'Transcript: ${done.translatedText}\n\n'
          'Duration: ${done.durationLabel}\n'
          'Gestures: ${done.totalGestures}\n'
          'Avg. confidence: ${(done.averageConfidence * 100).toStringAsFixed(0)}%',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<GloveDevice>>(
      stream: widget.backend.devices.watchUserDevices(widget.uid),
      builder: (context, snap) {
        final devices = snap.data ?? [];
        if (devices.isEmpty) {
          return const Center(child: Text('Add a glove first (Gloves tab).'));
        }
        _deviceId ??= devices.first.deviceId;

        return Column(
          children: [
            if (_session == null) _picker(devices) else _liveFeed(),
            _controls(devices),
          ],
        );
      },
    );
  }

  Widget _picker(List<GloveDevice> devices) => Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.translate, size: 56),
                const SizedBox(height: 12),
                const Text('Pick a glove and start translating.'),
                const SizedBox(height: 16),
                DropdownButton<String>(
                  value: _deviceId,
                  items: devices
                      .map((d) => DropdownMenuItem(
                          value: d.deviceId, child: Text(d.deviceName)))
                      .toList(),
                  onChanged: (v) => setState(() => _deviceId = v),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _liveFeed() => Expanded(
        child: StreamBuilder<List<RealtimeMessage>>(
          stream: widget.backend.messages.watchSessionMessages(_session!.sessionId),
          builder: (context, snap) {
            final msgs = snap.data ?? [];
            if (msgs.isEmpty) {
              return const Center(child: Text('Sign something on the glove…'));
            }
            return ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: msgs.length,
              itemBuilder: (_, i) => Align(
                alignment: Alignment.centerRight,
                child: Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(msgs[i].translatedText,
                        style: const TextStyle(fontSize: 20)),
                  ),
                ),
              ),
            );
          },
        ),
      );

  Widget _controls(List<GloveDevice> devices) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _session == null
              ? FilledButton.icon(
                  onPressed: _busy ? null : () => _start(devices),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start session'),
                )
              : Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _busy ? null : _simulateGesture,
                        icon: const Icon(Icons.add),
                        label: const Text('Gesture'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _end,
                        icon: const Icon(Icons.stop),
                        label: const Text('End'),
                      ),
                    ),
                  ],
                ),
        ),
      );
}
