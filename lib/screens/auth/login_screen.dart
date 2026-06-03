import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey       = GlobalKey<FormState>();
  final _emailCtrl     = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  bool  _obscurePass   = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final auth    = context.read<AuthProvider>();
    final success = await auth.login(
      _emailCtrl.text.trim(),
      _passwordCtrl.text.trim(),
    );

    if (success && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
  onTap: () => FocusScope.of(context).unfocus(),
  child: Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(title: const Text('Masuk')),
    body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Icon(
                Icons.location_city,
                size:  80,
                color: Color(0xFF1E3A5F),
              ),
              const SizedBox(height: 16),
              const Text(
                'Selamat Datang',
                style: TextStyle(
                  fontSize:   28,
                  fontWeight: FontWeight.bold,
                  color:      Color(0xFF1E3A5F),
                ),
              ),
              const Text(
                'Masuk untuk mengakses semua fitur',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              // Email
              TextFormField(
                controller:  _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText:    'Email',
                  prefixIcon:   const Icon(Icons.email_outlined),
                  border:       OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Email wajib diisi';
                  if (!v.contains('@')) return 'Format email tidak valid';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Password
              TextFormField(
                controller:  _passwordCtrl,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  labelText:  'Password',
                  prefixIcon: const Icon(Icons.lock_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePass
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Password wajib diisi';
                  if (v.length < 6) return 'Password minimal 6 karakter';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              // Pesan error
              Consumer<AuthProvider>(
                builder: (_, auth, __) => auth.errorMessage != null
                    ? Container(
                        padding: const EdgeInsets.all(12),
                        margin:  const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color:        Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Text(
                          auth.errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              // Tombol login
              Consumer<AuthProvider>(
                builder: (_, auth, __) => SizedBox(
                  width:  double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: auth.isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A5F),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: auth.isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Masuk',
                            style: TextStyle(
                              fontSize:   16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Link ke register
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Belum punya akun? '),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RegisterScreen(),
                      ),
                    ),
                    child: const Text(
                      'Daftar',
                      style: TextStyle(
                        color:      Color(0xFF1E3A5F),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}