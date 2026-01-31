import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;

late List<CameraDescription> cameras;

Future<File> applyPolarizationEffect(
  File inputFile, {
  double intensity = 0.7,
}) async {
  final bytes = await inputFile.readAsBytes();
  img.Image? image = img.decodeImage(bytes);
  if (image == null) return inputFile;

  // Apply polarization effect
  for (int y = 0; y < image.height; y++) {
    for (int x = 0; x < image.width; x++) {
      final pixel = image.getPixel(x, y);
      int r = pixel.r.toInt();
      int g = pixel.g.toInt();
      int b = pixel.b.toInt();

      // Contrast boost
      r = (((r - 128) * (1 + intensity)) + 128).clamp(0, 255).toInt();
      g = (((g - 128) * (1 + intensity)) + 128).clamp(0, 255).toInt();
      b = (((b - 128) * (1 + intensity)) + 128).clamp(0, 255).toInt();

      // Blue enhancement (sky/water)
      b = (b * (1 + intensity * 0.6)).clamp(0, 255).toInt();

      // Highlight suppression (glare reduction)
      final brightness = (r + g + b) / 3;
      if (brightness > 200) {
        r = (r * (1 - intensity * 0.4)).toInt();
        g = (g * (1 - intensity * 0.4)).toInt();
        b = (b * (1 - intensity * 0.4)).toInt();
      }

      pixel
        ..r = r
        ..g = g
        ..b = b;
    }
  }

  // Add white rectangular frame
  final int frameThickness = 40; // Frame border thickness
  final int bottomExtraSpace = 120; // Extra space at bottom for polaroid effect
  
  // Create new image with frame
  final int newWidth = image.width + (frameThickness * 2);
  final int newHeight = image.height + (frameThickness * 2) + bottomExtraSpace;
  
  final img.Image framedImage = img.Image(
    width: newWidth,
    height: newHeight,
  );
  
  // Fill with white background
  img.fill(framedImage, color: img.ColorRgb8(255, 255, 255));
  
  // Copy the polarized image onto the white background
  img.compositeImage(
    framedImage,
    image,
    dstX: frameThickness,
    dstY: frameThickness,
  );

  final polarizedFile = File(
    inputFile.path.replaceFirst('.jpg', '_polarized.jpg'),
  );
  await polarizedFile.writeAsBytes(
    img.encodeJpg(framedImage, quality: 95),
  );
  return polarizedFile;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    debugPrint('Error getting cameras: $e');
    cameras = [];
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _initialized = false;
  bool _capturing = false;
  final List<File> _photos = [];

  @override
  void initState() {
    super.initState();
    _loadExistingPhotos();
    if (cameras.isEmpty) {
      debugPrint('No cameras found');
      return;
    }
    _controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );
    _controller!
        .initialize()
        .then((_) {
          if (!mounted) return;
          setState(() => _initialized = true);
        })
        .catchError((e) {
          debugPrint('Camera init error: $e');
        });
  }

  Future<void> _loadExistingPhotos() async {
    final Directory picturesDir = Directory(
      '/storage/emulated/0/Pictures/PolarizedCamera',
    );
    if (await picturesDir.exists()) {
      final List<FileSystemEntity> files = picturesDir.listSync();
      final List<File> imageFiles = files
          .whereType<File>()
          .where((f) => f.path.endsWith('_polarized.jpg'))
          .toList();
      
      // Sort by modification time (newest first)
      imageFiles.sort((a, b) => 
        b.lastModifiedSync().compareTo(a.lastModifiedSync())
      );
      
      setState(() {
        _photos.addAll(imageFiles);
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_capturing || !_initialized || _controller == null) return;

    setState(() => _capturing = true);

    try {
      final XFile picture = await _controller!.takePicture();
      final Directory picturesDir = Directory(
        '/storage/emulated/0/Pictures/PolarizedCamera',
      );
      if (!await picturesDir.exists()) {
        await picturesDir.create(recursive: true);
      }

      final String newPath = path.join(
        picturesDir.path,
        '${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final File rawImage = await File(picture.path).copy(newPath);

      // Apply polarization
      final File polarizedImage = await applyPolarizationEffect(
        rawImage,
        intensity: 0.7,
      );

      setState(() {
        _photos.insert(0, polarizedImage);
      });

      // Show success feedback
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
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _capturing = false);
    }
  }

  void _openGallery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GalleryScreen(photos: _photos),
      ),
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
          // Camera Preview
          Positioned.fill(
            child: CameraPreview(_controller!),
          ),

          // Frame Overlay Preview
          Positioned.fill(
            child: CustomPaint(
              painter: FrameOverlayPainter(),
            ),
          ),

          // Top Bar with Gallery Icon
          Positioned(
            top: 50,
            right: 20,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(30),
              ),
              child: IconButton(
                icon: Stack(
                  children: [
                    const Icon(
                      Icons.photo_library,
                      color: Colors.white,
                      size: 28,
                    ),
                    if (_photos.isNotEmpty)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${_photos.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: _photos.isEmpty ? null : _openGallery,
              ),
            ),
          ),

          // Bottom Preview Thumbnails
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
                itemBuilder: (context, index) {
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
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.file(
                          _photos[index],
                          fit: BoxFit.cover,
                        ),
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
                    color: _capturing ? Colors.grey : Colors.transparent,
                  ),
                  child: _capturing
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : Container(
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

          // Polarization Effect Label
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.filter_vintage,
                    color: Colors.blue,
                    size: 20,
                  ),
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

class GalleryScreen extends StatelessWidget {
  final List<File> photos;

  const GalleryScreen({super.key, required this.photos});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('Gallery (${photos.length})'),
        elevation: 0,
      ),
      body: photos.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 80,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No photos yet',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: photos.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FullPreviewScreen(
                          image: photos[index],
                          allPhotos: photos,
                          initialIndex: index,
                        ),
                      ),
                    );
                  },
                  child: Card(
                    elevation: 4,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          photos[index],
                          fit: BoxFit.cover,
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.3),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(
                              Icons.filter_vintage,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// Frame overlay painter to show the white frame preview on camera
class FrameOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    // Calculate frame dimensions
    final double frameMargin = 30;
    final double frameWidth = size.width - (frameMargin * 2);
    final double aspectRatio = 3 / 4; // Standard photo aspect ratio
    final double frameHeight = frameWidth * aspectRatio;
    
    // Extra space at bottom for polaroid effect
    final double bottomExtraSpace = frameHeight * 0.15;
    final double totalFrameHeight = frameHeight + bottomExtraSpace;
    
    // Center the frame vertically
    final double frameTop = (size.height - totalFrameHeight) / 2;
    final double frameLeft = frameMargin;

    // Draw outer rectangle (complete frame with bottom space)
    final outerRect = Rect.fromLTWH(
      frameLeft,
      frameTop,
      frameWidth,
      totalFrameHeight,
    );
    canvas.drawRect(outerRect, paint);

    // Draw inner line separating photo area from bottom white space
    final double separatorY = frameTop + frameHeight;
    canvas.drawLine(
      Offset(frameLeft, separatorY),
      Offset(frameLeft + frameWidth, separatorY),
      paint..strokeWidth = 1.5,
    );

    // Add corner decorations
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0;

    final double cornerLength = 20;

    // Top-left corner
    canvas.drawLine(
      Offset(frameLeft - 5, frameTop),
      Offset(frameLeft + cornerLength, frameTop),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameLeft, frameTop - 5),
      Offset(frameLeft, frameTop + cornerLength),
      cornerPaint,
    );

    // Top-right corner
    canvas.drawLine(
      Offset(frameLeft + frameWidth - cornerLength, frameTop),
      Offset(frameLeft + frameWidth + 5, frameTop),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameLeft + frameWidth, frameTop - 5),
      Offset(frameLeft + frameWidth, frameTop + cornerLength),
      cornerPaint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(frameLeft - 5, frameTop + totalFrameHeight),
      Offset(frameLeft + cornerLength, frameTop + totalFrameHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameLeft, frameTop + totalFrameHeight - cornerLength),
      Offset(frameLeft, frameTop + totalFrameHeight + 5),
      cornerPaint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(frameLeft + frameWidth - cornerLength, frameTop + totalFrameHeight),
      Offset(frameLeft + frameWidth + 5, frameTop + totalFrameHeight),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(frameLeft + frameWidth, frameTop + totalFrameHeight - cornerLength),
      Offset(frameLeft + frameWidth, frameTop + totalFrameHeight + 5),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FullPreviewScreen extends StatefulWidget {
  final File image;
  final List<File> allPhotos;
  final int initialIndex;

  const FullPreviewScreen({
    super.key,
    required this.image,
    required this.allPhotos,
    required this.initialIndex,
  });

  @override
  State<FullPreviewScreen> createState() => _FullPreviewScreenState();
}

class _FullPreviewScreenState extends State<FullPreviewScreen> {
  late PageController _pageController;
  late int _currentIndex;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _deletePhoto(File photo) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text('Delete Photo?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await photo.delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Photo deleted'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting photo: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          setState(() {
            _showControls = !_showControls;
          });
        },
        child: Stack(
          children: [
            // Image PageView
            PageView.builder(
              controller: _pageController,
              itemCount: widget.allPhotos.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              itemBuilder: (context, index) {
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: Image.file(
                      widget.allPhotos[index],
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),

            // Top Bar
            if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(16),
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
                                '${_currentIndex + 1}/${widget.allPhotos.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deletePhoto(widget.allPhotos[_currentIndex]),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Bottom Navigation Dots
            if (_showControls && widget.allPhotos.length > 1)
              Positioned(
                bottom: 30,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    widget.allPhotos.length,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentIndex == index ? 12 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentIndex == index
                            ? Colors.blue
                            : Colors.white.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}