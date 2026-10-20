import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/chat_service.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../services/upload_service.dart';
import '../config/theme.dart';
import '../widgets/image_viewer.dart';
import '../widgets/glass_toast.dart';

class ChatScreen extends StatefulWidget {
  final String customerId;
  final String customerName;
  final String? customerAvatar;

  const ChatScreen({
    super.key,
    required this.customerId,
    required this.customerName,
    this.customerAvatar,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final messageController = TextEditingController();
  final listScrollController = ScrollController();
  List<ChatMessage> messages = [];
  bool isLoading = false;
  bool isUploading = false;
  bool isLocating = false;
  Timer? pollTimer;
  StreamSubscription<dynamic>? chatSubscription;
  String? editingMsgId;
  String? _fetchedAdminAvatar;

  @override
  void initState() {
    super.initState();
    loadMessages();
    if (widget.customerId == 'admin' && ApiService.currentUserRole == 'user') {
      _loadAdminInfo();
    }
    final roomCustomerId = ApiService.currentUserRole == 'admin' ? widget.customerId : ApiService.currentUserId;
    if (roomCustomerId != null) SocketService.joinRoom('${roomCustomerId}_admin');
    chatSubscription = SocketService.chatMessages.listen(_handleRealtimeMessage);
    pollTimer = Timer.periodic(const Duration(seconds: 4), (timer) => loadMessages(silent: true));
  }

  @override
  void dispose() { pollTimer?.cancel(); chatSubscription?.cancel(); messageController.dispose(); listScrollController.dispose(); super.dispose(); }

  Future<void> _loadAdminInfo() async {
    try {
      final res = await ApiService.get('/auth/admin-info');
      if (res != null && mounted) {
        setState(() {
          _fetchedAdminAvatar = res['avatar'];
        });
      }
    } catch (_) {}
  }

  void _handleRealtimeMessage(dynamic payload) {
    if (!mounted || payload is! Map) return;
    
    final event = payload['event'];
    final data = payload['data'];
    
    if (event == 'new') {
      final message = ChatMessage.fromJson(Map<String, dynamic>.from(data));
      if (messages.any((item) => item.id == message.id)) return;
      setState(() => messages.add(message));
      _scrollToBottom();
    } else if (event == 'edited') {
      final updated = ChatMessage.fromJson(Map<String, dynamic>.from(data));
      setState(() {
        final idx = messages.indexWhere((m) => m.id == updated.id);
        if (idx != -1) messages[idx] = updated;
      });
    } else if (event == 'deleted') {
      final msgId = data['id']?.toString();
      setState(() {
        final idx = messages.indexWhere((m) => m.id == msgId);
        if (idx != -1) {
            final old = messages[idx];
            messages[idx] = ChatMessage(
                id: old.id,
                customerId: old.customerId,
                senderId: old.senderId,
                senderName: old.senderName,
                message: 'This message was deleted',
                senderRole: old.senderRole,
                createdAt: old.createdAt,
                isDeleted: true
            );
        }
      });
    }
  }

  Future<void> loadMessages({bool silent = false}) async {
    if (!silent && mounted) setState(() => isLoading = true);
    try {
      final list = await ChatService.fetchMessages(widget.customerId);
      if (mounted) { setState(() => messages = list); if (!silent) _scrollToBottom(); }
    } catch (_) {}
    if (!silent && mounted) setState(() => isLoading = false);
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (listScrollController.hasClients) listScrollController.animateTo(listScrollController.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  Future<void> handleSendMessage({String? image, Map<String, double>? location}) async {
    final text = messageController.text.trim();
    if (text.isEmpty && image == null && location == null) return;
    
    final currentEditingId = editingMsgId;
    messageController.clear();
    setState(() => editingMsgId = null);

    try {
      if (currentEditingId != null) {
          await ChatService.editMessage(currentEditingId, text);
      } else {
          final sent = await ChatService.sendMessage(widget.customerId, text, image: image, location: location);
          if (mounted) { setState(() => messages.add(sent)); _scrollToBottom(); }
      }
    } catch (_) {}
  }

  void _startEditing(ChatMessage msg) {
    setState(() {
      editingMsgId = msg.id;
      messageController.text = msg.message;
    });
  }

  void _confirmDelete(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.deepCharcoal,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: const BorderSide(color: AppTheme.platinumBorder)),
        title: const Text('DELETE MESSAGE?', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1, color: Colors.white)),
        content: const Text('Are you sure you want to remove this message? This action cannot be undone.', style: TextStyle(color: AppTheme.coolGrey, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL', style: TextStyle(color: AppTheme.coolGrey, fontWeight: FontWeight.bold))),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ChatService.deleteMessage(id);
            },
            child: const Text('DELETE', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _shareLocation() async {
    if (isLocating) return;
    setState(() => isLocating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) showGlassToast(context, 'Location services are disabled on your device.', isError: true);
        setState(() => isLocating = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) showGlassToast(context, 'Location permission was denied.', isError: true);
          setState(() => isLocating = false);
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          showGlassToast(context, 'Location permissions are permanently denied. Please enable in Settings.', isError: true);
          await Geolocator.openAppSettings();
        }
        setState(() => isLocating = false);
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      await handleSendMessage(location: {'lat': position.latitude, 'lng': position.longitude});
    } catch (e) {
      if (mounted) showGlassToast(context, e.toString(), isError: true);
    } finally {
      if (mounted) setState(() => isLocating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isWeb = screenWidth > 800;
    final displayAvatar = widget.customerId == 'admin' ? _fetchedAdminAvatar : widget.customerAvatar;

    return Scaffold(
      backgroundColor: AppTheme.deepCharcoal,
      resizeToAvoidBottomInset: true, 
      appBar: AppBar(
        title: Row(
          children: [
            if (displayAvatar != null && displayAvatar.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.glassBorder, width: 0.5)),
                  child: ClipOval(child: CachedNetworkImage(imageUrl: displayAvatar, fit: BoxFit.cover, errorWidget: (ctx, url, err) => const Icon(Icons.person, size: 18))),
                ),
              ),
            Expanded(
              child: Text(widget.customerName.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 2)),
            ),
          ],
        ),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18), onPressed: () => Navigator.pop(context)),
      ),
      body: Container(
        decoration: AppTheme.filigreeBackground(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWeb ? 600 : double.infinity),
            child: Column(
              children: [
                if (isUploading || isLocating) const LinearProgressIndicator(minHeight: 1, valueColor: AlwaysStoppedAnimation(AppTheme.brushedPlatinum), backgroundColor: Colors.transparent),
                Expanded(
                  child: ListView.builder(
                    controller: listScrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final bool isMe = (ApiService.currentUserRole == 'admin' && msg.senderId == 'admin') || (ApiService.currentUserRole == 'user' && msg.senderId == ApiService.currentUserId);
                      return _buildMessageBubble(msg, isMe);
                    },
                  ),
                ),
                _buildInputArea(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
    final isDeleted = msg.isDeleted;
    final double screenWidth = MediaQuery.of(context).size.width;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isMe && !isDeleted ? () => _showOptions(msg) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          constraints: BoxConstraints(maxWidth: screenWidth * 0.75),
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withValues(alpha: 0.08) : AppTheme.matteBlack.withValues(alpha: 0.5),
            border: Border.all(color: isMe ? AppTheme.glassBorder : Colors.white10, width: 1),
            borderRadius: BorderRadius.only(topLeft: const Radius.circular(20), topRight: const Radius.circular(20), bottomLeft: Radius.circular(isMe ? 20 : 4), bottomRight: Radius.circular(isMe ? 4 : 20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msg.image != null && msg.image!.isNotEmpty && !isDeleted) 
                Padding(
                  padding: const EdgeInsets.only(bottom: 8), 
                  child: GestureDetector(
                    onTap: () {
                      FullScreenImageViewer.show(context, msg.image!, title: 'Chat Photo');
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12), 
                      child: CachedNetworkImage(imageUrl: msg.image!),
                    ),
                  ),
                ),
              if (msg.location != null && !isDeleted) _buildLocationCard(msg.location!),
              Text(isDeleted ? 'This message was deleted' : msg.message, style: TextStyle(color: isDeleted ? AppTheme.coolGrey : (isMe ? Colors.white : AppTheme.polishedSilver), fontSize: 13, height: 1.4, fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal)),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(DateFormat('hh:mm a').format(msg.createdAt.toLocal()), style: const TextStyle(color: Colors.white10, fontSize: 8, fontWeight: FontWeight.bold)),
                  if (msg.isEdited && !isDeleted) ...[const SizedBox(width: 4), const Text('• Edited', style: TextStyle(color: Colors.white10, fontSize: 8))],
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms).moveY(begin: 10, end: 0);
  }

  void _showOptions(ChatMessage msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(color: AppTheme.deepCharcoal, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (msg.message.isNotEmpty) ListTile(leading: const Icon(Icons.edit_outlined, color: AppTheme.brushedPlatinum), title: const Text('EDIT MESSAGE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)), onTap: () { Navigator.pop(ctx); _startEditing(msg); }),
            ListTile(leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.error), title: const Text('DELETE MESSAGE', style: TextStyle(color: AppTheme.error, fontWeight: FontWeight.bold, fontSize: 13)), onTap: () { Navigator.pop(ctx); _confirmDelete(msg.id); }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(Map<String, double> loc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.glassBorder, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [Icon(Icons.location_on_rounded, color: AppTheme.brushedPlatinum, size: 16), SizedBox(width: 8), Text('LOCATION SHARED', style: TextStyle(color: AppTheme.brushedPlatinum, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1))]),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 32, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.brushedPlatinum, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)), padding: EdgeInsets.zero), onPressed: () => _openInMaps(loc['lat']!, loc['lng']!), child: const Text('OPEN IN MAPS', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)))),
        ],
      ),
    );
  }

  Future<void> _openInMaps(double lat, double lng) async {
    final url = Uri.parse('https://www.google.com/maps?q=$lat,$lng');
    if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Widget _buildInputArea() {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (editingMsgId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: AppTheme.brushedPlatinum.withValues(alpha: 0.1),
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, size: 14, color: AppTheme.brushedPlatinum),
                  const SizedBox(width: 8),
                  const Text('Editing Message', style: TextStyle(color: AppTheme.brushedPlatinum, fontSize: 11, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  GestureDetector(onTap: () => setState(() { editingMsgId = null; messageController.clear(); }), child: const Icon(Icons.close_rounded, size: 16, color: AppTheme.coolGrey)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppTheme.deepCharcoal.withValues(alpha: 0.8), border: const Border(top: BorderSide(color: AppTheme.glassBorder, width: 0.5))),
            child: Row(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: isUploading || isLocating ? null : () async {
                    final img = await ImagePicker().pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 70,
                      maxWidth: 1024,
                      maxHeight: 1024,
                    );
                    if (img != null) {
                      setState(() => isUploading = true);
                      final url = await UploadService.uploadImage(img);
                      if (url != null) handleSendMessage(image: url);
                      setState(() => isUploading = false);
                    }
                  }, 
                  icon: const Icon(Icons.add_photo_alternate_outlined, color: AppTheme.coolGrey, size: 20),
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  onPressed: isUploading || isLocating ? null : _shareLocation, 
                  icon: Icon(Icons.location_on_outlined, color: isLocating ? AppTheme.brushedPlatinum : AppTheme.coolGrey, size: 20),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14), 
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(100), border: Border.all(color: AppTheme.glassBorder)), 
                    child: TextField(
                      controller: messageController, 
                      decoration: const InputDecoration(hintText: "Type a message...", border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none, filled: false, contentPadding: EdgeInsets.symmetric(vertical: 10)), 
                      style: const TextStyle(fontSize: 13, color: AppTheme.polishedSilver),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 42, height: 42, 
                  decoration: const BoxDecoration(color: AppTheme.brushedPlatinum, shape: BoxShape.circle), 
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => handleSendMessage(), 
                    icon: const Icon(Icons.send_rounded, color: Colors.black, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
