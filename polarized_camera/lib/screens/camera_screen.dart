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
  late AnimationController _flashAnimController;
  bool _showFlash = false;

  @override
  void initState() {
    super.initState();
    _shutterAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _flashAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
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

      final preset = ResolutionPreset.high;

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
    _shutterAnimController.dispose();
    _flashAnimController.dispose();
    super.dispose();
  }

  /// Take picture and apply polarization effect
  Future<void> _takePicture() async {
    if (_capturing || !_initialized || _controller == null) return;

    setState(() => _capturing = true);

    // Shutter animation
    _shutterAnimController.forward().then((_) {
      _shutterAnimController.reverse();
    });

    // Flash effect
    setState(() => _showFlash = true);
    _flashAnimController.forward().then((_) {
      _flashAnimController.reverse();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) setState(() => _showFlash = false);
      });
    });

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
            content: Text('📸 Saved'),
            duration: Duration(milliseconds: 800),
            backgroundColor: Colors.black87,
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
        body: Center(
          child: CircularProgressIndicator(
            color: Colors.white70,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final deviceRatio = size.width / size.height;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera Preview - FIXED: No mirroring for front camera
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: size.width,
                height: size.width * _controller!.value.aspectRatio,
                child: CameraPreview(_controller!),
              ),
            ),
          ),

          // Flash overlay
          if (_showFlash)
            Positioned.fill(
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.8, end: 0.0).animate(
                  CurvedAnimation(
                    parent: _flashAnimController,
                    curve: Curves.easeOut,
                  ),
                ),
                child: Container(color: Colors.white),
              ),
            ),

          // Top bar with vintage film camera aesthetic
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 12,
                bottom: 16,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.7),
                    Colors.black.withOpacity(0.0),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Film counter style badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.filter_vintage,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'POLAROID',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Gallery button
                  GestureDetector(
                    onTap: _photos.isEmpty ? null : _openGallery,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _photos.isEmpty
                            ? Colors.white.withOpacity(0.1)
                            : Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: _photos.isEmpty
                          ? Icon(
                              Icons.photo_library_outlined,
                              color: Colors.white.withOpacity(0.5),
                              size: 22,
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.file(
                                _photos[0],
                                fit: BoxFit.cover,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom control bar with film camera aesthetic
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                top: 30,
                left: 20,
                right: 20,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.black.withOpacity(0.0),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Camera mode indicator
                  Container(
                    width: 50,
                    height: 50,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _currentLens == CameraLensDirection.back
                              ? Icons.camera_rear
                              : Icons.camera_front,
                          color: Colors.white.withOpacity(0.6),
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.6),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Capture button - vintage shutter style
                  GestureDetector(
                    onTap: _capturing ? null : _takePicture,
                    child: AnimatedBuilder(
                      animation: _shutterAnimController,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: 1.0 - (_shutterAnimController.value * 0.15),
                          child: Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Container(
                              margin: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _capturing
                                    ? Colors.white.withOpacity(0.7)
                                    : Colors.white,
                              ),
                              child: _capturing
                                  ? const Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Camera switch button
                  GestureDetector(
                    onTap: _capturing ? null : _switchCamera,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.flip_camera_ios_outlined,
                        color: Colors.white.withOpacity(0.9),
                        size: 26,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Film frame corners (vintage aesthetic touch)
          ..._buildFilmFrameCorners(),

          // Photo counter
          if (_photos.isNotEmpty)
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 90,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${_photos.length}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildFilmFrameCorners() {
    const cornerSize = 20.0;
    const cornerThickness = 2.0;
    const margin = 16.0;

    Widget buildCorner({
      required Alignment alignment,
      required bool showTop,
      required bool showLeft,
    }) {
      return Align(
        alignment: alignment,
        child: Container(
          margin: EdgeInsets.only(
            top: alignment.y < 0 ? margin + MediaQuery.of(context).padding.top : margin,
            bottom: alignment.y > 0 ? margin + MediaQuery.of(context).padding.bottom : margin,
            left: alignment.x < 0 ? margin : 0,
            right: alignment.x > 0 ? margin : 0,
          ),
          width: cornerSize,
          height: cornerSize,
          child: CustomPaint(
            painter: CornerPainter(
              showTop: showTop,
              showLeft: showLeft,
              color: Colors.white.withOpacity(0.3),
              thickness: cornerThickness,
            ),
          ),
        ),
      );
    }

    return [
      buildCorner(alignment: Alignment.topLeft, showTop: true, showLeft: true),
      buildCorner(alignment: Alignment.topRight, showTop: true, showLeft: false),
      buildCorner(alignment: Alignment.bottomLeft, showTop: false, showLeft: true),
      buildCorner(alignment: Alignment.bottomRight, showTop: false, showLeft: false),
    ];
  }
}

class CornerPainter extends CustomPainter {
  final bool showTop;
  final bool showLeft;
  final Color color;
  final double thickness;

  CornerPainter({
    required this.showTop,
    required this.showLeft,
    required this.color,
    required this.thickness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke;

    final path = Path();

    if (showTop && showLeft) {
      // Top-left corner
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (showTop && !showLeft) {
      // Top-right corner
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (!showTop && showLeft) {
      // Bottom-left corner
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else {
      // Bottom-right corner
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}