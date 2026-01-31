import 'dart:io';
import 'package:image/image.dart' as img;

class PolarizationEffect {
  static Future<File> applyEffect(
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
    final int smallerWidth = (image.width * 0.85).toInt();
    final int smallerHeight = (image.height * 0.65)
        .toInt(); // Even smaller height
    final img.Image resizedImage = img.copyResize(
      image,
      width: smallerWidth,
      height: smallerHeight,
      interpolation: img.Interpolation.linear,
    );

    // Modern Polaroid frame dimensions
    final int topBorder = 70; // Top white border
    final int sideBorder = 70; // Left and right white borders
    final int bottomBorder = 200; // Large bottom border
    final int cornerRadius = 35; // Rounded corners
    final int outerMargin = 50; // Margin around the entire frame

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
        else if (frameX < cornerRadius &&
            frameY >= frameHeight - cornerRadius) {
          dx = cornerRadius - frameX;
          dy = frameY - (frameHeight - cornerRadius - 1);
          isCorner = true;
        }
        // Bottom-right corner
        else if (frameX >= frameWidth - cornerRadius &&
            frameY >= frameHeight - cornerRadius) {
          dx = frameX - (frameWidth - cornerRadius - 1);
          dy = frameY - (frameHeight - cornerRadius - 1);
          isCorner = true;
        }

        // If in corner area, check if outside radius
        if (isCorner) {
          final int distance = dx * dx + dy * dy;

          // STEP makes the curve less smooth (try 4–10)
          const int step = 6;

          final int steppedDistance = ((distance / step).floor()) * step;

          if (steppedDistance > cornerRadius * cornerRadius) {
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
          framedImage.setPixel(
            x,
            photoTop - 1 - i,
            img.ColorRgb8(180, 180, 180),
          );
        }
      }
      // Bottom border
      for (int x = photoLeft - i; x < photoLeft + photoWidth + i; x++) {
        if (x >= 0 && x < totalWidth) {
          framedImage.setPixel(
            x,
            photoTop + photoHeight + i,
            img.ColorRgb8(180, 180, 180),
          );
        }
      }
      // Left border
      for (int y = photoTop - i; y < photoTop + photoHeight + i; y++) {
        if (y >= 0 && y < totalHeight) {
          framedImage.setPixel(
            photoLeft - 1 - i,
            y,
            img.ColorRgb8(180, 180, 180),
          );
        }
      }
      // Right border
      for (int y = photoTop - i; y < photoTop + photoHeight + i; y++) {
        if (y >= 0 && y < totalHeight) {
          framedImage.setPixel(
            photoLeft + photoWidth + i,
            y,
            img.ColorRgb8(180, 180, 180),
          );
        }
      }
    }

    final polarizedFile = File(
      inputFile.path.replaceFirst('.jpg', '_polarized.jpg'),
    );
    await polarizedFile.writeAsBytes(img.encodeJpg(framedImage, quality: 95));
    return polarizedFile;
  }
}
