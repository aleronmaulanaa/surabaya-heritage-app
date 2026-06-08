import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
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
  Position? _userPosition;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  PlaceModel? _selectedPlace;
  bool _isLoadingLocation = false;
  bool _isLoadingRoute = false;
  bool _showBottomSheet = false;
  bool _isHoursExpanded = false;
  double _bottomSheetHeight = 0;
  int _slidePage = 0;

  static const CameraPosition _surabayaCenter = CameraPosition(
    target: LatLng(-7.2575, 112.7521),
    zoom: 13,
  );

  @override
  void initState() {
    super.initState();
    _getUserLocation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _buildMarkers();
    });
  }

  // ── GPS ────────────────────────────────────────────────────
  Future<void> _getUserLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLoadingLocation = false);
        _showSnack('Layanan lokasi (GPS) tidak aktif.');
        return;
      }
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
        _showSnack('Izin lokasi diblokir permanen.');
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      setState(() {
        _userPosition = position;
        _isLoadingLocation = false;
      });
      if (mounted) {
        context.read<PlaceProvider>().setUserLocation(
          position.latitude,
          position.longitude,
        );
      }
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(position.latitude, position.longitude),
          15,
        ),
      );
    } catch (e) {
      setState(() => _isLoadingLocation = false);
      _showSnack('Gagal menemukan lokasi.');
    }
  }

  // ── Custom Marker ──────────────────────────────────────────
  Future<BitmapDescriptor> _createCustomMarker(
    String categoryName,
    String placeName,
  ) async {
    final color    = _getCategoryColor(categoryName);
    final iconData = _getCategoryIcon(categoryName, placeName);

    const double circleRadius = 60.0;
    const double pinWidth     = circleRadius * 2 + 8;
    const double tailHeight   = 28.0;
    const double circleY      = circleRadius + 4;
    const double totalHeight  = circleY + circleRadius + tailHeight + 4;
    const double iconSize     = 58.0;

    final shortName = placeName.length > 20
        ? '${placeName.substring(0, 20)}...'
        : placeName;

    final textPainterMeasure = TextPainter(
      text: TextSpan(
        text: shortName,
        style: const TextStyle(
          fontSize:   44,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final double labelWidth   = textPainterMeasure.width + 8;
    final double canvasWidth  = labelWidth > pinWidth ? labelWidth : pinWidth;
    final double canvasHeight = totalHeight + textPainterMeasure.height + 6;

    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    final double centerX = canvasWidth / 2;

    // ── Shadow ────────────────────────────────────────────
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(
      Offset(centerX + 2, circleY + 2),
      circleRadius,
      shadowPaint,
    );

    // ── Lingkaran utama ───────────────────────────────────
    canvas.drawCircle(
      Offset(centerX, circleY),
      circleRadius,
      Paint()..color = color,
    );

    // ── Border putih ──────────────────────────────────────
    canvas.drawCircle(
      Offset(centerX, circleY),
      circleRadius,
      Paint()
        ..color      = Colors.white
        ..strokeWidth = 4
        ..style      = PaintingStyle.stroke,
    );

    // ── Ekor pin ──────────────────────────────────────────
    final tailPath = Path()
      ..moveTo(centerX - 10, circleY + circleRadius - 2)
      ..lineTo(centerX + 10, circleY + circleRadius - 2)
      ..lineTo(centerX,      circleY + circleRadius + tailHeight)
      ..close();
    canvas.drawPath(tailPath, Paint()..color = color);

    // ── Icon ──────────────────────────────────────────────
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontSize:   iconSize,
          fontFamily: iconData.fontFamily,
          color:      Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    iconPainter.paint(
      canvas,
      Offset(
        centerX - iconPainter.width / 2,
        circleY - iconPainter.height / 2,
      ),
    );

    // ── Nama lokasi dengan outline ────────────────────────
    final double labelY = circleY + circleRadius + tailHeight + 4;
    final double labelX = centerX - textPainterMeasure.width / 2;

    // Outline hitam 8 arah
    final outlinePainter = TextPainter(
      text: TextSpan(
        text: shortName,
        style: const TextStyle(
          fontSize:   44,
          fontWeight: FontWeight.w700,
          color:      Colors.black,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const offsets = [
      Offset(-1, -1), Offset(0, -1), Offset(1, -1),
      Offset(-1,  0),                Offset(1,  0),
      Offset(-1,  1), Offset(0,  1), Offset(1,  1),
    ];
    for (final o in offsets) {
      outlinePainter.paint(canvas, Offset(labelX + o.dx, labelY + o.dy));
    }

    // Teks utama — warna sesuai kategori
    final labelPainter = TextPainter(
      text: TextSpan(
        text: shortName,
        style: TextStyle(
          fontSize:   44,
          fontWeight: FontWeight.w700,
          color:      color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    labelPainter.paint(canvas, Offset(labelX, labelY));

    final picture = recorder.endRecording();
    final image   = await picture.toImage(
      canvasWidth.toInt() + 4,
      canvasHeight.toInt() + 4,
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  Color _getCategoryColor(String? name) {
    switch (name) {
      case 'Museum':
        return const Color(0xFF4CAF50);
      case 'Monumen & Tugu':
        return const Color(0xFF2196F3);
      case 'Bangunan Kolonial':
        return const Color(0xFFFF9800);
      case 'Kawasan Bersejarah':
        return const Color(0xFF9C27B0);
      case 'Tempat Ibadah Bersejarah':
        return const Color(0xFFE91E63);
      default:
        return const Color(0xFF1E3A5F);
    }
  }

  IconData _getCategoryIcon(String? categoryName, String placeName) {
    if (categoryName == 'Tempat Ibadah Bersejarah') {
      final lower = placeName.toLowerCase();
      if (lower.contains('masjid')) return Icons.mosque;
      if (lower.contains('gereja') || lower.contains('church'))
        return Icons.church;
      if (lower.contains('klenteng') || lower.contains('vihara'))
        return Icons.temple_hindu;
      return Icons.place;
    }
    switch (categoryName) {
      case 'Museum':
        return Icons.museum;
      case 'Monumen & Tugu':
        return Icons.account_balance;
      case 'Bangunan Kolonial':
        return Icons.domain;
      case 'Kawasan Bersejarah':
        return Icons.location_city;
      default:
        return Icons.place;
    }
  }

  // ── Markers ────────────────────────────────────────────────
  Future<void> _buildMarkers() async {
    final places = context.read<PlaceProvider>().allPlaces;
    final markers = <Marker>{};

    for (final place in places) {
      final icon = await _createCustomMarker(
        place.category?.name ?? '',
        place.name,
      );
      markers.add(
        Marker(
          markerId: MarkerId(place.id.toString()),
          position: LatLng(place.lat, place.lng),
          icon: icon,
          anchor: const Offset(0.5, 1.0),
          onTap: () => _onMarkerTapped(place),
        ),
      );
    }
    setState(() => _markers = markers);
  }

  void _onMarkerTapped(PlaceModel place) {
    final screenHeight = MediaQuery.of(context).size.height;
    setState(() {
      _selectedPlace = place;
      _polylines = {};
      _showBottomSheet = true;
      _isHoursExpanded = false;
      _slidePage = 0;
      _bottomSheetHeight = screenHeight * 0.48;
    });
    _mapController?.animateCamera(
      CameraUpdate.newLatLng(LatLng(place.lat - 0.003, place.lng)),
    );
  }

  void _closeBottomSheet() {
    setState(() {
      _showBottomSheet = false;
      _polylines = {};
      _bottomSheetHeight = 0;
    });
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _selectedPlace = null);
    });
  }

  // ── Routing via OSRM ───────────────────────────────────────
  Future<void> _getRoute(PlaceModel destination) async {
    if (_userPosition == null) {
      _showSnack('Lokasi kamu belum ditemukan.');
      return;
    }
    setState(() {
      _isLoadingRoute = true;
      _polylines = {};
    });
    try {
      final url =
          'http://router.project-osrm.org/route/v1/driving/'
          '${_userPosition!.longitude},${_userPosition!.latitude};'
          '${destination.lng},${destination.lat}'
          '?overview=full&geometries=polyline';

      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 'Ok' && data['routes'].isNotEmpty) {
          final encoded = data['routes'][0]['geometry'] as String;
          final distance = (data['routes'][0]['distance'] as num).toDouble();
          final duration = (data['routes'][0]['duration'] as num).toDouble();

          final points = PolylinePoints()
              .decodePolyline(encoded)
              .map((p) => LatLng(p.latitude, p.longitude))
              .toList();

          setState(() {
            _polylines = {
              Polyline(
                polylineId: const PolylineId('route'),
                points: points,
                color: const Color(0xFF1E3A5F),
                width: 5,
              ),
            };
            _isLoadingRoute = false;
          });

          if (points.isNotEmpty && _mapController != null) {
            double minLat = points
                .map((p) => p.latitude)
                .reduce((a, b) => a < b ? a : b);
            double maxLat = points
                .map((p) => p.latitude)
                .reduce((a, b) => a > b ? a : b);
            double minLng = points
                .map((p) => p.longitude)
                .reduce((a, b) => a < b ? a : b);
            double maxLng = points
                .map((p) => p.longitude)
                .reduce((a, b) => a > b ? a : b);
            _mapController!.animateCamera(
              CameraUpdate.newLatLngBounds(
                LatLngBounds(
                  southwest: LatLng(minLat, minLng),
                  northeast: LatLng(maxLat, maxLng),
                ),
                80,
              ),
            );
          }

          final km = (distance / 1000).toStringAsFixed(1);
          final min = (duration / 60).round();
          _showSnack('Rute ditemukan: $km km • ±$min menit berkendara');
        }
      }
    } catch (e) {
      setState(() => _isLoadingRoute = false);
      _showSnack('Gagal mengambil rute. Periksa koneksi internet.');
    }
  }

  // ── Fit all markers ────────────────────────────────────────
  void _fitAllMarkers() {
    if (_markers.isEmpty || _mapController == null) return;
    double minLat = 90, maxLat = -90;
    double minLng = 180, maxLng = -180;
    for (final m in _markers) {
      if (m.position.latitude < minLat) minLat = m.position.latitude;
      if (m.position.latitude > maxLat) maxLat = m.position.latitude;
      if (m.position.longitude < minLng) minLng = m.position.longitude;
      if (m.position.longitude > maxLng) maxLng = m.position.longitude;
    }
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  // ── Jam buka hari ini ──────────────────────────────────────
  String _getTodayHours(List<String> hours) {
    if (hours.isEmpty) return 'Jam buka tidak tersedia';
    final days = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu',
    ];
    final today = days[DateTime.now().weekday - 1];
    for (final h in hours) {
      if (h.toLowerCase().contains(today.toLowerCase())) return h;
    }
    return hours.first;
  }

  bool _isOpenNow(List<String> hours) {
    if (hours.isEmpty) return false;
    final todayHours = _getTodayHours(hours);
    final timeRegex = RegExp(
      r'(\d{1,2})[.:](\d{2})\s*[-–]\s*(\d{1,2})[.:](\d{2})',
    );
    final match = timeRegex.firstMatch(todayHours);
    if (match == null) return false;
    final now = TimeOfDay.now();
    final openH = int.parse(match.group(1)!);
    final openM = int.parse(match.group(2)!);
    final closeH = int.parse(match.group(3)!);
    final closeM = int.parse(match.group(4)!);
    final nowMinutes = now.hour * 60 + now.minute;
    final openMin = openH * 60 + openM;
    final closeMin = closeH * 60 + closeM;
    return nowMinutes >= openMin && nowMinutes <= closeMin;
  }

  // ── Build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Peta Lokasi'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              _buildMarkers();
              _fitAllMarkers();
            },
            tooltip: 'Tampilkan Semua Lokasi',
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Google Map ──────────────────────────────────────
          GoogleMap(
            initialCameraPosition: _surabayaCenter,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            mapType: MapType.normal,
            zoomControlsEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              _buildMarkers();
              if (_userPosition != null) {
                controller.animateCamera(
                  CameraUpdate.newLatLngZoom(
                    LatLng(_userPosition!.latitude, _userPosition!.longitude),
                    15,
                  ),
                );
              }
            },
            onTap: (_) => _closeBottomSheet(),
          ),

          // ── Loading lokasi ──────────────────────────────────
          if (_isLoadingLocation)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
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

          // ── Loading rute ────────────────────────────────────
          if (_isLoadingRoute)
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Menghitung rute...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Tombol lokasi user ──────────────────────────────
          Positioned(
            bottom: _showBottomSheet ? _bottomSheetHeight + 16 : 30,
            right: 16,
            child: AnimatedSlide(
              offset: Offset.zero,
              duration: const Duration(milliseconds: 300),
              child: FloatingActionButton(
                mini: true,
                backgroundColor: Colors.white,
                onPressed: _getUserLocation,
                child: const Icon(Icons.my_location, color: Color(0xFF1E3A5F)),
              ),
            ),
          ),

          // ── Legend ──────────────────────────────────────────
           if (!_showBottomSheet)
            Positioned(
              bottom: 30,
              left: 16,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LegendItem(color: const Color(0xFF4CAF50), label: 'Museum',             icon: Icons.museum),
                    _LegendItem(color: const Color(0xFF2196F3), label: 'Monumen & Tugu',     icon: Icons.account_balance),
                    _LegendItem(color: const Color(0xFFFF9800), label: 'Bangunan Kolonial',  icon: Icons.domain),
                    _LegendItem(color: const Color(0xFF9C27B0), label: 'Kawasan Bersejarah', icon: Icons.location_city),
                    _LegendItem(color: const Color(0xFFE91E63), label: 'Tempat Ibadah:',     icon: Icons.place, isIbadah: true),
                  ],
                ),
              ),
            ),

          // ── Bottom sheet dengan animasi slide ───────────────
           if (_showBottomSheet && _selectedPlace != null)
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                final screenHeight = MediaQuery.of(context).size.height;
                final newHeight = notification.extent * screenHeight;
                if (mounted && (newHeight - _bottomSheetHeight).abs() > 1) {
                  setState(() => _bottomSheetHeight = newHeight);
                }
                // Tutup jika diturunkan sampai paling bawah
                if (notification.extent <= 0.16) {
                  _closeBottomSheet();
                }
                return true;
              },
              child: DraggableScrollableSheet(
                initialChildSize: 0.48,
                minChildSize: 0.15,
                maxChildSize: 0.82,
                snap: true,
                snapSizes: const [0.15, 0.48, 0.82],
                builder: (context, scrollController) {
                  return _buildBottomSheet(_selectedPlace!, scrollController);
                },
              ),
            ),
        ],
      ),
    );
  }

  // ── Bottom Sheet Content ───────────────────────────────────
  Widget _buildBottomSheet(PlaceModel place, ScrollController scrollController) {
    final isOpen = _isOpenNow(place.openingHours);
    final todayHours = _getTodayHours(place.openingHours);
    final shortDesc = place.description.length > 120
        ? '${place.description.substring(0, 120)}...'
        : place.description;
    final screenHeight = MediaQuery.of(context).size.height;
    final isExpanded = _bottomSheetHeight > screenHeight * 0.6;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10)],
      ),
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.zero,
        shrinkWrap: true,
        children: [
          // ── Handle bar ────────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Level EXPANDED: foto slideshow besar ──
          if (isExpanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 180,
                      child: PageView.builder(
                        itemCount: place.photos.isNotEmpty ? place.photos.length : 1,
                        onPageChanged: (i) => setState(() => _slidePage = i),
                        itemBuilder: (_, i) {
                          if (place.photos.isEmpty) {
                            return Container(
                              color: _getCategoryColor(place.category?.name).withOpacity(0.1),
                              child: Icon(
                                _getCategoryIcon(place.category?.name ?? '', place.name),
                                size: 60,
                                color: _getCategoryColor(place.category?.name),
                              ),
                            );
                          }
                          return Image.network(
                            place.photos[i],
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => Container(
                              color: _getCategoryColor(place.category?.name).withOpacity(0.1),
                              child: Icon(
                                _getCategoryIcon(place.category?.name ?? '', place.name),
                                size: 60,
                                color: _getCategoryColor(place.category?.name),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (place.photos.length > 1) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        place.photos.length,
                        (i) => AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: _slidePage == i ? 16 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _slidePage == i
                                ? const Color(0xFF1E3A5F)
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Info utama ────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Foto kotak kecil — hanya saat TIDAK expanded
                    if (!isExpanded) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: place.photos.isNotEmpty
                            ? Image.network(
                                place.photos[0],
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 80,
                                  height: 80,
                                  color: _getCategoryColor(place.category?.name).withOpacity(0.1),
                                  child: Icon(
                                    _getCategoryIcon(place.category?.name ?? '', place.name),
                                    size: 32,
                                    color: _getCategoryColor(place.category?.name),
                                  ),
                                ),
                              )
                            : Container(
                                width: 80,
                                height: 80,
                                color: _getCategoryColor(place.category?.name).withOpacity(0.1),
                                child: Icon(
                                  _getCategoryIcon(place.category?.name ?? '', place.name),
                                  size: 32,
                                  color: _getCategoryColor(place.category?.name),
                                ),
                              ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    // Nama, kategori, rating
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E3A5F),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (place.category != null) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _getCategoryColor(place.category!.name).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                place.category!.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _getCategoryColor(place.category!.name),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.star, size: 14, color: Colors.amber),
                              const SizedBox(width: 4),
                              Text(
                                '${place.avgRating.toStringAsFixed(1)} (${place.reviewCount})',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 10),
                              Consumer<PlaceProvider>(
                                builder: (_, pp, __) {
                                  final dist = pp.distanceTo(place.lat, place.lng);
                                  if (dist == null) return const SizedBox.shrink();
                                  return Row(
                                    children: [
                                      const Icon(Icons.directions_walk, size: 14, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(
                                        dist < 1000
                                            ? '${dist.toStringAsFixed(0)} m'
                                            : '${(dist / 1000).toStringAsFixed(1)} km',
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Alamat (selalu tampil) ────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on, size: 14, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(child: Text(place.address, style: const TextStyle(fontSize: 12, color: Colors.black87))),
                  ],
                ),

                // ── Telepon ───────────────────────────
                if (place.phone.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.phone, size: 14, color: Colors.green),
                    const SizedBox(width: 6),
                    Text(place.phone, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                  ]),
                ],

                // ── Website ───────────────────────────
                if (place.website.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.language, size: 14, color: Colors.blue),
                    const SizedBox(width: 6),
                    Expanded(child: Text(place.website, style: const TextStyle(fontSize: 12, color: Colors.blue), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ],

                // ── Jam buka ──────────────────────────
                if (place.openingHours.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setState(() => _isHoursExpanded = !_isHoursExpanded),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Column(children: [
                        Row(children: [
                          Icon(Icons.access_time, size: 14, color: isOpen ? Colors.green : Colors.red),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isOpen ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(isOpen ? 'Buka' : 'Tutup', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isOpen ? Colors.green : Colors.red)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text(todayHours, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Icon(_isHoursExpanded ? Icons.expand_less : Icons.expand_more, size: 16, color: Colors.grey),
                        ]),
                        if (_isHoursExpanded) ...[
                          const SizedBox(height: 8),
                          const Divider(height: 1),
                          const SizedBox(height: 8),
                          ...place.openingHours.map((h) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(children: [const SizedBox(width: 20), Text(h, style: const TextStyle(fontSize: 12))]),
                          )),
                        ],
                      ]),
                    ),
                  ),
                ],

                // ── Deskripsi ─────────────────────────
                if (place.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.5),
                      children: [
                        TextSpan(text: shortDesc),
                        if (place.description.length > 120)
                          const TextSpan(
                            text: ' lihat lebih lengkap di detail lokasi',
                            style: TextStyle(color: Color(0xFF1E3A5F), fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // ── Tombol aksi ───────────────────────
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: _isLoadingRoute
                            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.directions, size: 18),
                        label: Text(_isLoadingRoute ? 'Menghitung...' : 'Tampilkan Rute'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A5F),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _isLoadingRoute ? null : () => _getRoute(place),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.info_outline, size: 18),
                        label: const Text('Lihat Detail'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1E3A5F),
                          side: const BorderSide(color: Color(0xFF1E3A5F)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DetailScreen(placeId: place.id)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Legend Item ─────────────────────────────────────────────
class _LegendItem extends StatelessWidget {
  final Color    color;
  final String   label;
  final IconData icon;
  final bool     isIbadah;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.icon,
    this.isIbadah = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle),
                child: Icon(icon, size: 13, color: Colors.white),
              ),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
          if (isIbadah) ...[
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(width: 28),
                Icon(Icons.mosque,        size: 13, color: Colors.black54),
                SizedBox(width: 6),
                Icon(Icons.church,        size: 13, color: Colors.black54),
                SizedBox(width: 6),
                Icon(Icons.temple_hindu,  size: 13, color: Colors.black54),
              ],
            ),
          ],
        ],
      ),
    );
  }
}