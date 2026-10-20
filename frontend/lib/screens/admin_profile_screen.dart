import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/user_service.dart';
import '../services/upload_service.dart';
import '../config/theme.dart';
import '../widgets/gold_button.dart';
import '../widgets/image_cropper_dialog.dart';

class AdminProfileScreen extends StatefulWidget {
  const AdminProfileScreen({super.key});

  @override
  State<AdminProfileScreen> createState() => _AdminProfileScreenState();
}

class _AdminProfileScreenState extends State<AdminProfileScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _hintController = TextEditingController();

  String? _profileImagePath;
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final user = await ApiService.get('/auth/me');
      if (user != null) {
        setState(() {
          _nameController.text = user['name'] ?? '';
          _emailController.text = user['email'] ?? '';
          _phoneController.text = user['phone'] ?? '';
          _hintController.text = user['recoveryHint'] ?? '';
          _profileImagePath = user['avatar'] ?? '';
        });
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _updateProfile() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final hint = _hintController.text.trim();

    if (name.isEmpty || email.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await ApiService.put('/auth/me', {
        'name': name,
        'email': email,
        'phone': phone,
        'avatar': _profileImagePath,
      });

      if (hint.isNotEmpty) {
        await ApiService.put('/auth/recovery-hint', {'recoveryHint': hint});
      }

      await UserService.saveUser(
        name: name,
        email: email,
        phone: phone,
        profileImage: _profileImagePath,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Admin profile updated successfully'),
            backgroundColor: AppTheme.success));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
        final imageUrl = await UploadService.uploadImage(croppedImage);
        if (imageUrl != null) {
          setState(() => _profileImagePath = imageUrl);
          await _updateProfile();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image upload failed: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _showEditDialog() {
    final nameEdit = TextEditingController(text: _nameController.text);
    final emailEdit = TextEditingController(text: _emailController.text);
    final phoneEdit = TextEditingController(text: _phoneController.text);
    final hintEdit = TextEditingController(text: _hintController.text);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: const BoxDecoration(
          color: AppTheme.deepCharcoal,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(top: BorderSide(color: AppTheme.glassBorder, width: 0.5)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('EDIT ADMIN IDENTITY',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 18, letterSpacing: 1.5)),
              const SizedBox(height: 28),
              _buildField('FULL NAME', nameEdit),
              const SizedBox(height: 18),
              _buildField('EMAIL ADDRESS', emailEdit),
              const SizedBox(height: 18),
              _buildField('PHONE NUMBER', phoneEdit, keyboard: TextInputType.phone),
              const SizedBox(height: 18),
              _buildField('RECOVERY HINT', hintEdit),
              const SizedBox(height: 32),
              GoldButton(
                label: 'SAVE PROFILE',
                onPressed: () {
                  setState(() {
                    _nameController.text = nameEdit.text;
                    _emailController.text = emailEdit.text;
                    _phoneController.text = phoneEdit.text;
                    _hintController.text = hintEdit.text;
                  });
                  Navigator.pop(ctx);
                  _updateProfile();
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentPass = TextEditingController();
    final newPass = TextEditingController();
    final confirmPass = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
        decoration: const BoxDecoration(
          color: AppTheme.deepCharcoal,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          border: Border(top: BorderSide(color: AppTheme.glassBorder, width: 0.5)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('UPDATE PASSWORD',
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 18, letterSpacing: 1.5)),
              const SizedBox(height: 28),
              _buildField('CURRENT PASSWORD', currentPass, obscure: true),
              const SizedBox(height: 18),
              _buildField('NEW PASSWORD', newPass, obscure: true),
              const SizedBox(height: 18),
              _buildField('CONFIRM NEW PASSWORD', confirmPass, obscure: true),
              const SizedBox(height: 32),
              GoldButton(
                label: 'SAVE PASSWORD',
                onPressed: () async {
                  if (newPass.text != confirmPass.text) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Passwords do not match'),
                        backgroundColor: AppTheme.error));
                    return;
                  }
                  if (currentPass.text.isEmpty || newPass.text.isEmpty) return;

                  Navigator.pop(ctx);
                  setState(() => _isLoading = true);
                  try {
                    await ApiService.put('/auth/change-password', {
                      'currentPassword': currentPass.text,
                      'newPassword': newPass.text
                    });
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Password updated successfully'),
                          backgroundColor: AppTheme.success));
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Failed: $e'),
                          backgroundColor: AppTheme.error));
                    }
                  } finally {
                    if (mounted) setState(() => _isLoading = false);
                  }
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl, {bool obscure = false, TextInputType keyboard = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2)),
        const SizedBox(height: 10),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          keyboardType: keyboard,
          style: const TextStyle(color: AppTheme.polishedSilver, fontSize: 13, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.03),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(100), borderSide: const BorderSide(color: AppTheme.glassBorder)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 360;

    return Scaffold(
      backgroundColor: AppTheme.deepCharcoal,
      appBar: AppBar(
        title: const Text('ADMIN PROFILE'),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18), onPressed: () => Navigator.pop(context)),
      ),
      body: Container(
        decoration: AppTheme.filigreeBackground(),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: EdgeInsets.all(isNarrow ? 16 : 24),
              child: Column(
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 28),
                  _buildMenuSection('IDENTITY SETTINGS', [
                    _buildMenuTile(Icons.edit_outlined, 'Edit Admin Details', _showEditDialog),
                    const Divider(color: AppTheme.glassBorder, height: 1, indent: 20, endIndent: 20),
                    _buildMenuTile(Icons.lock_outline_rounded, 'Change Password', _showChangePasswordDialog),
                  ]),
                ],
              ),
            ),
            if (_isLoading) const Center(child: CircularProgressIndicator(color: AppTheme.brushedPlatinum)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.premiumCard(radius: 32),
      child: Column(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              children: [
                Container(
                  width: 100, height: 100,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.glassBorder, width: 2)),
                  child: ClipOval(
                    child: _profileImagePath != null && _profileImagePath!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: _profileImagePath!, 
                          fit: BoxFit.cover,
                          width: 100,
                          height: 100,
                          placeholder: (ctx, url) => const CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brushedPlatinum),
                          errorWidget: (ctx, url, err) => const Icon(Icons.person, size: 50),
                        )
                      : const Icon(Icons.person_outline_rounded, color: AppTheme.coolGrey, size: 50),
                  ),
                ),
                Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: AppTheme.brushedPlatinum, shape: BoxShape.circle), child: const Icon(Icons.camera_alt_rounded, size: 14, color: Colors.black))),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(_nameController.text.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.polishedSilver, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(_emailController.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppTheme.coolGrey, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildMenuSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(left: 8, bottom: 12), child: Text(title, style: const TextStyle(color: Colors.white60, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 2))),
        Container(decoration: AppTheme.premiumCard(radius: 24), child: Column(children: children)),
      ],
    );
  }

  Widget _buildMenuTile(IconData icon, String title, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppTheme.brushedPlatinum, size: 20),
        title: Text(title, style: const TextStyle(color: AppTheme.polishedSilver, fontSize: 12, fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Colors.white10),
      ),
    );
  }
}
