import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../../providers/place_provider.dart';
import '../../models/place_model.dart';
import '../detail/detail_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;
  Position?            _userPosition;
  Set<Marker>          _markers = {};
  bool                 _isLoadingLocation = false;

  static const CameraPosition _surabayaCenter = CameraPosition(
    target: LatLng(-7.2575, 112.7521),
    zoom:   13,
  );

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildMarkers();
    });
  }

  Future<void> _getUserLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      // 1. Cek apakah layanan lokasi (GPS) HP menyala
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLoadingLocation = false);
        _showSnack('Layanan lokasi (GPS) tidak aktif. Nyalakan GPS di pengaturan HP.');
        return;
      }

      // 2. Cek & minta permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _isLoadingLocation = false);
          _showSnack('Izin lokasi ditolak.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() => _isLoadingLocation = false);
        _showSnack(
          'Izin lokasi diblokir permanen. Aktifkan lewat Pengaturan HP.',
        );
        return;
      }

      // 3. Ambil posisi user (dengan batas waktu 15 detik)
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );

      setState(() {
        _userPosition     = position;
        _isLoadingLocation = false;
      });

      // Simpan lokasi user ke provider agar jarak bisa dihitung
      if (mounted) {
        context.read<PlaceProvider>().setUserLocation(
          position.latitude,
          position.longitude,
        );
      }

      // 4. Pindahkan kamera ke posisi user
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          15,
        ),
      );
    } catch (e) {
      setState(() => _isLoadingLocation = false);
      _showSnack('Gagal menemukan lokasi. Pastikan GPS aktif dan coba lagi.');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  void _buildMarkers() {
    final places = context.read<PlaceProvider>().allPlaces;
    final markers = <Marker>{};

    for (final place in places) {
      markers.add(
        Marker(
          markerId: MarkerId(place.id.toString()),
          position: LatLng(place.lat, place.lng),
          infoWindow: InfoWindow(
            title:   place.name,
            snippet: place.category?.name ?? '',
            onTap:   () => _openDetail(place),
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            _getMarkerHue(place.category?.name),
          ),
        ),
      );
    }

    setState(() => _markers = markers);
  }

// Zoom otomatis agar semua pin masuk ke dalam layar
  void _fitAllMarkers() {
    if (_markers.isEmpty || _mapController == null) return;

    double minLat =  90, maxLat = -90;
    double minLng = 180, maxLng = -180;

    for (final m in _markers) {
      final lat = m.position.latitude;
      final lng = m.position.longitude;
      if (lat < minLat) minLat = lat;
      if (lat > maxLat) maxLat = lat;
      if (lng < minLng) minLng = lng;
      if (lng > maxLng) maxLng = lng;
    }

    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60, // padding pinggir layar
      ),
    );
  }

  double _getMarkerHue(String? categoryName) {
    switch (categoryName) {
      case 'Museum':
        return BitmapDescriptor.hueGreen;
      case 'Monumen & Tugu':
        return BitmapDescriptor.hueBlue;
      case 'Bangunan Kolonial':
        return BitmapDescriptor.hueOrange;
      case 'Kawasan Bersejarah':
        return BitmapDescriptor.hueViolet;
      case 'Tempat Ibadah Bersejarah':
        return BitmapDescriptor.hueRose;
      default:
        return BitmapDescriptor.hueRed;
    }
  }

  void _openDetail(PlaceModel place) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(placeId: place.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:         const Text('Peta Lokasi'),
        automaticallyImplyLeading: false,
        actions: [
          // Tombol refresh markers
          IconButton(
            icon:      const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _buildMarkers();
              _fitAllMarkers();
            },
            tooltip:   'Tampilkan Semua Lokasi',
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _surabayaCenter,
            markers:               _markers,
            myLocationEnabled:     true,
            myLocationButtonEnabled: false,
            mapType:               MapType.normal,
            zoomControlsEnabled:   false,
            onMapCreated: (controller) {
              _mapController = controller;
              _buildMarkers();
              if (_userPosition != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLng(
                    LatLng(
                      _userPosition!.latitude,
                      _userPosition!.longitude,
                    ),
                  ),
                );
              }
            },
          ),

          // Loading indicator lokasi
          if (_isLoadingLocation)
            Positioned(
              top:  16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color:        Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width:  16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Mencari lokasi kamu...'),
                    ],
                  ),
                ),
              ),
            ),

          // Tombol lokasi user
          Positioned(
            bottom: 100,
            right:  16,
            child: FloatingActionButton(
              mini:            true,
              backgroundColor: Colors.white,
              onPressed:       _getUserLocation,
              child: const Icon(
                Icons.my_location,
                color: Color(0xFF1E3A5F),
              ),
            ),
          ),

          // Legend kategori
          Positioned(
            bottom: 16,
            left:   16,
            child: Container(
              padding:     const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:        Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color:      Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LegendItem(color: Colors.green,  label: 'Museum'),
                  _LegendItem(color: Colors.blue,   label: 'Monumen & Tugu'),
                  _LegendItem(color: Colors.orange, label: 'Bangunan Kolonial'),
                  _LegendItem(color: Colors.purple, label: 'Kawasan Bersejarah'),
                  _LegendItem(color: Colors.pink,   label: 'Tempat Ibadah'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color  color;
  final String label;

  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width:  12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}