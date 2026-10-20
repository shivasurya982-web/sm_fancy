import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/user_service.dart';
import '../services/upload_service.dart';
import '../config/theme.dart';
import '../widgets/gold_button.dart';
import '../widgets/glass_toast.dart';
import '../widgets/image_cropper_dialog.dart';
import 'login_screen.dart';
import 'address_screen.dart';
import 'complaints_screen.dart';
import 'user_chat_redirect.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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
        _nameController.text = user['name'] ?? '';
        _emailController.text = user['email'] ?? '';
        _phoneController.text = user['phone'] ?? '';
        _hintController.text = user['recoveryHint'] ?? '';
        _profileImagePath = user['avatar'] ?? '';

        await UserService.saveUser(
          name: _nameController.text,
          email: _emailController.text,
          phone: _phoneController.text,
          profileImage: _profileImagePath,
        );
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _updateProfile() async {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final hint = _hintController.text.trim();

    if (name.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await ApiService.put('/auth/me', {
        'name': name,
        'phone': phone,
        'avatar': _profileImagePath,
      });

      if (hint.isNotEmpty) {
        await ApiService.put('/auth/recovery-hint', {'recoveryHint': hint});
      }

      await UserService.saveUser(
        name: name,
        email: _emailController.text,
        phone: phone,
        profileImage: _profileImagePath,
      );

      if (mounted) {
        showGlassToast(context, 'Profile updated successfully', isError: false, title: 'PROFILE UPDATED');
      }
    } catch (e) {
      if (mounted) {
        showGlassToast(context, 'Error updating profile: $e', isError: true);
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
          showGlassToast(context, 'Image upload failed: $e', isError: true);
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  void _showEditDialog() {
    final nameEdit = TextEditingController(text: _nameController.text);
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
              Text('EDIT PROFILE',
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(fontSize: 20, letterSpacing: 1.5)),
              const SizedBox(height: 28),
              _buildRegisterStyleField('FULL NAME', nameEdit, hint: 'ENTER YOUR NAME'),
              const SizedBox(height: 18),
              _buildRegisterStyleField('EMAIL ADDRESS', _emailController,
                  hint: 'ENTER YOUR EMAIL', enabled: false),
              const SizedBox(height: 18),
              _buildRegisterStyleField('PHONE NUMBER', phoneEdit,
                  hint: 'ENTER YOUR PHONE', keyboard: TextInputType.phone),
              const SizedBox(height: 18),
              _buildRegisterStyleField('RECOVERY HINT', hintEdit,
                  hint: 'ENTER RECOVERY HINT'),
              const SizedBox(height: 32),
              GoldButton(
                label: 'SAVE CHANGES',
                onPressed: () {
                  _nameController.text = nameEdit.text;
                  _phoneController.text = phoneEdit.text;
                  _hintController.text = hintEdit.text;
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
              Text('CHANGE PASSWORD',
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(fontSize: 20, letterSpacing: 1.5)),
              const SizedBox(height: 28),
              _buildRegisterStyleField('CURRENT PASSWORD', currentPass,
                  hint: '••••••••', obscure: true),
              const SizedBox(height: 18),
              _buildRegisterStyleField('NEW PASSWORD', newPass,
                  hint: '••••••••', obscure: true),
              const SizedBox(height: 18),
              _buildRegisterStyleField('CONFIRM NEW PASSWORD', confirmPass,
                  hint: '••••••••', obscure: true),
              const SizedBox(height: 32),
              GoldButton(
                label: 'UPDATE PASSWORD',
                onPressed: () async {
                  if (newPass.text != confirmPass.text) {
                    showGlassToast(ctx, 'Passwords do not match', isError: true, title: 'PASSWORD ERROR');
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
                      showGlassToast(context, 'Password updated successfully', isError: false, title: 'PASSWORD UPDATED');
                    }
                  } catch (e) {
                    if (mounted) {
                      showGlassToast(context, 'Failed to update password: $e', isError: true);
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

  Widget _buildRegisterStyleField(String label, TextEditingController ctrl,
      {String? hint,
      bool enabled = true,
      bool obscure = false,
      TextInputType keyboard = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(fontSize: 9, color: Colors.white70)),
        const SizedBox(height: 10),
        TextField(
          controller: ctrl,
          enabled: enabled,
          obscureText: obscure,
          keyboardType: keyboard,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: enabled ? AppTheme.polishedSilver : AppTheme.coolGrey),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Colors.white24),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.03),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(100),
                borderSide: const BorderSide(color: AppTheme.glassBorder)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final bool isSmall = screenWidth < 360;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: isWeb ? 500 : double.infinity),
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(isSmall ? 16 : 24, 12, isSmall ? 16 : 24, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PROFILE', style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 24),
                    _buildHeader(),
                    const SizedBox(height: 32),
                    _buildSectionTitle('COLLECTIONS'),
                    const SizedBox(height: 12),
                    _buildMenuCard([
                      _buildMenuTile(Icons.map_outlined, 'Saved Addresses', () {
                        Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const AddressScreen()));
                      }),
                    ]),
                    const SizedBox(height: 24),
                    _buildSectionTitle('SECURITY'),
                    const SizedBox(height: 12),
                    _buildMenuCard([
                      _buildMenuTile(Icons.lock_outline_rounded, 'Change Password',
                          _showChangePasswordDialog),
                    ]),
                    const SizedBox(height: 24),
                    _buildSectionTitle('PREFERENCES'),
                    const SizedBox(height: 12),
                    _buildMenuCard([
                      _buildMenuTile(Icons.notifications_active_outlined, 'App Notifications & Permissions', () async {
                        await openAppSettings();
                      }),
                    ]),
                    const SizedBox(height: 24),
                    _buildSectionTitle('CONCIERGE'),
                    const SizedBox(height: 12),
                    _buildMenuCard([
                      _buildMenuTile(Icons.chat_bubble_outline_rounded, 'Chat with Support', () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const UserChatRedirect()));
                      }),
                      const Divider(color: AppTheme.glassBorder, height: 1, indent: 20, endIndent: 20),
                      _buildMenuTile(Icons.help_outline_rounded, 'Help & Support', () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const ComplaintsScreen()));
                      }),
                    ]),
                    const SizedBox(height: 36),
                    _buildLogoutBtn(),
                  ],
                ),
              ),
              if (_isLoading)
                const Center(
                    child: CircularProgressIndicator(color: AppTheme.brushedPlatinum)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.premiumCard(radius: 24),
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.glassBorder, width: 1),
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                  child: ClipOval(
                    child: _profileImagePath != null &&
                            _profileImagePath!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: _profileImagePath!, 
                            fit: BoxFit.cover,
                            width: 64,
                            height: 64,
                            placeholder: (ctx, url) => const CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brushedPlatinum),
                          )
                        : const Icon(Icons.person_outline_rounded,
                            color: AppTheme.coolGrey, size: 28),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                        color: AppTheme.brushedPlatinum, shape: BoxShape.circle),
                    child: const Icon(Icons.camera_alt_rounded,
                        size: 12, color: Colors.black),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nameController.text.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppTheme.polishedSilver,
                      letterSpacing: 0.5),
                ),
                const SizedBox(height: 4),
                Text(_emailController.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.coolGrey, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            onPressed: _showEditDialog,
            icon: const Icon(Icons.edit_note_rounded,
                color: AppTheme.brushedPlatinum, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 8));
  }

  Widget _buildMenuCard(List<Widget> children) {
    return Container(
      decoration: AppTheme.premiumCard(radius: 24),
      child: Column(children: children),
    );
  }

  Widget _buildMenuTile(IconData icon, String title, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppTheme.brushedPlatinum, size: 18),
        title: Text(title,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.polishedSilver)),
        trailing: const Icon(Icons.chevron_right_rounded,
            size: 16, color: Colors.white10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
    );
  }

  Widget _buildLogoutBtn() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () async {
          await AuthService.logout();
          if (mounted) {
            Navigator.pushAndRemoveUntil(context,
                MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
          }
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.brushedPlatinum,
          side: const BorderSide(color: AppTheme.platinumBorder),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        ),
        child: const Text('LOGOUT',
            style: TextStyle(
                fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 10)),
      ),
    );
  }
}
