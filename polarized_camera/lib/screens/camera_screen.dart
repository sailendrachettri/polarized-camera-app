import 'dart:io';
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

class _CameraScreenState extends State<CameraScreen> with TickerProviderStateMixin {
  CameraController? _controller;
  bool _initialized = false;
  bool _capturing = false;
  CameraLensDirection _currentLens = CameraLensDirection.back;
  final List<File> _photos = [];
  late AnimationController _shutterAnimController;
  late AnimationController _processingAnimController;
  bool _isProcessing = false;
  FlashMode _flashMode = FlashMode.off;

  @override
  void initState() {
    super.initState();
    _shutterAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _processingAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
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
      await _controller?.dispose();

      final preset = ResolutionPreset.high;

      _controller = CameraController(
        camera,
        preset,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      await _controller!.setFlashMode(_flashMode);

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

  /// Toggle flash mode
  Future<void> _toggleFlash() async {
    if (_controller == null || !_initialized) return;

    try {
      FlashMode newMode;
      if (_flashMode == FlashMode.off) {
        newMode = FlashMode.always;
      } else if (_flashMode == FlashMode.always) {
        newMode = FlashMode.auto;
      } else {
        newMode = FlashMode.off;
      }

      await _controller!.setFlashMode(newMode);
      setState(() => _flashMode = newMode);
    } catch (e) {
      debugPrint('Flash toggle error: $e');
    }
  }

  /// Switch front/back camera safely
  Future<void> _switchCamera() async {
    if (_capturing || _isProcessing) return;

    final newLens = _currentLens == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;

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
    _shutterAnimController.dispose();
    _processingAnimController.dispose();
    super.dispose();
  }

  /// Take picture and apply polarization effect in background
  Future<void> _takePicture() async {
    if (_capturing || !_initialized || _controller == null) return;

    setState(() => _capturing = true);

    _shutterAnimController.forward().then((_) {
      _shutterAnimController.reverse();
    });

    try {
      final XFile picture = await _controller!.takePicture();

      setState(() {
        _capturing = false;
        _isProcessing = true;
      });

      _processImageInBackground(picture);
    } catch (e) {
      debugPrint('Capture error: $e');
      setState(() => _capturing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    }
  }

  /// Process image in background without freezing UI
  Future<void> _processImageInBackground(XFile picture) async {
    try {
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

      if (mounted) {
        setState(() {
          _photos.insert(0, polarizedImage);
          _isProcessing = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✨ Photo saved with polarization'),
            duration: Duration(milliseconds: 1200),
            backgroundColor: Colors.black87,
          ),
        );
      }
    } catch (e) {
      debugPrint('Processing error: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Processing failed: $e')),
        );
      }
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
        backgroundColor: Color(0xFFD5D5D5),
        body: Center(
          child: CircularProgressIndicator(
            color: Colors.black54,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final screenSize = MediaQuery.of(context).size;
    final cameraAspectRatio = _controller!.value.aspectRatio;
    
    // Calculate viewfinder size to match reference design
    final viewfinderWidth = screenSize.width * 0.70;
    final viewfinderHeight = viewfinderWidth * 1.4; // Portrait ratio like in reference

    return Scaffold(
      backgroundColor: const Color(0xFFD5D5D5), // Light gray background
      body: Stack(
        children: [
          // Main layout
          Column(
            children: [
              // Top section with brand label
              Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 20,
                ),
                child: Center(
                  child: Container(
                    width: 180,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A3A),
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Center(
                      child: Text(
                        'POLAROID',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Camera viewfinder with thick frame
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Main frame container
                    Container(
                      width: viewfinderWidth + 32,
                      height: viewfinderHeight + 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(32),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          // Textured overlay on frame
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(32),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white.withOpacity(0.1),
                                  Colors.transparent,
                                  Colors.black.withOpacity(0.2),
                                ],
                              ),
                            ),
                          ),
                          // Noise texture
                          CustomPaint(
                            size: Size(viewfinderWidth + 32, viewfinderHeight + 32),
                            painter: NoisePainter(),
                          ),
                        ],
                      ),
                    ),

                    // Camera preview
                    Container(
                      width: viewfinderWidth,
                      height: viewfinderHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: Colors.black,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: viewfinderWidth,
                            height: viewfinderWidth * cameraAspectRatio,
                            child: CameraPreview(_controller!),
                          ),
                        ),
                      ),
                    ),

                    // Processing overlay
                    if (_isProcessing)
                      Container(
                        width: viewfinderWidth,
                        height: viewfinderHeight,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.black.withOpacity(0.7),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            RotationTransition(
                              turns: _processingAnimController,
                              child: const Icon(
                                Icons.filter_vintage,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Applying Polarization...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              const Spacer(),

              // Controls area
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  children: [
                    // Flash and Gallery buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Flash toggle
                        GestureDetector(
                          onTap: _toggleFlash,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF4A4A4A),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              _flashMode == FlashMode.off
                                  ? Icons.flash_off
                                  : _flashMode == FlashMode.always
                                      ? Icons.flash_on
                                      : Icons.flash_auto,
                              color: const Color(0xFF2A2A2A),
                              size: 28,
                            ),
                          ),
                        ),

                        // Capture button
                        GestureDetector(
                          onTap: _capturing ? null : _takePicture,
                          child: AnimatedBuilder(
                            animation: _shutterAnimController,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: 1.0 - (_shutterAnimController.value * 0.1),
                                child: Container(
                                  width: 85,
                                  height: 85,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF2A2A2A),
                                      width: 3,
                                    ),
                                  ),
                                  child: _capturing
                                      ? const Center(
                                          child: SizedBox(
                                            width: 32,
                                            height: 32,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 3,
                                              color: Color(0xFF2A2A2A),
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              );
                            },
                          ),
                        ),

                        // Gallery button
                        GestureDetector(
                          onTap: _photos.isEmpty ? null : _openGallery,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF4A4A4A),
                                width: 2,
                              ),
                            ),
                            child: _photos.isEmpty
                                ? const Icon(
                                    Icons.photo_library,
                                    color: Color(0xFF2A2A2A),
                                    size: 28,
                                  )
                                : ClipOval(
                                    child: Image.file(
                                      _photos[0],
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Gallery and Camera switch toggle
                    Container(
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: const Color(0xFF4A4A4A),
                          width: 2,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Gallery icon
                          GestureDetector(
                            onTap: _photos.isEmpty ? null : _openGallery,
                            child: Container(
                              width: 70,
                              height: 50,
                              decoration: const BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: Color(0xFF4A4A4A),
                                    width: 1,
                                  ),
                                ),
                              ),
                              child: const Icon(
                                Icons.photo_library,
                                color: Color(0xFF2A2A2A),
                                size: 24,
                              ),
                            ),
                          ),
                          // Camera switch icon
                          GestureDetector(
                            onTap: (_capturing || _isProcessing) ? null : _switchCamera,
                            child: Container(
                              width: 70,
                              height: 50,
                              child: const Icon(
                                Icons.flip_camera_ios,
                                color: Color(0xFF2A2A2A),
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: MediaQuery.of(context).padding.bottom + 30),
            ],
          ),
        ],
      ),
    );
  }
}

// Painter for noise/grain texture on the frame
class NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.03)
      ..style = PaintingStyle.fill;

    // Create grain effect
    for (double i = 0; i < size.width; i += 2) {
      for (double j = 0; j < size.height; j += 2) {
        if ((i.toInt() + j.toInt()) % 4 == 0) {
          canvas.drawCircle(Offset(i, j), 0.5, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}