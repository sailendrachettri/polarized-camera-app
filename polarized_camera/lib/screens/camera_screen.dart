import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:path/path.dart' as path;
import 'package:audioplayers/audioplayers.dart';
import '../main.dart';
import '../utils/polarization_effect.dart';
import 'gallery_screen.dart';
import 'full_preview_screen.dart';
import 'dart:io';
import 'package:media_store_plus/media_store_plus.dart';
import '../utils/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with TickerProviderStateMixin {
  CameraController? _controller;
  bool _initialized = false;
  bool _capturing = false;
  CameraLensDirection _currentLens = CameraLensDirection.back;
  final List<File> _photos = [];
  late AnimationController _shutterAnimController;
  late AnimationController _processingAnimController;
  late AnimationController _flashAnimController;
  bool _isProcessing = false;
  FlashMode _flashMode = FlashMode.off;
  bool _isTorchOn = false;
  final AudioPlayer _audioPlayer = AudioPlayer();

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
    _flashAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _audioPlayer.setAudioContext(
      AudioContext(
        android: AudioContextAndroid(
          usageType: AndroidUsageType.media,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ),
    );

    _requestPermissions();
    _loadExistingPhotos();
    _initCamera();
  }

  bool cameraCaptureSoundEnable = false;
  bool printingPolarizedImageSound = false;

  /// ✅ Request storage permissions
  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final status = await Permission.photos.request();

      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission is required to save photos'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    }
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

      // Set initial flash mode
      if (_currentLens == CameraLensDirection.back) {
        await _controller!.setFlashMode(_flashMode);

        // Restore torch state if it was on
        if (_isTorchOn && _flashMode == FlashMode.torch) {
          await _controller!.setFlashMode(FlashMode.torch);
        }
      }

      if (!mounted) return;
      setState(() => _initialized = true);
    } catch (e) {
      debugPrint('Camera init failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to open camera')));
      }
    }
  }

  /// Toggle flash/torch mode
  Future<void> _toggleFlash() async {
    if (_controller == null || !_initialized) return;

    // Front camera doesn't support flash
    if (_currentLens == CameraLensDirection.front) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Flash not available on front camera'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    try {
      FlashMode newMode;
      bool newTorchState = false;

      if (_flashMode == FlashMode.off) {
        // Off -> Torch (always on)
        newMode = FlashMode.torch;
        newTorchState = true;
      } else if (_flashMode == FlashMode.torch) {
        // Torch -> Auto (flash on capture)
        newMode = FlashMode.auto;
        newTorchState = false;
      } else {
        // Auto -> Off
        newMode = FlashMode.off;
        newTorchState = false;
      }

      await _controller!.setFlashMode(newMode);
      setState(() {
        _flashMode = newMode;
        _isTorchOn = newTorchState;
      });
    } catch (e) {
      debugPrint('Flash toggle error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to toggle flash'),
          duration: Duration(seconds: 1),
        ),
      );
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

    // Turn off torch when switching cameras
    if (_isTorchOn && _controller != null) {
      try {
        await _controller!.setFlashMode(FlashMode.off);
      } catch (e) {
        debugPrint('Error turning off torch: $e');
      }
    }

    setState(() {
      _initialized = false;
      _currentLens = newLens;
      // Reset flash mode when switching to front camera
      if (newLens == CameraLensDirection.front) {
        _flashMode = FlashMode.off;
        _isTorchOn = false;
      }
    });

    await Future.delayed(const Duration(milliseconds: 200));
    await _initCamera();
  }

  /// Load previously captured polarized photos
  Future<void> _loadExistingPhotos() async {
    try {
      // ✅ Use GallerySaver to get saved photos
      final photos = await GallerySaver.getSavedPhotos();

      if (mounted) {
        setState(() {
          _photos.clear();
          _photos.addAll(photos);
        });
      }

      debugPrint('✅ Loaded ${photos.length} photos from gallery');
    } catch (e) {
      debugPrint('❌ Error loading existing photos: $e');
    }
  }

  /// Play camera shutter sound
  Future<void> _playShutterSound() async {
    try {
      if (cameraCaptureSoundEnable) {
        await _audioPlayer.play(AssetSource('sounds/click.mp3'));
        cameraCaptureSoundEnable = false;
        return;
      } else if (printingPolarizedImageSound) {
        await _audioPlayer.play(AssetSource('sounds/printing.mp3'));
        printingPolarizedImageSound = false;
        return;
      }
    } catch (e) {
      debugPrint('Error playing shutter sound: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _shutterAnimController.dispose();
    _processingAnimController.dispose();
    _flashAnimController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Take picture and apply polarization effect in background
  Future<void> _takePicture() async {
    if (_capturing || !_initialized || _controller == null) return;

    setState(() => _capturing = true);

    // Play shutter sound
    cameraCaptureSoundEnable = true;
    _playShutterSound();

    // Shutter animation
    _shutterAnimController.forward().then((_) {
      _shutterAnimController.reverse();
    });

    // Flash animation effect
    _flashAnimController.forward().then((_) {
      _flashAnimController.reverse();
    });

    try {
      // If using auto flash, temporarily set flash mode for this capture
      if (_flashMode == FlashMode.auto) {
        await _controller!.setFlashMode(FlashMode.always);
      }

      final XFile picture = await _controller!.takePicture();

      // Restore torch mode if it was on
      if (_isTorchOn) {
        await _controller!.setFlashMode(FlashMode.torch);
      } else if (_flashMode == FlashMode.auto) {
        await _controller!.setFlashMode(FlashMode.auto);
      }

      setState(() {
        _capturing = false;
        _isProcessing = true;
      });

      _processImageInBackground(picture);
    } catch (e) {
      debugPrint('Capture error: $e');
      setState(() => _capturing = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Capture failed: $e')));
      }
    }
  }

  /// Process image in background without freezing UI
  Future<void> _processImageInBackground(XFile picture) async {
    // Play shutter sound
    printingPolarizedImageSound = true;
    _playShutterSound();
    try {
      // ✅ Use temporary directory instead of Pictures
      final Directory tempDir = await getTemporaryDirectory();

      final String fileName =
          '${DateTime.now().millisecondsSinceEpoch}_polarized.jpg';
      final String tempPath = path.join(tempDir.path, fileName);

      // Copy camera image to temp directory
      final File rawImage = await File(picture.path).copy(tempPath);

      // Apply effect (MODIFIES the same file)
      final File polarizedImage = await PolarizationEffect.applyEffect(
        rawImage,
        intensity: 0.7,
      );

      if (!mounted) return;

      // ✅ Save to gallery (media_store_plus handles the actual gallery save)
      await GallerySaver.saveToPictures(polarizedImage, fileName: fileName);
      // await GallerySaver.saveToDownloads(polarizedImage, fileName: fileName);

      // Reload all photos from gallery to get the saved file
      final photos = await GallerySaver.getSavedPhotos();

      setState(() {
        _photos.clear();
        _photos.addAll(photos);
        _isProcessing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📸 Saved to Gallery'),
          duration: Duration(milliseconds: 1200),
        ),
      );
    } catch (e) {
      debugPrint('Processing error: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Processing failed: $e')));
      }
    }
  }

  void _openGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GalleryScreen(photos: _photos)),
    );
  }

  IconData _getFlashIcon() {
    if (_currentLens == CameraLensDirection.front) {
      return Icons.flash_off;
    }

    switch (_flashMode) {
      case FlashMode.off:
        return Icons.flash_off;
      case FlashMode.torch:
        return Icons.flash_on;
      case FlashMode.auto:
        return Icons.flash_auto;
      default:
        return Icons.flash_off;
    }
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

    final viewfinderWidth = screenSize.width * 0.70;
    final viewfinderHeight = viewfinderWidth * 1.4;

    return Scaffold(
      backgroundColor: const Color(0xFFD5D5D5),

      body: Stack(
        children: [
          // White flash overlay
          if (_flashAnimController.isAnimating)
            FadeTransition(
              opacity: Tween<double>(begin: 0.9, end: 0.0).animate(
                CurvedAnimation(
                  parent: _flashAnimController,
                  curve: Curves.easeOut,
                ),
              ),
              child: Container(color: Colors.white),
            ),

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
                        'NeoPolar Cam',
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
                            size: Size(
                              viewfinderWidth + 32,
                              viewfinderHeight + 32,
                            ),
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
                        color: Colors.grey.shade200,
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
                              color: _isTorchOn
                                  ? Colors.yellow.shade100
                                  : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _isTorchOn
                                    ? Colors.yellow.shade700
                                    : const Color(0xFF4A4A4A),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              _getFlashIcon(),
                              color: _isTorchOn
                                  ? Colors.yellow.shade800
                                  : const Color(0xFF2A2A2A),
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
                                scale:
                                    1.0 - (_shutterAnimController.value * 0.1),
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
                            onTap: (_capturing || _isProcessing)
                                ? null
                                : _switchCamera,
                            child: SizedBox(
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
