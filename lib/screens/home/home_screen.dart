import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/place_provider.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/place_card.dart';
import '../../widgets/category_chip.dart';
import '../../widgets/loading_widget.dart';
import '../map/map_screen.dart';
import '../detail/detail_screen.dart';
import '../auth/login_screen.dart';
import '../bookmark/bookmark_screen.dart';
import '../../providers/bookmark_provider.dart';
import 'package:geolocator/geolocator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl      = TextEditingController();
  final _homeFocusScope  = FocusScopeNode();
  final _homeScrollCtrl  = ScrollController();
  int _currentIndex      = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
    });
  }

  Future<void> _initLocation() async {
    try {
      // Cek apakah layanan lokasi menyala
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      // Cek & minta permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      // Ambil posisi & simpan ke provider
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      if (mounted) {
        context.read<PlaceProvider>().setUserLocation(
          position.latitude,
          position.longitude,
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _homeFocusScope.dispose();
    _homeScrollCtrl.dispose();
    super.dispose();
  }

  void switchToMap() {
    setState(() => _currentIndex = 1);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PlaceProvider>();
    if ((provider.pendingRoutePlace != null || provider.pendingViewPlace != null) && _currentIndex != 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _currentIndex = 1);
      });
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          FocusScope(
            node: _homeFocusScope,
            child: _HomeTab(scrollController: _homeScrollCtrl),
          ),
          const MapScreen(),
          const BookmarkScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) {
          _homeFocusScope.unfocus();
          final auth = context.read<AuthProvider>();
          if (i == 2) {
            if (!auth.isLoggedIn) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
              return;
            }
            if (auth.token != null) {
              context.read<BookmarkProvider>().fetchBookmarks(auth.token!);
            }
          }
          setState(() => _currentIndex = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Peta',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Tersimpan',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  final ScrollController scrollController;
  const _HomeTab({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Header
            Container(
              padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 0),
              color: const Color(0xFF1E3A5F),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Surabaya Heritage',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Jelajahi tempat bersejarah',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      Consumer<AuthProvider>(
                        builder: (_, auth, __) => IconButton(
                          icon: Icon(
                            auth.isLoggedIn
                                ? Icons.account_circle
                                : Icons.login,
                            color: Colors.white,
                            size: 28,
                          ),
                          onPressed: () {
                            if (auth.isLoggedIn) {
                              _showProfileMenu(context, auth);
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const LoginScreen(),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _SearchBar(),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            const _CategoryFilter(),
            Expanded(child: _PlaceList(scrollController: scrollController)),
          ],
        ),
      ),
      ),
    );
  }

  void _showProfileMenu(BuildContext context, AuthProvider auth) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_circle, size: 60, color: Color(0xFF1E3A5F)),
            const SizedBox(height: 8),
            Text(
              auth.user?.name ?? '',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              auth.user?.email ?? '',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('Keluar', style: TextStyle(color: Colors.red)),
                onPressed: () {
                  auth.logout();
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar();

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final _ctrl      = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      focusNode: _focusNode,
      autofocus: false,
      onChanged: (val) {
        context.read<PlaceProvider>().searchPlaces(val);
        setState(() {});
      },
      decoration: InputDecoration(
        hintText: 'Cari tempat bersejarah...',
        hintStyle: const TextStyle(color: Colors.grey),
        prefixIcon: const Icon(Icons.search, color: Colors.grey),
        suffixIcon: _ctrl.text.isNotEmpty
            ? GestureDetector(
                onTap: () {
                  _ctrl.clear();
                  context.read<PlaceProvider>().searchPlaces('');
                  setState(() {});
                  FocusScope.of(context).unfocus();
                },
                child: Container(
                  margin: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Colors.grey,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                ),
              )
            : null,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
      ),
    );
  }
}

class _CategoryFilter extends StatelessWidget {
  const _CategoryFilter();

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaceProvider>(
      builder: (_, provider, __) {
        if (provider.categories.isEmpty) return const SizedBox.shrink();
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => provider.filterByCategory(null),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: provider.selectedCategoryId == null
                          ? const Color(0xFF1E3A5F)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF1E3A5F),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'Semua',
                      style: TextStyle(
                        color: provider.selectedCategoryId == null
                            ? Colors.white
                            : const Color(0xFF1E3A5F),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                ...provider.categories.map(
                  (cat) => CategoryChip(
                    category: cat,
                    isSelected: provider.selectedCategoryId == cat.id,
                    onTap: () => provider.filterByCategory(cat.id),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PlaceList extends StatelessWidget {
  final ScrollController scrollController;
  const _PlaceList({required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlaceProvider>(
      builder: (_, provider, __) {
        if (provider.isLoading) return const LoadingWidget();

        if (provider.errorMessage != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 60, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  provider.errorMessage!,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => provider.fetchPlaces(),
                  child: const Text('Coba Lagi'),
                ),
              ],
            ),
          );
        }

        if (provider.places.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off, size: 60, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Tidak ada tempat ditemukan',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => provider.fetchPlaces(),
          child: ListView.builder(
            controller: scrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: provider.places.length,
            itemBuilder: (_, i) => PlaceCard(
              place: provider.places[i],
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      DetailScreen(placeId: provider.places[i].id),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}