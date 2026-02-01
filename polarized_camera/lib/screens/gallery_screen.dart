import 'dart:io';
import 'package:flutter/material.dart';
import 'full_preview_screen.dart';

class GalleryScreen extends StatelessWidget {
  final List<File> photos;

  const GalleryScreen({super.key, required this.photos});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 212, 213, 213),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 212, 213, 213),
        surfaceTintColor: const Color.fromARGB(255, 212, 213, 213),
        elevation: 0,
        title: Text(
          'Gallery (${photos.length})',
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: photos.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 80,
                    color: Colors.black38,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No photos yet',
                    style: TextStyle(color: Colors.black54, fontSize: 18),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.9,
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      color: const Color.fromARGB(255, 212, 213, 213),
                      padding: const EdgeInsets.all(6), // reduces empty edges
                      child: AspectRatio(
                        aspectRatio:
                            1, // square preview (try 4 / 3 if you want taller)
                        child: Image.file(photos[index], fit: BoxFit.contain),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
