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

  // Apply polarization effect first
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

  // Resize image to be smaller - reduced width and height (65% of original)
  final int smallerWidth = (image.width * 0.65).toInt();
  final int smallerHeight = (image.height * 0.45).toInt(); // Even smaller height
  final img.Image resizedImage = img.copyResize(
    image,
    width: smallerWidth,
    height: smallerHeight,
    interpolation: img.Interpolation.linear,
  );

  // Modern Polaroid frame dimensions
  final int topBorder = 70;        // Top white border
  final int sideBorder = 70;       // Left and right white borders
  final int bottomBorder = 200;    // Large bottom border
  final int cornerRadius = 35;     // Rounded corners
  final int outerMargin = 50;      // Margin around the entire frame
  
  // Calculate frame dimensions (without outer margin)
  final int frameWidth = resizedImage.width + (sideBorder * 2);
  final int frameHeight = resizedImage.height + topBorder + bottomBorder;
  
  // Create new image with frame + outer margin
  final int totalWidth = frameWidth + (outerMargin * 2);
  final int totalHeight = frameHeight + (outerMargin * 2);
  
  final img.Image framedImage = img.Image(
    width: totalWidth,
    height: totalHeight,
  );
  
  // Fill entire image with black background (for outer margin)
  img.fill(framedImage, color: img.ColorRgb8(0, 0, 0));
  
  // Fill the frame area with white
  for (int y = outerMargin; y < outerMargin + frameHeight; y++) {
    for (int x = outerMargin; x < outerMargin + frameWidth; x++) {
      framedImage.setPixel(x, y, img.ColorRgb8(255, 255, 255));
    }
  }
  
  // Apply rounded corners to the white frame
  for (int y = outerMargin; y < outerMargin + frameHeight; y++) {
    for (int x = outerMargin; x < outerMargin + frameWidth; x++) {
      bool isCorner = false;
      int dx = 0, dy = 0;
      
      // Calculate position relative to frame
      final int frameX = x - outerMargin;
      final int frameY = y - outerMargin;
      
      // Top-left corner
      if (frameX < cornerRadius && frameY < cornerRadius) {
        dx = cornerRadius - frameX;
        dy = cornerRadius - frameY;
        isCorner = true;
      }
      // Top-right corner
      else if (frameX >= frameWidth - cornerRadius && frameY < cornerRadius) {
        dx = frameX - (frameWidth - cornerRadius - 1);
        dy = cornerRadius - frameY;
        isCorner = true;
      }
      // Bottom-left corner
      else if (frameX < cornerRadius && frameY >= frameHeight - cornerRadius) {
        dx = cornerRadius - frameX;
        dy = frameY - (frameHeight - cornerRadius - 1);
        isCorner = true;
      }
      // Bottom-right corner
      else if (frameX >= frameWidth - cornerRadius && frameY >= frameHeight - cornerRadius) {
        dx = frameX - (frameWidth - cornerRadius - 1);
        dy = frameY - (frameHeight - cornerRadius - 1);
        isCorner = true;
      }
      
      // If in corner area, check if outside radius
      if (isCorner) {
        final int distance = (dx * dx + dy * dy);
        if (distance > cornerRadius * cornerRadius) {
          // Make black (part of outer margin)
          framedImage.setPixel(x, y, img.ColorRgb8(0, 0, 0));
        }
      }
    }
  }
  
  // Calculate photo position (accounting for outer margin)
  final int photoTop = outerMargin + topBorder;
  final int photoLeft = outerMargin + sideBorder;
  final int photoWidth = resizedImage.width;
  final int photoHeight = resizedImage.height;
  
  // Add subtle shadow/depth to the inner photo area
  final int shadowSize = 3;
  for (int i = 0; i < shadowSize; i++) {
    final int shadowAlpha = (150 * (shadowSize - i) / shadowSize).toInt();
    
    // Top shadow
    for (int x = photoLeft; x < photoLeft + photoWidth; x++) {
      framedImage.setPixel(
        x,
        photoTop + i,
        img.ColorRgb8(shadowAlpha, shadowAlpha, shadowAlpha),
      );
    }
    
    // Left shadow
    for (int y = photoTop; y < photoTop + photoHeight; y++) {
      framedImage.setPixel(
        photoLeft + i,
        y,
        img.ColorRgb8(shadowAlpha, shadowAlpha, shadowAlpha),
      );
    }
    
    // Right shadow
    for (int y = photoTop; y < photoTop + photoHeight; y++) {
      framedImage.setPixel(
        photoLeft + photoWidth - 1 - i,
        y,
        img.ColorRgb8(shadowAlpha, shadowAlpha, shadowAlpha),
      );
    }
    
    // Bottom shadow
    for (int x = photoLeft; x < photoLeft + photoWidth; x++) {
      framedImage.setPixel(
        x,
        photoTop + photoHeight - 1 - i,
        img.ColorRgb8(shadowAlpha, shadowAlpha, shadowAlpha),
      );
    }
  }
  
  // Copy the polarized image onto the white background
  img.compositeImage(
    framedImage,
    resizedImage,
    dstX: photoLeft,
    dstY: photoTop,
  );
  
  // Add a subtle dark border around the photo
  final int borderThickness = 2;
  for (int i = 0; i < borderThickness; i++) {
    // Top border
    for (int x = photoLeft - i; x < photoLeft + photoWidth + i; x++) {
      if (x >= 0 && x < totalWidth) {
        framedImage.setPixel(x, photoTop - 1 - i, img.ColorRgb8(180, 180, 180));
      }
    }
    // Bottom border
    for (int x = photoLeft - i; x < photoLeft + photoWidth + i; x++) {
      if (x >= 0 && x < totalWidth) {
        framedImage.setPixel(x, photoTop + photoHeight + i, img.ColorRgb8(180, 180, 180));
      }
    }
    // Left border
    for (int y = photoTop - i; y < photoTop + photoHeight + i; y++) {
      if (y >= 0 && y < totalHeight) {
        framedImage.setPixel(photoLeft - 1 - i, y, img.ColorRgb8(180, 180, 180));
      }
    }
    // Right border
    for (int y = photoTop - i; y < photoTop + photoHeight + i; y++) {
      if (y >= 0 && y < totalHeight) {
        framedImage.setPixel(photoLeft + photoWidth + i, y, img.ColorRgb8(180, 180, 180));
      }
    }
  }

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