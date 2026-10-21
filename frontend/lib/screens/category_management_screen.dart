import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/category_service.dart';
import '../services/upload_service.dart';
import '../config/theme.dart';

class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() => _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  List<dynamic> _categories = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = await CategoryService.fetchCategories();
      setState(() => _categories = list);
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  void _showAddEditDialog({dynamic category}) {
    final nameCtrl = TextEditingController(text: category?['name'] ?? '');
    String? imageUrl = category?['image'];
    bool uploading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
          decoration: const BoxDecoration(
            color: AppTheme.deepCharcoal, 
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
            border: Border(top: BorderSide(color: AppTheme.glassBorder, width: 0.5)),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(category == null ? 'ADD CATEGORY' : 'EDIT CATEGORY', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1, color: AppTheme.polishedSilver)),
                const SizedBox(height: 24),
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'CATEGORY NAME')),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () async {
                      final img = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 70,
                        maxWidth: 1024,
                        maxHeight: 1024,
                      );
                      if (img != null) {
                          setDialogState(() => uploading = true);
                          final url = await UploadService.uploadImage(img);
                          setDialogState(() {
                            if (url != null && url.isNotEmpty) imageUrl = url;
                            uploading = false;
                          });
                      }
                  },
                  child: Container(
                    height: 130, width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05), 
                      border: Border.all(color: AppTheme.glassBorder, width: 1), 
                      borderRadius: BorderRadius.circular(20)
                    ),
                    child: uploading 
                      ? const Center(child: CircularProgressIndicator(color: AppTheme.brushedPlatinum))
                      : imageUrl != null 
                          ? ClipRRect(borderRadius: BorderRadius.circular(20), child: Image.network(imageUrl!, fit: BoxFit.cover))
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center, 
                              children: [
                                  Icon(Icons.add_a_photo_outlined, color: AppTheme.brushedPlatinum.withValues(alpha: 0.3), size: 32), 
                                  const SizedBox(height: 12), 
                                  const Text('UPLOAD IMAGE', style: TextStyle(fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w900, color: AppTheme.coolGrey))
                              ]
                          ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameCtrl.text.isEmpty) return;
                      if (category == null) {
                        await CategoryService.addCategory(nameCtrl.text.trim(), imageUrl);
                      } else {
                        await CategoryService.updateCategory(category['_id'], nameCtrl.text.trim(), imageUrl);
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    },
                    child: Text(category == null ? 'CREATE' : 'SAVE'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 360;

    return Scaffold(
      backgroundColor: AppTheme.deepCharcoal,
      appBar: AppBar(
        title: const Text('MANAGE CATEGORIES'),
        actions: [IconButton(onPressed: () => _showAddEditDialog(), icon: const Icon(Icons.add_rounded, size: 28))],
      ),
      body: Container(
        decoration: AppTheme.filigreeBackground(),
        child: Stack(
          children: [
            _categories.isEmpty && !_isLoading
                ? const Center(child: Text('No categories found.', style: TextStyle(color: AppTheme.coolGrey, letterSpacing: 1)))
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(isNarrow ? 16 : 24, 20, isNarrow ? 16 : 24, 100),
                    itemCount: _categories.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (ctx, idx) {
                      final cat = _categories[idx];
                      return Container(
                        decoration: AppTheme.premiumCard(radius: 24),
                        child: Material(
                          color: Colors.transparent,
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(12),
                            leading: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: Colors.white.withValues(alpha: 0.05),
                                border: Border.all(color: AppTheme.glassBorder, width: 0.8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: cat['image'] != null && cat['image'].toString().startsWith('http')
                                    ? Image.network(cat['image'], fit: BoxFit.cover)
                                    : const Icon(Icons.category_rounded, color: Colors.white10, size: 24),
                              ),
                            ),
                            title: Text(cat['name'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1, color: AppTheme.polishedSilver)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(icon: const Icon(Icons.edit_outlined, color: AppTheme.brushedPlatinum, size: 20), onPressed: () => _showAddEditDialog(category: cat)),
                                IconButton(icon: const Icon(Icons.delete_outline_rounded, color: AppTheme.error, size: 20), onPressed: () async {
                                  await CategoryService.deleteCategory(cat['_id']);
                                  _load();
                                }),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.35),
                child: const Center(child: CircularProgressIndicator(color: AppTheme.brushedPlatinum)),
              ),
          ],
        ),
      ),
    );
  }
}
