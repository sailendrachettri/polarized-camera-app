import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:media_store_plus/media_store_plus.dart';

class GallerySaver {
  static final MediaStore _mediaStore = MediaStore();

  /// Save image to Pictures (Gallery)
  static Future<void> saveToPictures(File imageFile, {String? fileName}) async {
    try {
      final String finalFileName = fileName ?? 
          '${DateTime.now().millisecondsSinceEpoch}_polarized.jpg';
      
      // ✅ Save to MediaStore with proper error handling
      final savedUri = await _mediaStore.saveFile(
        tempFilePath: imageFile.path,
        dirType: DirType.photo,
        dirName: DirName.pictures,
        relativePath: 'PolarizedCamera',
      );

      print('Image saved to gallery: $savedUri');
    } catch (e) {
      print('Error saving to gallery: $e');
      rethrow;
    }
  }

   /// ✅ Get all saved photos from PolarizedCamera folder
  static Future<List<File>> getSavedPhotos() async {
    try {
      final Directory picturesDir = Directory(
        '/storage/emulated/0/Pictures/PolarizedCamera',
      );

      if (!await picturesDir.exists()) {
        return [];
      }

      final files = picturesDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_polarized.jpg'))
          .toList();

      // Sort by newest first
      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );

      return files;
    } catch (e) {
      print('❌ Error loading photos: $e');
      return [];
    }
  }


  /// Save image to Downloads - Not usint it as of now
  // static Future<void> saveToDownloads(File imageFile, {String? fileName}) async {
  //   try {
  //     final String finalFileName = fileName ?? 
  //         '${DateTime.now().millisecondsSinceEpoch}_polarized.jpg';
      
  //     final savedUri = await _mediaStore.saveFile(
  //       tempFilePath: imageFile.path,
  //       dirType: DirType.photo,
  //       dirName: DirName.download,
  //     );

  //     print('Image saved to downloads: $savedUri');
  //   } catch (e) {
  //     print('Error saving to downloads: $e');
  //     rethrow;
  //   }
  // }
}