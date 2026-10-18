import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

/// Captures a widget as a PNG and opens the native share sheet — the My
/// Prep score card, and the feed's question and session cards.
class ShareCardService {
  static Future<void> shareFromKey(
    GlobalKey key, {
    String text = "Here's my practice progress on Quirzy!",
    String fileName = 'my_prep_progress.png',
  }) async {
    final bytes = await _capture(key);
    if (bytes == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, mimeType: 'image/png', name: fileName)],
        text: text,
      ),
    );
  }

  /// Renders [card] off-screen (in the app's overlay, outside the visible
  /// area), captures it and shares the image. Returns false if it could not
  /// be captured, so the caller can fall back to sharing text.
  static Future<bool> shareWidget(
    BuildContext context,
    Widget card, {
    required String text,
    required String fileName,
  }) async {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return false;
    final key = GlobalKey();
    final theme = Theme.of(context);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -10000,
        top: 0,
        child: Theme(
          data: theme,
          child: Material(
            type: MaterialType.transparency,
            child: RepaintBoundary(key: key, child: card),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    try {
      // Let it lay out and paint once before capturing.
      await WidgetsBinding.instance.endOfFrame;
      final bytes = await _capture(key);
      if (bytes == null) return false;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'image/png', name: fileName)],
          text: text,
        ),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      entry.remove();
    }
  }

  static Future<Uint8List?> _capture(GlobalKey key) async {
    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final ui.Image image = await boundary.toImage(pixelRatio: 3);
    final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }
}
