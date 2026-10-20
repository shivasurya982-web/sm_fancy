import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import '../config/theme.dart';

class ImageCropperDialog extends StatefulWidget {
  final XFile imageFile;

  const ImageCropperDialog({super.key, required this.imageFile});

  static Future<XFile?> cropImage(BuildContext context, XFile file) async {
    return await showDialog<XFile?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ImageCropperDialog(imageFile: file),
    );
  }

  @override
  State<ImageCropperDialog> createState() => _ImageCropperDialogState();
}

class _ImageCropperDialogState extends State<ImageCropperDialog> {
  final GlobalKey _cropKey = GlobalKey();
  final TransformationController _transformController = TransformationController();
  Uint8List? _imageBytes;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadImageBytes();
  }

  Future<void> _loadImageBytes() async {
    final bytes = await widget.imageFile.readAsBytes();
    if (mounted) {
      setState(() {
        _imageBytes = bytes;
      });
    }
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _cropAndConfirm() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final boundary = _cropKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        Navigator.pop(context, widget.imageFile);
        return;
      }

      final ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        Navigator.pop(context, widget.imageFile);
        return;
      }

      final Uint8List croppedBytes = byteData.buffer.asUint8List();
      final croppedXFile = XFile.fromData(
        croppedBytes,
        name: 'cropped_profile.png',
        mimeType: 'image/png',
      );

      if (mounted) {
        Navigator.pop(context, croppedXFile);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context, widget.imageFile);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final double cropSize = (screenWidth * 0.7).clamp(220.0, 300.0);

    return Dialog(
      backgroundColor: AppTheme.deepCharcoal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: AppTheme.glassBorder, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'CROP PROFILE IMAGE',
              style: TextStyle(
                color: AppTheme.polishedSilver,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pinch or drag to position inside circle',
              style: TextStyle(color: AppTheme.coolGrey, fontSize: 11),
            ),
            const SizedBox(height: 20),
            _imageBytes == null
                ? SizedBox(
                    height: cropSize,
                    child: const Center(
                      child: CircularProgressIndicator(color: AppTheme.brushedPlatinum),
                    ),
                  )
                : Center(
                    child: Container(
                      width: cropSize,
                      height: cropSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppTheme.brushedPlatinum, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.5),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: RepaintBoundary(
                          key: _cropKey,
                          child: Container(
                            color: Colors.black,
                            child: InteractiveViewer(
                              transformationController: _transformController,
                              minScale: 0.8,
                              maxScale: 4.0,
                              boundaryMargin: const EdgeInsets.all(100),
                              child: Image.memory(
                                _imageBytes!,
                                fit: BoxFit.cover,
                                width: cropSize,
                                height: cropSize,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
            const SizedBox(height: 28),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppTheme.coolGrey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isProcessing ? null : () => Navigator.pop(context, null),
                    child: const Text('CANCEL', style: TextStyle(color: AppTheme.coolGrey, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.brushedPlatinum,
                      foregroundColor: AppTheme.matteBlack,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _isProcessing ? null : _cropAndConfirm,
                    child: _isProcessing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Text('CROP & SAVE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
