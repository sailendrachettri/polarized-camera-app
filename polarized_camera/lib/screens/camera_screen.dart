import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path/path.dart' as path;
import '../main.dart';
import '../utils/polarization_effect.dart';
import 'gallery_screen.dart';
import 'full_preview_screen.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _initialized = false;
  bool _capturing = false;
  CameraLensDirection _currentLens = CameraLensDirection.back;
  final List<File> _photos = [];

  @override
  void initState() {
    super.initState();
    _loadExistingPhotos();
    _initCamera();
  }

  /// Get camera safely by lens direction
  CameraDescription? _getCamera(CameraLensDirection direction) {
    try {
      return cameras.firstWhere((cam) => cam.lensDirection == direction);
    } catch (e) {
      return null;
    }
  }

  /// Initialize camera with safe resolution & format
  Future<void> _initCamera() async {
    final camera = _getCamera(_currentLens);
    if (camera == null) {
      debugPrint('Camera not available: $_currentLens');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera $_currentLens not available')),
        );
      }
      return;
    }

    try {
      // Dispose old controller safely
      await _controller?.dispose();

      // Use low resolution for front camera, high for back
      final preset = _currentLens == CameraLensDirection.front
          ? ResolutionPreset.low
          : ResolutionPreset.high;

      _controller = CameraController(
        camera,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();

      if (!mounted) return;
      setState(() => _initialized = true);
    } catch (e) {
      debugPrint('Camera init failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to open camera')),
        );
      }
    }
  }

  /// Switch front/back camera safely
  Future<void> _switchCamera() async {
    if (_capturing) return;

    final newLens = _currentLens == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    // Check if camera exists
    if (_getCamera(newLens) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This camera is not available')),
      );
      return;
    }

    setState(() {
      _initialized = false;
      _currentLens = newLens;
    });

    // Small delay to ensure controller disposal
    await Future.delayed(const Duration(milliseconds: 200));
    await _initCamera();
  }

  /// Load previously captured polarized photos
  Future<void> _loadExistingPhotos() async {
    final Directory picturesDir =
        Directory('/storage/emulated/0/Pictures/PolarizedCamera');

    if (await picturesDir.exists()) {
      final files = picturesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_polarized.jpg'))
          .toList();

      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );

      setState(() {
        _photos.addAll(files);
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Take picture and apply polarization effect
  Future<void> _takePicture() async {
    if (_capturing || !_initialized || _controller == null) return;

    setState(() => _capturing = true);

    try {
      final XFile picture = await _controller!.takePicture();

      final Directory picturesDir =
          Directory('/storage/emulated/0/Pictures/PolarizedCamera');
      if (!await picturesDir.exists()) {
        await picturesDir.create(recursive: true);
      }

      final String newPath = path.join(
        picturesDir.path,
        '${DateTime.now().millisecondsSinceEpoch}_polarized.jpg',
      );

      final File rawImage = await File(picture.path).copy(newPath);

      final File polarizedImage =
          await PolarizationEffect.applyEffect(rawImage, intensity: 0.7);

      setState(() {
        _photos.insert(0, polarizedImage);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo captured with polarization effect!'),
            duration: Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    } finally {
      setState(() => _capturing = false);
    }
  }

  void _openGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GalleryScreen(photos: _photos)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized || _controller == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview with front camera mirroring
          Positioned.fill(
            child: Transform(
              alignment: Alignment.center,
              transform: _currentLens == CameraLensDirection.front
                  ? Matrix4.rotationY(math.pi)
                  : Matrix4.identity(),
              child: CameraPreview(_controller!),
            ),
          ),

          // Gallery Icon
          Positioned(
            top: 50,
            right: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(30),
              ),
              child: IconButton(
                icon: const Icon(
                  Icons.photo_library,
                  color: Colors.white,
                  size: 28,
                ),
                onPressed: _photos.isEmpty ? null : _openGallery,
              ),
            ),
          ),

          // Bottom thumbnails
          if (_photos.isNotEmpty)
            Positioned(
              bottom: 120,
              left: 0,
              right: 0,
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _photos.length > 5 ? 5 : _photos.length,
                itemBuilder: (_, index) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FullPreviewScreen(
                            image: _photos[index],
                            allPhotos: _photos,
                            initialIndex: index,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      width: 70,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(_photos[index], fit: BoxFit.cover),
                      ),
                    ),
                  );
                },
              ),
            ),

          // Capture Button
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _takePicture,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 5),
                  ),
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Camera Switch Button
          Positioned(
            bottom: 40,
            right: 30,
            child: GestureDetector(
              onTap: _switchCamera,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.cameraswitch,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),

          // Polarization Label
          Positioned(
            top: 50,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.filter_vintage, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Polarized',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
