import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/settings_service.dart';
import '../services/upload_service.dart';
import '../config/theme.dart';
import '../widgets/gold_button.dart';

class SplashConfigScreen extends StatefulWidget {
  const SplashConfigScreen({super.key});

  @override
  State<SplashConfigScreen> createState() => _SplashConfigScreenState();
}

class _SplashConfigScreenState extends State<SplashConfigScreen> {
  final _taglineController = TextEditingController();
  final _upiIdController = TextEditingController();
  final _ownerPhoneController = TextEditingController();
  final _localCityController = TextEditingController();
  final _localFeeController = TextEditingController();
  final _standardFeeController = TextEditingController();
  List<dynamic> _welcomeBanners = [];
  List<dynamic> _homeBanners = [];
  String? _upiQrUrl;
  bool _isLoading = false;
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _taglineController.dispose();
    _upiIdController.dispose();
    _ownerPhoneController.dispose();
    _localCityController.dispose();
    _localFeeController.dispose();
    _standardFeeController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final settings = await SettingsService.getSettings();
      setState(() {
        _taglineController.text = settings['splashTagline'] ?? '';
        _upiIdController.text = settings['upiId'] ?? '';
        _ownerPhoneController.text = settings['ownerPhone'] ?? '9443039600';
        _localCityController.text = settings['localCity'] ?? '';
        _localFeeController.text = (settings['localShippingFee'] ?? 0.0).toString();
        _standardFeeController.text = (settings['standardShippingFee'] ?? 0.0).toString();
        _welcomeBanners = List<dynamic>.from(settings['onboardingBanners'] ?? []);
        _homeBanners = List<dynamic>.from(settings['homeBanners'] ?? []);
        _upiQrUrl = settings['upiQrCode'];
      });
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);
    try {
      await SettingsService.updateSettings({
        'splashTagline': _taglineController.text.trim(),
        'upiId': _upiIdController.text.trim(),
        'ownerPhone': _ownerPhoneController.text.trim(),
        'upiQrCode': _upiQrUrl,
        'localCity': _localCityController.text.trim(),
        'localShippingFee': double.tryParse(_localFeeController.text) ?? 0.0,
        'standardShippingFee': double.tryParse(_standardFeeController.text) ?? 0.0,
        'onboardingBanners': _welcomeBanners,
        'homeBanners': _homeBanners,
      });
      if (mounted) { 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings and Banners updated successfully!'), backgroundColor: AppTheme.success),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _autoSaveBanners() async {
    try {
      await SettingsService.updateSettings({
        'splashTagline': _taglineController.text.trim(),
        'upiId': _upiIdController.text.trim(),
        'ownerPhone': _ownerPhoneController.text.trim(),
        'upiQrCode': _upiQrUrl,
        'localCity': _localCityController.text.trim(),
        'localShippingFee': double.tryParse(_localFeeController.text) ?? 0.0,
        'standardShippingFee': double.tryParse(_standardFeeController.text) ?? 0.0,
        'onboardingBanners': _welcomeBanners,
        'homeBanners': _homeBanners,
      });
    } catch (_) {}
  }

  Future<void> _pickAndAddHomeBanner() async {
    try {
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (img == null) return;

      setState(() => _isUploadingImage = true);
      final url = await UploadService.uploadImage(img);
      setState(() => _isUploadingImage = false);

      if (url != null && url.isNotEmpty) {
        setState(() {
          _homeBanners.add({
            'title': 'Siva Murugan Fancy',
            'description': 'Tiruchendur',
            'image': url,
          });
        });
        await _autoSaveBanners();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('New banner image uploaded!'), backgroundColor: AppTheme.success),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload image. Please try again.')),
          );
        }
      }
    } catch (e) {
      setState(() => _isUploadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading image: $e')));
      }
    }
  }

  Future<void> _pickAndUpdateHomeBanner(int index) async {
    try {
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      if (img == null) return;

      setState(() => _isUploadingImage = true);
      final url = await UploadService.uploadImage(img);
      setState(() => _isUploadingImage = false);

      if (url != null && url.isNotEmpty) {
        setState(() {
          final existing = Map<String, dynamic>.from(_homeBanners[index] as Map);
          existing['image'] = url;
          _homeBanners[index] = existing;
        });
        await _autoSaveBanners();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Banner image changed successfully!'), backgroundColor: AppTheme.success),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to upload replacement image.')),
          );
        }
      }
    } catch (e) {
      setState(() => _isUploadingImage = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error changing image: $e')));
      }
    }
  }

  void _showAddBannerUrlDialog() {
    final urlCtrl = TextEditingController();
    final titleCtrl = TextEditingController(text: 'Siva Murugan Fancy');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.deepCharcoal,
        title: const Text('ADD BANNER BY URL', style: TextStyle(color: AppTheme.polishedSilver, fontSize: 14, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'Banner Title'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              decoration: const InputDecoration(labelText: 'Banner Image URL (https://...)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: AppTheme.coolGrey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brushedPlatinum),
            onPressed: () async {
              final url = urlCtrl.text.trim();
              if (url.isNotEmpty) {
                setState(() {
                  _homeBanners.add({
                    'title': titleCtrl.text.trim().isEmpty ? 'Siva Murugan Fancy' : titleCtrl.text.trim(),
                    'description': 'Tiruchendur',
                    'image': url,
                  });
                });
                await _autoSaveBanners();
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Banner URL added.'), backgroundColor: AppTheme.success),
                  );
                }
              }
            },
            child: const Text('ADD', style: TextStyle(color: AppTheme.matteBlack, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final bool isNarrow = screenWidth < 360;

    return Scaffold(
      backgroundColor: AppTheme.deepCharcoal,
      appBar: AppBar(
        title: const Text('APP SETTINGS'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Container(
        decoration: AppTheme.filigreeBackground(),
        child: Stack(
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWeb ? 550 : double.infinity),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 24, vertical: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader('HOME DASHBOARD BANNERS'),
                      const SizedBox(height: 8),
                      const Text(
                        'Upload and manage banner images displayed on the home dashboard.',
                        style: TextStyle(color: AppTheme.coolGrey, fontSize: 11),
                      ),
                      const SizedBox(height: 16),
                      _buildHomeBannersList(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: const BorderSide(color: AppTheme.brushedPlatinum),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              icon: _isUploadingImage
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brushedPlatinum))
                                  : const Icon(Icons.cloud_upload_rounded, color: AppTheme.brushedPlatinum, size: 18),
                              label: Text(_isUploadingImage ? 'UPLOADING...' : 'UPLOAD IMAGE', style: const TextStyle(color: AppTheme.brushedPlatinum, fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: _isUploadingImage ? null : _pickAndAddHomeBanner,
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                              side: const BorderSide(color: AppTheme.glassBorder),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            icon: const Icon(Icons.link_rounded, color: AppTheme.coolGrey, size: 18),
                            label: const Text('URL', style: TextStyle(color: AppTheme.coolGrey, fontSize: 11)),
                            onPressed: _showAddBannerUrlDialog,
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),

                      _buildHeader('GENERAL SETTINGS'),
                      const SizedBox(height: 20),
                      _buildInput('SPLASH TAGLINE', _taglineController),
                      const SizedBox(height: 14),
                      _buildInput('CONTACT PHONE', _ownerPhoneController, numeric: true),
                      const SizedBox(height: 14),
                      _buildInput('UPI ID', _upiIdController),
                      const SizedBox(height: 28),
                      const Text('UPI QR CODE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1, color: AppTheme.coolGrey)),
                      const SizedBox(height: 14),
                      Center(
                        child: GestureDetector(
                          onTap: _isUploadingImage ? null : () async {
                            final img = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 70,
                              maxWidth: 800,
                              maxHeight: 800,
                            );
                            if (img != null) {
                              setState(() => _isUploadingImage = true);
                              final url = await UploadService.uploadImage(img);
                              setState(() {
                                if (url != null && url.isNotEmpty) _upiQrUrl = url;
                                _isUploadingImage = false;
                              });
                            }
                          },
                          child: Container(
                            width: 160,
                            height: 160,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: AppTheme.glassBorder, width: 1),
                            ),
                            child: _upiQrUrl != null
                                ? ClipRRect(borderRadius: BorderRadius.circular(24), child: Image.network(_upiQrUrl!, fit: BoxFit.cover))
                                : const Icon(Icons.qr_code_scanner_rounded, color: AppTheme.brushedPlatinum, size: 48),
                          ),
                        ),
                      ),
                      const SizedBox(height: 36),

                      _buildHeader('SHIPPING FEES'),
                      const SizedBox(height: 20),
                      _buildInput('LOCAL CITY', _localCityController),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: _buildInput('LOCAL FEE', _localFeeController, numeric: true)),
                          const SizedBox(width: 14),
                          Expanded(child: _buildInput('STANDARD FEE', _standardFeeController, numeric: true)),
                        ],
                      ),
                      const SizedBox(height: 36),
                      GoldButton(label: 'SAVE SETTINGS', onPressed: _isLoading ? null : _save),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.4),
                child: const Center(
                  child: CircularProgressIndicator(color: AppTheme.brushedPlatinum),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeBannersList() {
    if (_homeBanners.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.premiumCard(radius: 20),
        child: const Column(
          children: [
            Icon(Icons.image_not_supported_outlined, color: AppTheme.coolGrey, size: 36),
            SizedBox(height: 8),
            Text(
              'No custom banners added yet.\nThe app currently displays the default logo/banner.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.coolGrey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _homeBanners.length,
      itemBuilder: (context, index) {
        final banner = _homeBanners[index];
        final String? imageUrl = banner['image'];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: AppTheme.premiumCard(radius: 20),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 90,
                  height: 60,
                  color: Colors.white10,
                  child: imageUrl != null && imageUrl.isNotEmpty
                      ? (imageUrl.startsWith('assets/')
                          ? Image.asset(imageUrl, fit: BoxFit.cover)
                          : Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: AppTheme.coolGrey),
                            ))
                      : const Icon(Icons.image_rounded, color: AppTheme.coolGrey),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      banner['title'] ?? 'Banner #${index + 1}',
                      style: const TextStyle(color: AppTheme.polishedSilver, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      imageUrl ?? 'No image URL',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.coolGrey, fontSize: 10),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_a_photo_outlined, color: AppTheme.brushedPlatinum, size: 20),
                tooltip: 'Change Image',
                onPressed: () => _pickAndUpdateHomeBanner(index),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error, size: 20),
                tooltip: 'Delete Banner',
                onPressed: () async {
                  setState(() {
                    _homeBanners.removeAt(index);
                  });
                  await _autoSaveBanners();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(String title) => Text(title, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9));

  Widget _buildInput(String label, TextEditingController ctrl, {bool numeric = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: numeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 9, letterSpacing: 1),
      ),
    );
  }
}
