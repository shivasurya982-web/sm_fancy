import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/user_service.dart';
import '../services/upload_service.dart';
import '../config/theme.dart';
import '../widgets/image_cropper_dialog.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _profileImagePath;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _nameController.text = await UserService.getName();
    _emailController.text = await UserService.getEmail();
    _phoneController.text = await UserService.getPhone();
    _profileImagePath = await UserService.getProfileImage();
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1200,
      maxHeight: 1200,
    );
    if (image == null || !mounted) return;

    final croppedImage = await ImageCropperDialog.cropImage(context, image);
    if (croppedImage != null) {
      setState(() => _isLoading = true);
      try {
        final String? uploadedUrl = await UploadService.uploadImage(croppedImage);
        if (uploadedUrl != null) {
          setState(() => _profileImagePath = uploadedUrl);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("IMAGE UPLOADED")));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      await UserService.saveUser(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        profileImage: _profileImagePath,
      );
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("PROFILE UPDATED"), backgroundColor: AppTheme.success));
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 360;

    return Scaffold(
      backgroundColor: AppTheme.deepCharcoal,
      appBar: AppBar(
        title: const Text("EDIT PROFILE"),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20), onPressed: () => Navigator.pop(context)),
      ),
      body: Container(
        decoration: AppTheme.filigreeBackground(),
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 24, vertical: 20),
          child: Column(
            children: [
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _isLoading ? null : _pickImage,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                        border: Border.all(color: AppTheme.glassBorder, width: 1.5),
                      ),
                      child: ClipOval(
                        child: _isLoading 
                          ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brushedPlatinum))
                          : (_profileImagePath == null || _profileImagePath!.isEmpty)
                            ? const Icon(Icons.person_outline_rounded, size: 50, color: AppTheme.coolGrey)
                            : _buildImageWidget(),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: AppTheme.brushedPlatinum, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.black),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              
              Container(
                  padding: const EdgeInsets.all(20),
                  decoration: AppTheme.premiumCard(radius: 24),
                  child: Column(
                      children: [
                        _buildField('FULL NAME', _nameController, Icons.person_outline_rounded),
                        const SizedBox(height: 20),
                        _buildField('EMAIL ADDRESS', _emailController, Icons.email_outlined, enabled: false),
                        const SizedBox(height: 20),
                        _buildField('PHONE NUMBER', _phoneController, Icons.phone_outlined, keyboardType: TextInputType.phone),
                      ],
                  ),
              ),

              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  child: const Text("SAVE CHANGES"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageWidget() {
    if (_profileImagePath == null || _profileImagePath!.isEmpty) return const SizedBox();
    if (_profileImagePath!.startsWith('http')) {
      return CachedNetworkImage(imageUrl: _profileImagePath!, fit: BoxFit.cover);
    } else {
      return Image.file(File(_profileImagePath!), fit: BoxFit.cover);
    }
  }

  Widget _buildField(String label, TextEditingController ctrl, IconData icon, {bool enabled = true, TextInputType keyboardType = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 8, color: Colors.white70)),
        const SizedBox(height: 10),
        TextField(
          controller: ctrl,
          enabled: enabled,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: enabled ? AppTheme.polishedSilver : AppTheme.coolGrey),
          decoration: InputDecoration(
              prefixIcon: Icon(icon, size: 18, color: AppTheme.brushedPlatinum),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.03),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(100), borderSide: const BorderSide(color: AppTheme.glassBorder)),
          ),
        ),
      ],
    );
  }
}
