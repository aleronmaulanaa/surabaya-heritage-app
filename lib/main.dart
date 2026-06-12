import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'utils/app_notification.dart';
import 'providers/auth_provider.dart';
import 'providers/place_provider.dart';
import 'providers/bookmark_provider.dart';
import 'screens/home/home_screen.dart';
import 'screens/auth/login_screen.dart';
import 'utils/constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PlaceProvider()),
        ChangeNotifierProvider(create: (_) => BookmarkProvider()),
      ],
      child: MaterialApp(
        title:          AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E3A5F),
          ),
          useMaterial3:       true,
          fontFamily:         'Roboto',
          appBarTheme: const AppBarTheme(
            backgroundColor:  Color(0xFF1E3A5F),
            foregroundColor:  Colors.white,
            elevation:        0,
          ),
        ),
        home: const AppEntry(),
      ),
    );
  }
}

class AppEntry extends StatefulWidget {
  const AppEntry({super.key});

  @override
  State<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<AppEntry> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final authProvider = context.read<AuthProvider>();
    await authProvider.checkLoginStatus();

    final placeProvider = context.read<PlaceProvider>();
    await placeProvider.fetchPlaces();
    await placeProvider.fetchCategories();

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1E3A5F),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_city, size: 80, color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Surabaya Heritage Map',
                style: TextStyle(
                  color:      Colors.white,
                  fontSize:   24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 32),
              CircularProgressIndicator(color: Colors.white),
            ],
          ),
        ),
      );
    }

    return const ConnectivityWrapper(child: HomeScreen());
  }
}

class ConnectivityWrapper extends StatefulWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  late final StreamSubscription<List<ConnectivityResult>> _subscription;
  bool _dialogShowing = false;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.every((r) => r == ConnectivityResult.none);
      if (offline && !_dialogShowing) {
        _wasOffline = true;
        _showOfflineDialog();
      } else if (!offline && _dialogShowing) {
        Navigator.of(context).pop();
        _showOnlineBanner();
      } else if (!offline && _wasOffline && !_dialogShowing) {
        _wasOffline = false;
        _showOnlineBanner();
      }
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  void _showOnlineBanner() {
    _wasOffline = false;
    AppNotification.show(
      context,
      message: 'Koneksi internet kembali terhubung',
      type: NotifType.success,
    );
  }

  void _showOfflineDialog() {
    _dialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _OfflineDialog(
        onClose: () => Navigator.of(ctx).pop(),
        onRetry: () async {
          final results = await Connectivity().checkConnectivity();
          final stillOffline = results.every((r) => r == ConnectivityResult.none);
          if (stillOffline) return false;
          if (!ctx.mounted) return false;
          Navigator.of(ctx).pop();
          return true;
        },
      ),
    ).then((_) => _dialogShowing = false);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _OfflineDialog extends StatefulWidget {
  final VoidCallback onClose;
  final Future<bool> Function() onRetry;
  const _OfflineDialog({required this.onClose, required this.onRetry});

  @override
  State<_OfflineDialog> createState() => _OfflineDialogState();
}

class _OfflineDialogState extends State<_OfflineDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  bool _checking = false;

  @override
  void dispose() {
    _spinCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleRetry() async {
    if (_checking) return;
    setState(() => _checking = true);
    await _spinCtrl.forward(from: 0);
    final ok = await widget.onRetry();
    if (!ok && mounted) {
      _spinCtrl.reset();
      setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_rounded, size: 48, color: Color(0xFFE53935)),
                const SizedBox(height: 16),
                const Text(
                  'Koneksi Terputus',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Aplikasi ini memerlukan koneksi internet untuk memuat peta, rute, dan data lokasi. '
                  'Silakan periksa koneksi WiFi atau data seluler Anda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _handleRetry,
                  icon: RotationTransition(
                    turns: _spinCtrl,
                    child: const Icon(Icons.refresh),
                  ),
                  label: Text(_checking ? 'Memeriksa...' : 'Coba Lagi'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            right: 4,
            top: 4,
            child: IconButton(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFFFCDD2),
                foregroundColor: const Color(0xFFE53935),
                padding: const EdgeInsets.all(4),
                minimumSize: const Size(32, 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}