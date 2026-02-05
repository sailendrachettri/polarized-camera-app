import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'screens/camera_screen.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    cameras = await availableCameras();
    
    // ✅ Set app folder BEFORE initializing
    MediaStore.appFolder = "PolarizedCamera";
    
    // ✅ Then initialize
    await MediaStore.ensureInitialized();
    
  } catch (e) {
    debugPrint('Error initializing app: $e');
    cameras = [];
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Polarized Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.grey,
        scaffoldBackgroundColor: const Color(0xFFD5D5D5),
      ),
      home: const CameraScreen(),
    );
  }
}