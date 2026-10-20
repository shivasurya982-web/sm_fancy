import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import 'package:image_picker/image_picker.dart';
import '../config/theme.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  State<ProductManagementScreen> createState() => _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  List<ProductModel> _products = [];
  List<Uint8List> _selectedImagesBytes = [];
  List<String> _selectedImageNames = [];
  List<String> _existingImagesUrls = [];
  bool _isLoading = false;
  String _searchQuery = '';
  
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _priceController = TextEditingController();
  final _categoryController = TextEditingController();
  final _brandController = TextEditingController();
  final _stockController = TextEditingController();
  final _metalController = TextEditingController();
  final _purityController = TextEditingController();
  final _weightController = TextEditingController();
  final _stoneController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    _brandController.dispose();
    _stockController.dispose();
    _metalController.dispose();
    _purityController.dispose();
    _weightController.dispose();
    _stoneController.dispose();
    super.dispose();
  }

  Future<void> _pickMultiImage(StateSetter setDialogState) async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage(
      imageQuality: 70,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (pickedFiles.isEmpty) return;
    for (var file in pickedFiles) {
      final bytes = await file.readAsBytes();
      _selectedImagesBytes.add(bytes);
      _selectedImageNames.add(file.name);
    }
    setDialogState(() {});
  }

  Future<void> _loadProducts() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final list = await ProductService.fetchProducts(search: _searchQuery.isEmpty ? null : _searchQuery, forceRefresh: true);
      if (mounted) setState(() => _products = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSaveProduct({String? id}) async {
    final name = _nameController.text.trim();
    final desc = _descController.text.trim();
    final price = double.tryParse(_priceController.text.trim()) ?? 0;
    final category = _categoryController.text.trim();
    if (name.isEmpty || desc.isEmpty || category.isEmpty) return;

    Navigator.pop(context);
    setState(() => _isLoading = true);
    try {
      if (id == null) {
        await ProductService.addProduct(
          name: name, description: desc, price: price, category: category,
          imagesBytes: _selectedImagesBytes, fileNames: _selectedImageNames,
          brand: _brandController.text.trim(), stock: int.tryParse(_stockController.text.trim()) ?? 0,
          metalType: _metalController.text.trim(), purity: _purityController.text.trim(),
          weight: _weightController.text.trim(), stoneInfo: _stoneController.text.trim(),
        );
      } else {
        await ProductService.updateProduct(
          id, name: name, description: desc, price: price, category: category,
          imagesBytes: _selectedImagesBytes, fileNames: _selectedImageNames,
          brand: _brandController.text.trim(), stock: int.tryParse(_stockController.text.trim()) ?? 0,
          metalType: _metalController.text.trim(), purity: _purityController.text.trim(),
          weight: _weightController.text.trim(), stoneInfo: _stoneController.text.trim(),
        );
      }
      _loadProducts();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error));
      setState(() => _isLoading = false);
    }
  }

  void _showProductDialog({ProductModel? product}) {
    if (product != null) {
      _nameController.text = product.name;
      _descController.text = product.description;
      _priceController.text = product.price.toString();
      _categoryController.text = product.category;
      _brandController.text = product.brand;
      _stockController.text = product.stock.toString();
      _metalController.text = product.metalType ?? '';
      _purityController.text = product.purity ?? '';
      _weightController.text = product.weight ?? '';
      _stoneController.text = product.stoneInfo ?? '';
      _existingImagesUrls = List.from(product.images);
    } else {
      _nameController.clear(); _descController.clear(); _priceController.clear();
      _categoryController.clear(); _brandController.clear(); _stockController.clear();
      _metalController.clear(); _purityController.clear(); _weightController.clear();
      _stoneController.clear();
      _existingImagesUrls = [];
    }
    _selectedImagesBytes = [];
    _selectedImageNames = [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          decoration: const BoxDecoration(color: AppTheme.deepCharcoal, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          child: Column(
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.platinumBorder.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text(product == null ? 'ADD PRODUCT' : 'EDIT PRODUCT', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 1)),
              const SizedBox(height: 20),
              Expanded(
                child: ListView(
                  children: [
                    _buildInput('PRODUCT NAME', _nameController),
                    const SizedBox(height: 14),
                    _buildInput('DESCRIPTION', _descController, maxLines: 3),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _buildInput('PRICE (₹)', _priceController, isNumeric: true)),
                        const SizedBox(width: 14),
                        Expanded(child: _buildInput('STOCK', _stockController, isNumeric: true)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildInput('CATEGORY', _categoryController),
                    const SizedBox(height: 14),
                    _buildInput('BRAND', _brandController),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _buildInput('METAL', _metalController)),
                        const SizedBox(width: 14),
                        Expanded(child: _buildInput('PURITY', _purityController)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _buildInput('WEIGHT', _weightController)),
                        const SizedBox(width: 14),
                        Expanded(child: _buildInput('STONES', _stoneController)),
                      ],
                    ),
                    const SizedBox(height: 20),
                    
                    if (_existingImagesUrls.isNotEmpty) ...[
                        const Text('SAVED IMAGES', style: TextStyle(color: AppTheme.coolGrey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 10),
                        SizedBox(height: 80, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _existingImagesUrls.length, itemBuilder: (ctx, i) => _buildCloudThumb(i, setDialogState))),
                        const SizedBox(height: 16),
                    ],

                    if (_selectedImagesBytes.isNotEmpty) ...[
                        const Text('NEW IMAGES', style: TextStyle(color: AppTheme.coolGrey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 10),
                        SizedBox(height: 80, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _selectedImagesBytes.length, itemBuilder: (ctx, i) => _buildImageThumb(i, setDialogState))),
                        const SizedBox(height: 16),
                    ],
                    
                    OutlinedButton.icon(
                      onPressed: () => _pickMultiImage(setDialogState),
                      icon: const Icon(Icons.add_a_photo_outlined, size: 20),
                      label: const Text('ADD IMAGES'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _handleSaveProduct(id: product?.id),
                  child: Text(product == null ? 'CREATE' : 'SAVE'),
                ),
              ),
            ],
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
        title: const Text('MANAGE PRODUCTS'),
        actions: [IconButton(icon: const Icon(Icons.add_rounded, size: 28), onPressed: () => _showProductDialog())],
      ),
      body: Container(
        decoration: AppTheme.filigreeBackground(),
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: EdgeInsets.all(isNarrow ? 16 : 24),
                  child: TextField(
                    decoration: const InputDecoration(hintText: 'Search products...', prefixIcon: Icon(Icons.search_outlined)),
                    onChanged: (v) { _searchQuery = v; _loadProducts(); },
                  ),
                ),
                Expanded(
                  child: _products.isEmpty && !_isLoading
                      ? const Center(child: Text('No products found.', style: TextStyle(color: AppTheme.coolGrey, letterSpacing: 1)))
                      : Builder(
                          builder: (context) {
                            final double gridWidth = MediaQuery.of(context).size.width;
                            final int crossAxisCount = gridWidth > 600 ? 3 : 2;
                            final double aspectRatio = gridWidth < 360 ? 0.58 : (gridWidth < 400 ? 0.60 : 0.64);
                            return GridView.builder(
                              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 24, vertical: 10),
                              itemCount: _products.length,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                childAspectRatio: aspectRatio,
                                crossAxisSpacing: isNarrow ? 12 : 16,
                                mainAxisSpacing: isNarrow ? 12 : 16,
                              ),
                              itemBuilder: (ctx, i) => _buildProductTile(_products[i]),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 20),
              ],
            ),
            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.35),
                child: const Center(
                  child: CircularProgressIndicator(color: AppTheme.brushedPlatinum),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInput(String label, TextEditingController ctrl, {int maxLines = 1, bool isNumeric = false}) {
    return TextField(
      controller: ctrl, maxLines: maxLines,
      keyboardType: isNumeric ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label, labelStyle: const TextStyle(fontSize: 9, letterSpacing: 1)),
    );
  }

  Widget _buildImageThumb(int i, StateSetter setDialogState) {
    return Container(
      margin: const EdgeInsets.only(right: 12), width: 80, height: 80,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.glassBorder), image: DecorationImage(image: MemoryImage(_selectedImagesBytes[i]), fit: BoxFit.cover)),
      child: Align(alignment: Alignment.topRight, child: GestureDetector(onTap: () { _selectedImagesBytes.removeAt(i); _selectedImageNames.removeAt(i); setDialogState(() {}); }, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close, size: 14, color: Colors.white)))),
    );
  }

  Widget _buildCloudThumb(int i, StateSetter setDialogState) {
      return Container(
          margin: const EdgeInsets.only(right: 12), width: 80, height: 80,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.glassBorder), image: DecorationImage(image: NetworkImage(_existingImagesUrls[i]), fit: BoxFit.cover)),
          child: Align(alignment: Alignment.topRight, child: GestureDetector(onTap: () { _existingImagesUrls.removeAt(i); setDialogState(() {}); }, child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: AppTheme.error, shape: BoxShape.circle), child: const Icon(Icons.delete_outline, size: 14, color: Colors.white)))),
      );
  }

  Widget _buildProductTile(ProductModel p) {
    return Container(
      decoration: AppTheme.premiumCard(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(20)), child: _buildTileImage(p.image))),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5, color: AppTheme.polishedSilver), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('₹${p.price.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w300, fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildIconBtn(Icons.edit_outlined, AppTheme.brushedPlatinum, () => _showProductDialog(product: p)),
                    _buildIconBtn(Icons.delete_outline_rounded, AppTheme.error, () async {
                      if (mounted) setState(() => _isLoading = true);
                      await ProductService.deleteProduct(p.id); _loadProducts();
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTileImage(String url) {
    if (url.isEmpty) return Container(color: Colors.white10);
    return CachedNetworkImage(imageUrl: url, fit: BoxFit.cover, errorWidget: (context, url, error) => Container(color: Colors.white10));
  }

  Widget _buildIconBtn(IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Icon(icon, color: color, size: 14),
      ),
    );
  }
}
