import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/settings_service.dart';
import '../services/category_service.dart';
import '../config/theme.dart';
import '../widgets/product_card.dart';
import 'product_details_screen.dart';
import 'categories_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _selectedCategory = 'All';
  List<ProductModel> _allProducts = [];
  List<ProductModel> _filteredProducts = [];
  List<dynamic> _banners = [];
  List<dynamic> _categories = [];
  bool _isLoading = false;
  String _sortBy = 'Newest';
  
  double _minPrice = 0;
  double _maxPrice = 100000;
  bool _onlyInStock = false;
  double _minRating = 0.0;
  
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData(forceRefresh: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (mounted && (_allProducts.isEmpty || forceRefresh)) {
        setState(() => _isLoading = true);
    }
    try {
      await Future.wait([
        _loadProducts(forceRefresh), 
        _loadSettings(forceRefresh: forceRefresh),
        _loadCategories()
      ]);
      _applyFilterAndSort();
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadProducts(bool forceRefresh) async {
    try {
      final list = await ProductService.fetchProducts(forceRefresh: forceRefresh);
      if (mounted) setState(() => _allProducts = list);
    } catch (_) {}
  }

  Future<void> _loadSettings({bool forceRefresh = false}) async {
    final settings = await SettingsService.getSettings(forceRefresh: forceRefresh);
    if (mounted) {
      setState(() {
        final homeBanners = settings['homeBanners'];
        if (homeBanners is List && homeBanners.isNotEmpty) {
          _banners = List<dynamic>.from(homeBanners);
        } else {
          final onboardingBanners = settings['onboardingBanners'];
          if (onboardingBanners is List && onboardingBanners.isNotEmpty) {
            _banners = List<dynamic>.from(onboardingBanners);
          } else {
            _banners = [
              {
                'title': 'Siva Murugan Fancy',
                'description': 'Tiruchendur',
                'image': 'assets/images/logo1.png'
              },
              {
                'title': 'Luxury Collection',
                'description': 'Exclusive Jewellery',
                'image': 'assets/images/banner4.jpg'
              },
              {
                'title': 'Special Deals',
                'description': 'Premium Accessories',
                'image': 'assets/images/banner5.jpg'
              }
            ];
          }
        }
      });
    }
  }

  Future<void> _loadCategories() async {
    final list = await CategoryService.fetchCategories();
    if (mounted) setState(() => _categories = list);
  }

  void _applyFilterAndSort() {
    final query = _searchController.text.toLowerCase();
    List<ProductModel> filtered = List.from(_allProducts);
    
    // Search Filter
    if (query.isNotEmpty) {
      filtered = filtered.where((p) => 
        p.name.toLowerCase().contains(query) || 
        p.category.toLowerCase().contains(query) ||
        p.description.toLowerCase().contains(query)
      ).toList();
    }

    // Category Filter
    if (_selectedCategory != 'All') {
      filtered = filtered.where((p) => p.category.trim().toLowerCase() == _selectedCategory.trim().toLowerCase()).toList();
    }
    
    // Price Filter
    filtered = filtered.where((p) => p.price >= _minPrice && p.price <= _maxPrice).toList();
    
    // Stock Filter
    if (_onlyInStock) {
      filtered = filtered.where((p) => p.stock > 0).toList();
    }

    // Rating Filter
    if (_minRating > 0) {
      filtered = filtered.where((p) => p.averageRating >= _minRating).toList();
    }
    
    // Sort
    if (_sortBy == 'Price: Low to High') {
      filtered.sort((a, b) => a.price.compareTo(b.price));
    } else if (_sortBy == 'Price: High to Low') {
      filtered.sort((a, b) => b.price.compareTo(a.price));
    } else if (_sortBy == 'Highest Rated') {
      filtered.sort((a, b) => b.averageRating.compareTo(a.averageRating));
    }
    
    setState(() => _filteredProducts = filtered);
  }

  Widget _buildPriceAdjustBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppTheme.glassBorder, width: 0.8),
          color: Colors.white.withValues(alpha: 0.05),
        ),
        child: Icon(icon, color: AppTheme.brushedPlatinum, size: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isNarrow = screenWidth < 360;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () => _loadData(forceRefresh: true),
        color: AppTheme.brushedPlatinum,
        backgroundColor: AppTheme.matteBlack,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: SizedBox(height: 10)),

            // Search Bar
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: isNarrow ? 16 : 24, vertical: 10),
              sliver: SliverToBoxAdapter(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: AppTheme.glassBorder),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_outlined, color: AppTheme.coolGrey, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          onChanged: (_) => _applyFilterAndSort(),
                          style: const TextStyle(color: AppTheme.polishedSilver, fontSize: 14),
                          decoration: const InputDecoration(
                            hintText: 'Search for pieces...',
                            hintStyle: TextStyle(color: AppTheme.coolGrey, fontSize: 13),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppTheme.coolGrey, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _applyFilterAndSort();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),

            if (_banners.isNotEmpty && _searchController.text.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.only(top: 16),
                sliver: SliverToBoxAdapter(
                  child: CarouselSlider(
                    options: CarouselOptions(
                      height: isNarrow ? 180 : 220,
                      viewportFraction: isNarrow ? 0.95 : 0.9,
                      enlargeCenterPage: true,
                      autoPlay: true,
                    ),
                    items: _banners.map((banner) {
                      return Container(
                        width: double.infinity,
                        decoration: AppTheme.premiumCard(radius: 32),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(32),
                          child: _buildBannerImage(banner['image']),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(isNarrow ? 20 : 32, isNarrow ? 32 : 48, isNarrow ? 20 : 32, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _searchController.text.isEmpty ? 'CURATED COLLECTIONS' : 'SEARCH RESULTS',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9),
                      ),
                    ),
                    if (_searchController.text.isEmpty) ...[
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoriesScreen())),
                        child: const Text('VIEW ALL', style: TextStyle(color: AppTheme.brushedPlatinum, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1)),
                      ),
                      const SizedBox(width: 12),
                    ],
                    GestureDetector(
                      onTap: () {
                         String tempSort = _sortBy;
                         double tempMin = _minPrice;
                         double tempMax = _maxPrice;
                         bool tempStock = _onlyInStock;
                         double tempRating = _minRating;

                         showModalBottomSheet(
                           context: context,
                           backgroundColor: Colors.transparent,
                           isScrollControlled: true,
                           builder: (ctx) => StatefulBuilder(
                             builder: (context, setSheetState) => DraggableScrollableSheet(
                               initialChildSize: 0.80,
                               minChildSize: 0.4,
                               maxChildSize: 0.95,
                               builder: (_, scrollController) => Container(
                               padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
                               decoration: BoxDecoration(
                                 color: AppTheme.deepCharcoal,
                                 borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                                 border: Border.all(color: AppTheme.glassBorder),
                               ),
                               child: ListView(
                                 controller: scrollController,
                                 children: [
                                   Row(
                                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                     children: [
                                       Text('FILTERS & SORTING', style: Theme.of(context).textTheme.labelSmall),
                                       IconButton(
                                         onPressed: () => Navigator.pop(ctx),
                                         icon: const Icon(Icons.close_rounded, color: AppTheme.coolGrey, size: 20),
                                       ),
                                     ],
                                   ),
                                   const SizedBox(height: 24),
                                   const Text('SORT BY', style: TextStyle(color: AppTheme.coolGrey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                   const SizedBox(height: 12),
                                   
                                   ...['Newest', 'Price: Low to High', 'Price: High to Low', 'Highest Rated'].map((opt) => GestureDetector(
                                      onTap: () => setSheetState(() => tempSort = opt),
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        child: Row(
                                          children: [
                                            Text(opt.toUpperCase(), style: TextStyle(color: tempSort == opt ? AppTheme.polishedSilver : AppTheme.coolGrey, fontWeight: tempSort == opt ? FontWeight.w900 : FontWeight.w400, fontSize: 12, letterSpacing: 1)),
                                            const Spacer(),
                                            if (tempSort == opt) const Icon(Icons.check_rounded, color: AppTheme.brushedPlatinum, size: 18),
                                          ],
                                        ),
                                      ),
                                   )),

                                   const SizedBox(height: 24),
                                   const Text('RATING FILTER', style: TextStyle(color: AppTheme.coolGrey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                   const SizedBox(height: 12),
                                   SingleChildScrollView(
                                     scrollDirection: Axis.horizontal,
                                     child: Row(
                                       children: [
                                         0.0, 4.0, 3.0, 2.0
                                       ].map((rVal) {
                                         final isSelected = tempRating == rVal;
                                         final label = rVal == 0.0 ? 'ALL RATINGS' : '${rVal.toInt()}★ & ABOVE';
                                         return Padding(
                                           padding: const EdgeInsets.only(right: 8),
                                           child: ChoiceChip(
                                             label: Text(label, style: TextStyle(fontSize: 9, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500, letterSpacing: 0.5)),
                                             selected: isSelected,
                                             onSelected: (val) {
                                               if (val) setSheetState(() => tempRating = rVal);
                                             },
                                             backgroundColor: Colors.white.withValues(alpha: 0.05),
                                             selectedColor: AppTheme.brushedPlatinum,
                                             labelStyle: TextStyle(color: isSelected ? Colors.black : AppTheme.coolGrey),
                                             shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100), side: BorderSide(color: isSelected ? AppTheme.brushedPlatinum : AppTheme.glassBorder, width: 0.5)),
                                           ),
                                         );
                                       }).toList(),
                                     ),
                                   ),

                                   const SizedBox(height: 24),
                                   Row(
                                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                     children: [
                                       const Text('PRICE RANGE (₹)', style: TextStyle(color: AppTheme.coolGrey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                       Row(
                                         children: [
                                           _buildPriceAdjustBtn(Icons.remove, () => setSheetState(() { if (tempMax > tempMin + 100) tempMax -= 100; })),
                                           const SizedBox(width: 12),
                                           Text('₹${tempMax.round()}', style: const TextStyle(color: AppTheme.polishedSilver, fontSize: 11, fontWeight: FontWeight.bold)),
                                           const SizedBox(width: 12),
                                           _buildPriceAdjustBtn(Icons.add, () => setSheetState(() { if (tempMax < 100000) tempMax += 100; })),
                                         ],
                                       ),
                                     ],
                                   ),
                                   const SizedBox(height: 8),
                                   RangeSlider(
                                     values: RangeValues(tempMin, tempMax),
                                     min: 0, max: 100000, divisions: 1000,
                                     activeColor: AppTheme.brushedPlatinum, inactiveColor: Colors.white10,
                                     labels: RangeLabels('₹${tempMin.round()}', '₹${tempMax.round()}'),
                                     onChanged: (values) => setSheetState(() { tempMin = values.start; tempMax = values.end; }),
                                   ),
                                   
                                   const SizedBox(height: 24),
                                   Row(
                                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                     children: [
                                       const Text('ONLY IN STOCK', style: TextStyle(color: AppTheme.coolGrey, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                                       Switch(
                                         value: tempStock,
                                         activeThumbColor: AppTheme.brushedPlatinum,
                                         onChanged: (val) => setSheetState(() => tempStock = val),
                                       ),
                                     ],
                                   ),
                                   
                                   const SizedBox(height: 32),
                                   SizedBox(
                                     width: double.infinity,
                                     child: ElevatedButton(
                                       onPressed: () {
                                          _sortBy = tempSort;
                                          _minPrice = tempMin;
                                          _maxPrice = tempMax;
                                          _onlyInStock = tempStock;
                                          _minRating = tempRating;
                                          _applyFilterAndSort();
                                          Navigator.pop(ctx);
                                       },
                                       child: const Text('APPLY FILTERS'),
                                     ),
                                   ),
                                   const SizedBox(height: 20),
                                 ],
                               ),
                             ),
                           ),
                         ),
                       );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: AppTheme.capsuleDecoration(),
                        child: const Icon(Icons.tune_rounded, color: AppTheme.brushedPlatinum, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_searchController.text.isEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 40,
                  child: ListView.separated(
                    padding: EdgeInsets.symmetric(horizontal: isNarrow ? 20 : 32),
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length + 1,
                    separatorBuilder: (ctx, index) => const SizedBox(width: 10),
                    itemBuilder: (ctx, idx) {
                      final isAll = idx == 0;
                      final name = isAll ? 'ALL' : _categories[idx - 1]['name'].toString().toUpperCase();
                      final isSelected = _selectedCategory == (isAll ? 'All' : _categories[idx - 1]['name']);
                      return GestureDetector(
                        onTap: () {
                          setState(() => _selectedCategory = isAll ? 'All' : _categories[idx - 1]['name']);
                          _applyFilterAndSort();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.brushedPlatinum : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: isSelected ? AppTheme.brushedPlatinum : AppTheme.glassBorder, width: 0.8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            name,
                            style: TextStyle(
                              color: isSelected ? Colors.black : AppTheme.coolGrey,
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.w900 : FontWeight.w500,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

            SliverPadding(
              padding: EdgeInsets.fromLTRB(isNarrow ? 16 : 32, 20, isNarrow ? 16 : 32, 120),
              sliver: _isLoading
                  ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator(color: AppTheme.brushedPlatinum)))
                  : _filteredProducts.isEmpty
                  ? SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('NO ITEMS FOUND', style: TextStyle(color: AppTheme.coolGrey, fontWeight: FontWeight.w900, letterSpacing: 2)),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: () => _loadData(forceRefresh: true),
                              icon: const Icon(Icons.refresh_rounded, color: AppTheme.brushedPlatinum, size: 18),
                              label: const Text('RELOAD LIVE DATA', style: TextStyle(color: AppTheme.brushedPlatinum, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1)),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Builder(
                      builder: (context) {
                        final double gridWidth = MediaQuery.of(context).size.width;
                        final int crossAxisCount = gridWidth > 600 ? 3 : 2;
                        final double aspectRatio = gridWidth < 360 ? 0.55 : (gridWidth < 400 ? 0.60 : 0.64);
                        return SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            childAspectRatio: aspectRatio,
                            crossAxisSpacing: isNarrow ? 12 : 16,
                            mainAxisSpacing: isNarrow ? 12 : 16,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (ctx, idx) {
                              return ProductCard(
                                product: _filteredProducts[idx],
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => ProductDetailsScreen(product: _filteredProducts[idx])),
                                ),
                              ).animate().fadeIn(duration: 400.ms, delay: (idx % 4 * 100).ms).scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOut);
                            },
                            childCount: _filteredProducts.length,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerImage(String? url) {
    if (url == null || url.isEmpty) return Container(color: Colors.white10);
    if (url.startsWith('assets/')) {
      return Container(
        color: AppTheme.matteBlack,
        child: Center(
          child: Image.asset(url, fit: BoxFit.contain),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(color: Colors.white10),
      errorWidget: (context, url, error) => Container(
        color: AppTheme.matteBlack,
        child: Center(
          child: Image.asset('assets/images/logo1.png', fit: BoxFit.contain),
        ),
      ),
    );
  }
}
