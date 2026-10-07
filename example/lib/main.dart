import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:face_gesture_detector/face_gesture_detector.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Gesture Detector Demo',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const FaceDetectorDemo(),
    );
  }
}

class FaceDetectorDemo extends StatefulWidget {
  const FaceDetectorDemo({super.key});

  @override
  State<FaceDetectorDemo> createState() => _FaceDetectorDemoState();
}

class _FaceDetectorDemoState extends State<FaceDetectorDemo>
    with WidgetsBindingObserver {
  final _gestureController = FaceGestureDetectorController();
  final _events = <String>[];

  CameraController? _cameraController;
  bool _hasFace = false;
  bool _isPaused = false;
  String? _error;

  // ── Capture state ──────────────────────────────────────────
  bool _autoCapture = false;
  bool _capturing = false;
  List<CaptureBlockReason> _blockReasons = const [CaptureBlockReason.noFace];
  ImageQualityMetrics? _liveQuality;
  CapturedPhoto? _lastPhoto;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _gestureController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _cameraController;
    if (camera == null || !camera.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      camera.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      // `high` (720p) keeps the analysis stream fluid while giving the
      // sharpness metric enough detail; takePicture() always uses the
      // full sensor resolution regardless of this preset.
      final controller = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  void _addEvent(String event) {
    final entry =
        '${DateTime.now().toIso8601String().substring(11, 19)} $event';
    debugPrint('[FaceGesture] $entry');
    setState(() {
      _events.insert(0, entry);
      if (_events.length > 50) _events.removeLast();
    });
  }

  Future<void> _capture() async {
    if (_capturing || !_gestureController.isAttached) return;
    setState(() => _capturing = true);
    final started = DateTime.now();
    try {
      final photo = await _gestureController.capturePhoto(
        options: const CaptureOptions(
          cropToFace: true,
          marginFactor: 0.6,
          aspectRatio: 0.75,
          targetShortSide: 1080,
        ),
      );
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      _addEvent(
        'Captured ${photo.width}×${photo.height} in ${elapsed}ms '
        '(b=${photo.quality.brightness.toStringAsFixed(2)} '
        's=${photo.quality.sharpness.toStringAsFixed(0)} '
        'crop=${photo.cropApplied})',
      );
      setState(() => _lastPhoto = photo);
    } catch (e) {
      _addEvent('Capture failed: $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Gesture Detector'),
        actions: [
          IconButton(
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
            onPressed: () {
              setState(() {
                _isPaused = !_isPaused;
                _isPaused
                    ? _gestureController.pause()
                    : _gestureController.resume();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _gestureController.reset();
              setState(() => _events.clear());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(flex: 3, child: _buildCameraArea()),
          _buildCaptureBar(),
          Expanded(flex: 2, child: _buildEventLog()),
        ],
      ),
    );
  }

  Widget _buildCameraArea() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Camera error: $_error',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    final camera = _cameraController;
    if (camera == null || !camera.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return FaceGestureDetector(
      configuration: FaceGestureConfiguration(),
      cameraController: camera,
      controller: _gestureController,
      onFaceDetected: (details) {
        if (!_hasFace) {
          _hasFace = true;
          _addEvent('Face detected (${(details.confidence * 100).toInt()}%)');
        }
      },
      onFaceLost: () {
        _hasFace = false;
        _addEvent('Face lost');
      },
      onBlinkDetected: (details) =>
          _addEvent('Blink (${details.blinkDuration.inMilliseconds}ms)'),
      onSmileDetected: (details) => _addEvent(
        'Smile (intensity: ${details.intensity.toStringAsFixed(2)})',
      ),
      onHeadTurnDetected: (details) => _addEvent(
        'Head turn ${details.direction.name} (yaw=${details.yawAngle.toStringAsFixed(1)})',
      ),
      onHeadNodDetected: (details) => _addEvent(
        'Head nod ${details.direction.name} (pitch=${details.pitchAngle.toStringAsFixed(1)})',
      ),
      onBrowRaised: (details) =>
          _addEvent('Brow raised (${details.intensity.toStringAsFixed(2)})'),
      onMouthOpened: (details) =>
          _addEvent('Mouth open (${details.openness.toStringAsFixed(2)})'),
      onDistanceChanged: (details) =>
          _addEvent('Distance: ${details.category.name}'),
      onQualityChanged: (details) {
        // Live metrics for the status bar (no event log entry — too noisy).
        setState(() => _liveQuality = details.metrics);
      },
      onCaptureBlocked: (details) {
        setState(() => _blockReasons = details.reasons);
        _addEvent(
          details.isClear
              ? 'Capture gates clear — hold still'
              : 'Capture blocked: ${details.reasons.map((r) => r.name).join(', ')}',
        );
      },
      onCaptureReady: (details) {
        _addEvent(
          'Capture ready (held ${details.sustainedFor.inMilliseconds}ms)',
        );
        if (_autoCapture) _capture();
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(camera),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: _buildGateOverlay(),
          ),
        ],
      ),
    );
  }

  Widget _buildGateOverlay() {
    final q = _liveQuality;
    final clear = _blockReasons.isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            clear
                ? 'Ready — hold still'
                : _blockReasons.map((r) => r.name).join(' · '),
            style: TextStyle(
              color: clear ? Colors.greenAccent : Colors.orangeAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (q != null)
            Text(
              'brightness ${q.brightness.toStringAsFixed(2)} · '
              'sharpness ${q.sharpness.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildCaptureBar() {
    final photo = _lastPhoto;
    return Material(
      color: Colors.grey.shade200,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            FilledButton.icon(
              onPressed: _capturing || _cameraController == null
                  ? null
                  : _capture,
              icon: _capturing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.camera_alt),
              label: const Text('Capture'),
            ),
            const SizedBox(width: 12),
            const Text('Auto'),
            Switch(
              value: _autoCapture,
              onChanged: (v) => setState(() => _autoCapture = v),
            ),
            const Spacer(),
            if (photo != null) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${photo.width}×${photo.height}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    'b=${photo.quality.brightness.toStringAsFixed(2)} '
                    's=${photo.quality.sharpness.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(photo.path),
                  key: ValueKey(photo.path),
                  width: 48,
                  height: 64,
                  fit: BoxFit.cover,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEventLog() {
    return Container(
      color: Colors.grey.shade100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Text(
                  'Event Log',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                if (_hasFace)
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _events.isEmpty
                ? const Center(child: Text('Waiting for events...'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _events.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        _events[index],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
