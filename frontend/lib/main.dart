import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:fl_chart/fl_chart.dart';

import 'firebase_options.dart';
import 'quality_page.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

part 'stations_page.dart';
part 'consumption.dart';

String get kBackendBase => dotenv.env['BACKEND_BASE_URL'] ?? 'http://127.0.0.1:8000';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint("Could not load .env file: $e");
  }
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const SmartFuelApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// THEME
// ─────────────────────────────────────────────────────────────────────────────
class AppTheme extends ChangeNotifier {
  static final AppTheme _i = AppTheme._();
  factory AppTheme() => _i;
  AppTheme._();

  static const Map<String, Color> accents = {
    'Emerald': Color(0xFF2ECC71),
    'Cyan': Color(0xFF00BCD4),
    'Amber': Color(0xFFFFC107),
    'Rose': Color(0xFFFF4E7A),
    'Violet': Color(0xFF8B5CF6),
  };

  String _accentName =
      'Emerald'; // to change default accent colors we prefered Emerald
  String get accentName => _accentName;
  Color get accent => accents[_accentName]!;

  void setAccent(String name) {
    if (accents.containsKey(name)) {
      _accentName = name;
      notifyListeners();
    }
  }
}

final appTheme = AppTheme();

// ─────────────────────────────────────────────────────────────────────────────
// THEME MODE NOTIFIER  (dark / light)
// ─────────────────────────────────────────────────────────────────────────────
class ThemeModeNotifier extends ChangeNotifier {
  static final ThemeModeNotifier _i = ThemeModeNotifier._();
  factory ThemeModeNotifier() => _i;
  ThemeModeNotifier._();

  ThemeMode _mode = ThemeMode.dark; //dark to light for default theme
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  void set(ThemeMode m) {
    _mode = m;
    notifyListeners();
  }
}

final themeModeNotifier = ThemeModeNotifier();

class SF {
  // ── Dark-mode base colours ─────────────────────────────────────────────────
  static const _bgDark = Color(0xFF07110F);
  static const _cardDark = Color(0xFF0B1A16);
  static const _mutedDark = Color(0xFF9BBFB0);
  static const _textDark = Color(0xFFE8F6EF);

  // ── Light-mode base colours ────────────────────────────────────────────────
  static const _bgLight = Color(0xFFF4FBF8);
  static const _cardLight = Color(0xFFE8F5EF);
  static const _mutedLight = Color(0xFF4A7A65);
  static const _textLight = Color(0xFF0D1F18);

  // ── Theme-aware getters ────────────────────────────────────────────────────
  static Color get bg => themeModeNotifier.isDark ? _bgDark : _bgLight;
  static Color get card => themeModeNotifier.isDark ? _cardDark : _cardLight;
  static Color get muted => themeModeNotifier.isDark ? _mutedDark : _mutedLight;
  static Color get text => themeModeNotifier.isDark ? _textDark : _textLight;

  static Color get green => appTheme.accent;
  static Color get greenDark => _darken(appTheme.accent, 0.18);

  // In light mode use a black tint for borders/overlays instead of white
  static Color glass(double a) => themeModeNotifier.isDark
      ? Colors.white.withAlpha((a * 255).round())
      : Colors.black.withAlpha((a * 255).round());

  // Lighter shadow in light mode
  static Color shadow() => themeModeNotifier.isDark
      ? const Color(0xFF020604).withAlpha(153)
      : const Color(0xFF0D2018).withAlpha(30);

  static Color _darken(Color c, double a) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness - a).clamp(0.0, 1.0)).toColor();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// APP
// ─────────────────────────────────────────────────────────────────────────────
class SmartFuelApp extends StatefulWidget {
  const SmartFuelApp({super.key});
  @override
  State<SmartFuelApp> createState() => _SmartFuelAppState();
}

class _SmartFuelAppState extends State<SmartFuelApp> {
  @override
  void initState() {
    super.initState();
    appTheme.addListener(() => setState(() {}));
    themeModeNotifier.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    themeModeNotifier.removeListener(() => setState(() {}));
    super.dispose();
  }

  // Shared dark theme (used as darkTheme and standalone dark)
  ThemeData _darkTheme() => ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: SF.bg,
        textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme)
            .apply(bodyColor: SF.text, displayColor: SF.text),
        colorScheme: ColorScheme.dark(primary: SF.green, secondary: SF.green),
      );

  // Light theme
  ThemeData _lightTheme() => ThemeData.light(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFFF4FBF8),
        textTheme: GoogleFonts.dmSansTextTheme(ThemeData.light().textTheme)
            .apply(
                bodyColor: const Color(0xFF0D1F18),
                displayColor: const Color(0xFF0D1F18)),
        colorScheme: ColorScheme.light(
          primary: SF.green,
          secondary: SF.green,
          surface: const Color(0xFFE8F5EF),
          onSurface: const Color(0xFF0D1F18),
          outline: const Color(0xFFB8D8C8),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFE8F5EF),
          foregroundColor: Color(0xFF0D1F18),
          elevation: 0,
          iconTheme: IconThemeData(color: Color(0xFF0D1F18)),
        ),
        cardColor: const Color(0xFFE8F5EF),
        dividerColor: const Color(0xFFB8D8C8),
        iconTheme: const IconThemeData(color: Color(0xFF0D1F18)),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFDFF0E8),
          hintStyle: const TextStyle(color: Color(0xFF4A7A65)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFB8D8C8)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFB8D8C8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2ECC71), width: 1.5),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? const Color(0xFF2ECC71)
                  : const Color(0xFFB8D8C8)),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? const Color(0xFF2ECC71).withAlpha(80)
                  : const Color(0xFFD0E8DC)),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFFE8F5EF),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: Color(0xFF0D1F18),
          iconColor: Color(0xFF0D1F18),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartFuel',
      debugShowCheckedModeBanner: false,
      themeMode: themeModeNotifier.mode,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      home: const AuthGate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// AUTH GATE
// ─────────────────────────────────────────────────────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _Loader();
        }
        if (snap.data == null) return const LoginPage();
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(snap.data!.uid)
              .get(),
          builder: (_, ps) {
            if (!ps.hasData) return const _Loader();
            if (!ps.data!.exists) {
              return RegisterPage(prefillEmail: snap.data!.email ?? '');
            }
            return const DashboardShell();
          },
        );
      },
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SF.bg,
      body: Center(child: CircularProgressIndicator(color: SF.green)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOGIN
// ─────────────────────────────────────────────────────────────────────────────
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginState();
}

class _LoginState extends State<LoginPage> {
  final _em = TextEditingController();
  final _pw = TextEditingController();
  bool _loading = false;

  static const _validEmailDomains = [
    'gmail.com',
    'hotmail.com',
    'yahoo.com',
    'outlook.com',
    'live.com',
    'icloud.com',
    'msn.com',
    'protonmail.com',
  ];

  String? _validateEmail(String v) {
    final clean = v.trim().toLowerCase();
    if (clean.isEmpty) return 'Email is required';

    final atIndex = clean.indexOf('@');
    if (atIndex < 1 || atIndex != clean.lastIndexOf('@')) {
      return 'Enter a valid email address';
    }

    final localPart = clean.substring(0, atIndex);
    final domain = clean.substring(atIndex + 1);

    if (!RegExp(r'^[a-z0-9][a-z0-9._%+\-]+$').hasMatch(localPart)) {
      return 'Enter a valid email address';
    }

    if (!_validEmailDomains.contains(domain)) {
      return 'Please enter a valid email from supported providers '
          '(gmail.com, hotmail.com, yahoo.com, outlook.com, live.com, '
          'icloud.com, msn.com, protonmail.com)';
    }

    return null;
  }

  Future<void> _login() async {
    final emailErr = _validateEmail(_em.text);
    if (emailErr != null) {
      _snack(emailErr);
      return;
    }
    if (_pw.text.isEmpty) {
      _snack('Password is required');
      return;
    }

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _em.text.trim(),
        password: _pw.text,
      );
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: Colors.redAccent));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SF.bg,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _GlassCard(
                width: 420,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _LogoRow(),
                    const SizedBox(height: 20),
                    Text('Sign In',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: SF.green)),
                    const SizedBox(height: 4),
                    Text('Welcome back to SmartFuel',
                        style: TextStyle(color: SF.muted, fontSize: 13)),
                    const SizedBox(height: 22),
                    _SFInput(
                        ctrl: _em, hint: 'Email', icon: Icons.email_outlined),
                    const SizedBox(height: 12),
                    _SFInput(
                        ctrl: _pw,
                        hint: 'Password',
                        icon: Icons.lock_outline,
                        obscure: true),
                    const SizedBox(height: 20),
                    _GradBtn(
                        text: _loading ? 'Signing in…' : 'Login',
                        onTap: _loading ? null : _login),
                    const SizedBox(height: 14),
                    Center(
                      child: GestureDetector(
                        onTap: () => Navigator.push(
                            context, _fade(const CreateAccountPage())),
                        child: RichText(
                          text: TextSpan(
                            text: 'No account? ',
                            style: TextStyle(color: SF.muted, fontSize: 13),
                            children: [
                              TextSpan(
                                text: 'Create Account',
                                style: TextStyle(
                                    color: SF.green,
                                    fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: GestureDetector(
                        onTap: () async {
                          final uri = Uri(
                            scheme: 'mailto',
                            path: 'waleedawann14@gmail.com',
                            queryParameters: {
                              'subject': 'SmartFuel Complaint / Support',
                            },
                          );
                          try {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          } catch (_) {
                            await launchUrl(uri);
                          }
                        },
                        child: RichText(
                          text: TextSpan(
                            text: 'Issues? Contact: ',
                            style: TextStyle(
                                color: SF.muted.withAlpha(160), fontSize: 11),
                            children: [
                              TextSpan(
                                text: 'waleedawann14@gmail.com',
                                style: TextStyle(
                                    color: SF.green.withAlpha(200),
                                    fontSize: 11,
                                    decoration: TextDecoration.underline),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CREATE ACCOUNT
// ─────────────────────────────────────────────────────────────────────────────
class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});
  @override
  State<CreateAccountPage> createState() => _CreateAccountState();
}

class _CreateAccountState extends State<CreateAccountPage> {
  final _fn = TextEditingController();
  final _ph = TextEditingController();
  final _em = TextEditingController();
  final _pw = TextEditingController();
  final _vn = TextEditingController();
  final _vmake = TextEditingController(); // vehicle make e.g. Toyota
  final _vname = TextEditingController(); // vehicle name e.g. Corolla
  int? _selectedYear;
  double? _selectedTank;
  bool _loading = false;

  // ── Tank capacity options (label → liters) ────────────────────────────────
  static const List<Map<String, dynamic>> _tankOptions = [
    {'label': '8 L', 'liters': 8.0},
    {'label': '12 L', 'liters': 12.0},
    {'label': '25 L', 'liters': 25.0},
    {'label': '30 L', 'liters': 30.0},
    {'label': '35 L', 'liters': 35.0},
    {'label': '36 L', 'liters': 36.0},
    {'label': '40 L', 'liters': 40.0},
    {'label': '47 L', 'liters': 47.0},
    {'label': '50 L', 'liters': 50.0},
    {'label': '58 L', 'liters': 58.0},
    {'label': '60 L', 'liters': 60.0},
    {'label': '70 L', 'liters': 70.0},
    {'label': '80 L', 'liters': 80.0},
    {'label': '85 L', 'liters': 85.0},
  ];

  // ── Validation helpers ─────────────────────────────────────────────────────
  static final _validEmailDomains = [
    'gmail.com',
    'hotmail.com',
    'yahoo.com',
    'outlook.com',
    'live.com',
    'icloud.com',
    'msn.com',
    'protonmail.com',
    'mail.com',
  ];

  String? _validateName(String v) {
    if (v.trim().isEmpty) return 'Full name is required';
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(v.trim())) {
      return 'Name must contain letters only';
    }
    return null;
  }

  String? _validatePhone(String v) {
    final clean = v.trim();
    if (clean.isEmpty) return 'Phone number is required';
    if (!RegExp(r'^03\d{9}$').hasMatch(clean)) {
      return 'Phone must be 11 digits starting with 03';
    }
    return null;
  }

  String? _validateEmail(String v) {
    final clean = v.trim().toLowerCase();
    if (clean.isEmpty) return 'Email is required';

    // Must have exactly one '@'
    final atIndex = clean.indexOf('@');
    if (atIndex < 1 || atIndex != clean.lastIndexOf('@')) {
      return 'Enter a valid email address';
    }

    final localPart = clean.substring(0, atIndex);
    final domain = clean.substring(atIndex + 1);

    // Local part must be at least 2 characters, safe characters only
    if (!RegExp(r'^[a-z0-9][a-z0-9._%+\-]+$').hasMatch(localPart)) {
      return 'Enter a valid email address';
    }

    // Domain MUST be in the allowed list — everything else is rejected
    if (!_validEmailDomains.contains(domain)) {
      return 'Please enter a valid email from supported providers '
          '(gmail.com, hotmail.com, yahoo.com, outlook.com, live.com, '
          'icloud.com, msn.com, protonmail.com, mail.com)';
    }

    return null;
  }

  String? _validateVehicleNumber(String v) {
    final clean = v.trim().toUpperCase();
    if (clean.isEmpty) return 'Vehicle number is required';
    if (!RegExp(r'^[A-Z]{3}\d{2,4}$').hasMatch(clean)) {
      return 'Format: 3 letters then 2–4 digits (e.g. ABC1234)';
    }
    return null;
  }

  String? _validateMake(String v) {
    if (v.trim().isEmpty) return 'Vehicle make is required (e.g. Toyota)';
    return null;
  }

  String? _validateVehicleName(String v) {
    if (v.trim().isEmpty) return 'Vehicle name is required (e.g. Corolla)';
    return null;
  }

  Future<void> _create() async {
    // Run all validations
    final nameErr = _validateName(_fn.text);
    final phoneErr = _validatePhone(_ph.text);
    final emailErr = _validateEmail(_em.text);
    final vnErr = _validateVehicleNumber(_vn.text);
    final makeErr = _validateMake(_vmake.text);
    final vnameErr = _validateVehicleName(_vname.text);

    for (final e in [nameErr, phoneErr, emailErr, vnErr, makeErr, vnameErr]) {
      if (e != null) {
        _snack(e);
        return;
      }
    }
    if (_selectedYear == null) {
      _snack('Please select a model year');
      return;
    }
    if (_selectedTank == null) {
      _snack('Please select a tank capacity');
      return;
    }
    if (_pw.text.length < 8 ||
        !RegExp(r'(?=.*[a-zA-Z])(?=.*\d)').hasMatch(_pw.text)) {
      _snack(
          'Password must be at least 8 characters and contain both letters and numbers');
      return;
    }

    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _em.text.trim(),
        password: _pw.text,
      );
      final uid = cred.user!.uid;
      const vid = 'veh_1';
      final uRef = FirebaseFirestore.instance.collection('users').doc(uid);
      await uRef.set({
        'fullName': _fn.text.trim(),
        'phone': _ph.text.trim(),
        'email': _em.text.trim(),
        'activeVehicleId': vid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await uRef.collection('vehicles').doc(vid).set({
        'vehicleNumber': _vn.text.trim().toUpperCase(),
        'vehicleMake': _vmake.text.trim(),
        'vehicleName': _vname.text.trim(),
        'vehicleModel': '${_vmake.text.trim()} ${_vname.text.trim()}',
        'modelYear': _selectedYear,
        'tankCapacityL': _selectedTank,
      });
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      _snack(e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: Colors.redAccent));

  Widget _dropdownField({
    required IconData icon,
    required String hint,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: SF.bg.withAlpha(180),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SF.glass(0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: SF.muted, size: 18),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = List.generate(currentYear - 1980 + 1, (i) => currentYear - i);

    return Scaffold(
      backgroundColor: SF.bg,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _GlassCard(
                width: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Back arrow
                    Row(children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: SF.green.withAlpha(28),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: SF.green.withAlpha(60)),
                          ),
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              color: SF.green, size: 16),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _LogoRow(),
                    ]),
                    const SizedBox(height: 20),
                    Text('Create Account',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: SF.green)),
                    Text('Register and add your vehicle',
                        style: TextStyle(color: SF.muted, fontSize: 13)),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                          child: _SFInput(
                              ctrl: _fn,
                              hint: 'Full Name',
                              icon: Icons.person_outline)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _SFInput(
                              ctrl: _ph,
                              hint: 'Phone',
                              icon: Icons.phone_outlined)),
                    ]),
                    const SizedBox(height: 10),
                    _SFInput(
                        ctrl: _em, hint: 'Email', icon: Icons.email_outlined),
                    const SizedBox(height: 10),
                    _SFInput(
                        ctrl: _pw,
                        hint: 'Password (min 8 chars, letters and characters)',
                        icon: Icons.lock_outline,
                        obscure: true),
                    const SizedBox(height: 16),
                    _SectionLabel('Vehicle Details'),
                    const SizedBox(height: 10),
                    _SFInput(
                        ctrl: _vn,
                        hint: 'Vehicle Number(ABC1234)',
                        icon: Icons.directions_car_outlined),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _SFInput(
                              ctrl: _vmake,
                              hint: 'Make',
                              icon: Icons.garage_outlined)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _SFInput(
                              ctrl: _vname,
                              hint: 'Variant',
                              icon: Icons.car_repair)),
                    ]),
                    const SizedBox(height: 10),
                    // Year dropdown
                    _dropdownField(
                      icon: Icons.calendar_today_outlined,
                      hint: 'Model Year',
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _selectedYear,
                          isExpanded: true,
                          dropdownColor: SF.card,
                          style: TextStyle(color: SF.text, fontSize: 14),
                          hint: Text('Model Year',
                              style: TextStyle(color: SF.muted, fontSize: 14)),
                          menuMaxHeight: 280,
                          items: years
                              .map((y) => DropdownMenuItem(
                                    value: y,
                                    child: Text(y.toString()),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedYear = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Tank capacity dropdown
                    _dropdownField(
                      icon: Icons.local_gas_station_outlined,
                      hint: 'Tank Capacity',
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<double>(
                          value: _selectedTank,
                          isExpanded: true,
                          dropdownColor: SF.card,
                          style: TextStyle(color: SF.text, fontSize: 14),
                          hint: Text('Tank Capacity',
                              style: TextStyle(color: SF.muted, fontSize: 14)),
                          menuMaxHeight: 300,
                          items: _tankOptions
                              .map((t) => DropdownMenuItem<double>(
                                    value: t['liters'] as double,
                                    child: Text(t['label'] as String,
                                        style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedTank = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(
                          child: _GradBtn(
                              text: _loading ? 'Registering…' : 'Register',
                              onTap: _loading ? null : _create)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _OutlineBtn(
                              text: 'Back',
                              onTap: () => Navigator.pop(context))),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REGISTER (profile completion)
// ─────────────────────────────────────────────────────────────────────────────
class RegisterPage extends StatelessWidget {
  final String prefillEmail;
  const RegisterPage({super.key, required this.prefillEmail});
  @override
  Widget build(BuildContext context) =>
      _ProfileCompletePage(prefillEmail: prefillEmail);
}

class _ProfileCompletePage extends StatefulWidget {
  final String prefillEmail;
  const _ProfileCompletePage({required this.prefillEmail});
  @override
  State<_ProfileCompletePage> createState() => _ProfileCompleteState();
}

class _ProfileCompleteState extends State<_ProfileCompletePage> {
  final _fn = TextEditingController();
  final _ph = TextEditingController();
  late final _em = TextEditingController(text: widget.prefillEmail);
  final _vn = TextEditingController();
  final _vmake = TextEditingController();
  final _vname = TextEditingController();
  int? _selectedYear;
  double? _selectedTank;
  bool _loading = false;

  static const List<Map<String, dynamic>> _tankOptions = [
    {'label': 'Mini / Kei (10 L)', 'liters': 10.0},
    {'label': 'Suzuki Mehran / Alto (25 L)', 'liters': 25.0},
    {'label': 'Honda City / Civic (40 L)', 'liters': 40.0},
    {'label': 'Toyota Corolla Sedan (50 L)', 'liters': 50.0},
    {'label': 'Toyota Camry / Accord (60 L)', 'liters': 60.0},
    {'label': 'Honda CR-V / Compact SUV (58 L)', 'liters': 58.0},
    {'label': 'Toyota Fortuner / Prado (80 L)', 'liters': 80.0},
    {'label': 'Toyota Land Cruiser SUV (85 L)', 'liters': 85.0},
    {'label': 'Pickup / Hilux (80 L)', 'liters': 80.0},
    {'label': 'Van / Hi-Ace (70 L)', 'liters': 70.0},
    {'label': 'Truck / Bus (200 L)', 'liters': 200.0},
  ];

  static final _validEmailDomains = [
    'gmail.com',
    'hotmail.com',
    'yahoo.com',
    'outlook.com',
    'live.com',
    'icloud.com',
    'msn.com',
    'protonmail.com',
    'mail.com',
  ];

  String? _validateName(String v) {
    if (v.trim().isEmpty) return 'Full name is required';
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(v.trim())) {
      return 'Name must contain letters only';
    }
    return null;
  }

  String? _validatePhone(String v) {
    final clean = v.trim();
    if (clean.isEmpty) return 'Phone number is required';
    if (!RegExp(r'^03\d{9}$').hasMatch(clean)) {
      return 'Phone must be 11 digits starting with 03';
    }
    return null;
  }

  String? _validateEmail(String v) {
    final clean = v.trim().toLowerCase();
    if (clean.isEmpty) return 'Email is required';

    // Must have exactly one @, non-empty local part, valid domain format
    final emailRegex = RegExp(
      r'^[a-z0-9][a-z0-9._%+\-]{1,}@[a-z0-9\-]+\.[a-z]{2,}$',
    );
    if (!emailRegex.hasMatch(clean)) {
      return 'Enter a valid email address (e.g. user@gmail.com)';
    }

    final domain = clean.split('@')[1];
    if (!_validEmailDomains.contains(domain)) {
      return 'Please enter a valid email from supported providers'
          ' (gmail.com, hotmail.com, yahoo.com, outlook.com, etc.)';
    }
    return null;
  }

  String? _validateVehicleNumber(String v) {
    final clean = v.trim().toUpperCase();
    if (clean.isEmpty) return 'Vehicle number is required';
    if (!RegExp(r'^[A-Z]{3}\d{2,4}$').hasMatch(clean)) {
      return 'Format: 3 letters then 2–4 digits (e.g. ABC1234)';
    }
    return null;
  }

  Future<void> _save() async {
    final nameErr = _validateName(_fn.text);
    final phoneErr = _validatePhone(_ph.text);
    final emailErr = _validateEmail(_em.text);
    final vnErr = _validateVehicleNumber(_vn.text);

    for (final e in [nameErr, phoneErr, emailErr, vnErr]) {
      if (e != null) {
        _snack(e);
        return;
      }
    }
    if (_vmake.text.trim().isEmpty) {
      _snack('Vehicle make is required (e.g. Toyota)');
      return;
    }
    if (_vname.text.trim().isEmpty) {
      _snack('Vehicle name is required (e.g. Corolla)');
      return;
    }
    if (_selectedYear == null) {
      _snack('Please select a model year');
      return;
    }
    if (_selectedTank == null) {
      _snack('Please select a tank capacity');
      return;
    }

    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      const vid = 'veh_1';
      final uRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await uRef.set({
        'fullName': _fn.text.trim(),
        'phone': _ph.text.trim(),
        'email': _em.text.trim(),
        'activeVehicleId': vid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await uRef.collection('vehicles').doc(vid).set({
        'vehicleNumber': _vn.text.trim().toUpperCase(),
        'vehicleMake': _vmake.text.trim(),
        'vehicleName': _vname.text.trim(),
        'vehicleModel': '${_vmake.text.trim()} ${_vname.text.trim()}',
        'modelYear': _selectedYear,
        'tankCapacityL': _selectedTank,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString()), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), backgroundColor: Colors.redAccent));

  Widget _dropdownField({
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: SF.bg.withAlpha(180),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SF.glass(0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: SF.muted, size: 18),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentYear = DateTime.now().year;
    final years = List.generate(currentYear - 1980 + 1, (i) => currentYear - i);

    return Scaffold(
      backgroundColor: SF.bg,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _GlassCard(
                width: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Back arrow to dashboard
                    Row(children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pushAndRemoveUntil(
                          _fade(const DashboardShell()),
                          (_) => false,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: SF.green.withAlpha(28),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: SF.green.withAlpha(60)),
                          ),
                          child: Icon(Icons.arrow_back_ios_new_rounded,
                              color: SF.green, size: 16),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _LogoRow(),
                    ]),
                    const SizedBox(height: 20),
                    Text('Complete Profile',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: SF.green)),
                    const SizedBox(height: 20),
                    _SFInput(
                        ctrl: _fn,
                        hint: 'Full Name (letters only)',
                        icon: Icons.person_outline),
                    const SizedBox(height: 10),
                    _SFInput(
                        ctrl: _ph,
                        hint: 'Phone (03XXXXXXXXX)',
                        icon: Icons.phone_outlined),
                    const SizedBox(height: 10),
                    _SFInput(
                        ctrl: _em,
                        hint: 'Email (e.g. user@gmail.com)',
                        icon: Icons.email_outlined),
                    const SizedBox(height: 16),
                    _SectionLabel('Vehicle Details'),
                    const SizedBox(height: 10),
                    _SFInput(
                        ctrl: _vn,
                        hint: 'Vehicle Number (e.g. ABC1234)',
                        icon: Icons.directions_car_outlined),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                          child: _SFInput(
                              ctrl: _vmake,
                              hint: 'Make (e.g. Toyota)',
                              icon: Icons.garage_outlined)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: _SFInput(
                              ctrl: _vname,
                              hint: 'Name (e.g. Corolla)',
                              icon: Icons.car_repair)),
                    ]),
                    const SizedBox(height: 10),
                    _dropdownField(
                      icon: Icons.calendar_today_outlined,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _selectedYear,
                          isExpanded: true,
                          dropdownColor: SF.card,
                          style: TextStyle(color: SF.text, fontSize: 14),
                          hint: Text('Model Year',
                              style: TextStyle(color: SF.muted, fontSize: 14)),
                          menuMaxHeight: 280,
                          items: years
                              .map((y) => DropdownMenuItem(
                                    value: y,
                                    child: Text(y.toString()),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedYear = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _dropdownField(
                      icon: Icons.local_gas_station_outlined,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<double>(
                          value: _selectedTank,
                          isExpanded: true,
                          dropdownColor: SF.card,
                          style: TextStyle(color: SF.text, fontSize: 14),
                          hint: Text('Tank Capacity',
                              style: TextStyle(color: SF.muted, fontSize: 14)),
                          menuMaxHeight: 300,
                          items: _tankOptions
                              .map((t) => DropdownMenuItem<double>(
                                    value: t['liters'] as double,
                                    child: Text(t['label'] as String,
                                        style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedTank = v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _GradBtn(
                        text: _loading ? 'Saving…' : 'Save & Continue',
                        onTap: _loading ? null : _save),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItemData {
  final IconData outlineIcon;
  final IconData filledIcon;
  final String label;

  const _NavItemData(this.outlineIcon, this.filledIcon, this.label);
}

// ─────────────────────────────────────────────────────────────────────────────
// DASHBOARD SHELL
// ─────────────────────────────────────────────────────────────────────────────
class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key});
  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  int _idx =
      0; // (0=Home, 1=Sensors, 2=Quality, 3=History, 4=Reports, 5=Stations, 6=Settings)
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const List<_NavItemData> _navItems = [
    _NavItemData(Icons.home_outlined, Icons.home, 'Home'),
    _NavItemData(Icons.memory_outlined, Icons.memory, 'Sensors'),
    _NavItemData(Icons.science_outlined, Icons.science, 'Quality'),
    _NavItemData(Icons.speed_outlined, Icons.speed, 'Refueling History'),
    _NavItemData(Icons.bar_chart_outlined, Icons.bar_chart, 'Reports'),
    _NavItemData(
      Icons.local_gas_station_outlined,
      Icons.local_gas_station,
      'Stations',
    ),
    _NavItemData(Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;

    final pages = <Widget>[
      const HomeDashboardPage(),
      const SensorsPage(),
      const QualityPage(),
      const ConsumptionPage(),
      const ReportsPage(),
      const StationsPage(),
      const SettingsPage(),
    ];

    final drawerSidebar = _Sidebar(
      selected: _idx,
      items: _navItems,
      onSelect: (i) => setState(() => _idx = i),
      onLogout: () => FirebaseAuth.instance.signOut(),
      closeDrawer: () => _scaffoldKey.currentState?.closeDrawer(),
    );

    final wideSidebar = _Sidebar(
      selected: _idx,
      items: _navItems,
      onSelect: (i) => setState(() => _idx = i),
      onLogout: () => FirebaseAuth.instance.signOut(),
    );

    // AFTER
    return PopScope(
      canPop: false, // Never let back button exit the app
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_idx != 0) {
            // If not on Home, go to Home tab
            setState(() => _idx = 0);
          }
          // If already on Home, do nothing (don't exit)
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: SF.bg,
        drawer: wide
            ? null
            : Drawer(backgroundColor: SF.card, child: drawerSidebar),
        body: SafeArea(
          child: Row(
            children: [
              if (wide) SizedBox(width: 260, child: wideSidebar),
              Expanded(
                child: pages[_idx],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SIDEBAR
// ─────────────────────────────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  final int selected;
  final List<_NavItemData> items;
  final void Function(int) onSelect;
  final VoidCallback onLogout;
  final VoidCallback? closeDrawer;

  const _Sidebar({
    required this.selected,
    required this.items,
    required this.onSelect,
    required this.onLogout,
    this.closeDrawer,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Container(
      decoration: BoxDecoration(
        color: SF.card,
        border: Border(right: BorderSide(color: SF.glass(0.04))),
        boxShadow: [BoxShadow(color: SF.shadow(), blurRadius: 30)],
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Brand
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [SF.green, SF.greenDark]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_gas_station,
                      color: Colors.black, size: 16),
                ),
                const SizedBox(width: 10),
                Text('SmartFuel',
                    style: TextStyle(
                        color: SF.green,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
              ]),
            ),
            // Profile
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: _ProfileTile(email: user?.email ?? ''),
            ),
            Divider(color: SF.glass(0.05), height: 1),
            const SizedBox(height: 8),
            // Nav items
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                itemCount: items.length,
                itemBuilder: (listCtx, i) {
                  final item = items[i];
                  final active = selected == i;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        onSelect(i);
                        closeDrawer?.call();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: active
                              ? SF.green.withAlpha(28)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: active
                                ? SF.green.withAlpha(60)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(children: [
                          Icon(
                            active ? item.filledIcon : item.outlineIcon,
                            color: active ? SF.green : SF.muted,
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            item.label,
                            style: TextStyle(
                              color: active ? SF.green : SF.text,
                              fontWeight:
                                  active ? FontWeight.w700 : FontWeight.w400,
                              fontSize: 14,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              ),
            ),
            Divider(color: SF.glass(0.05), height: 1),
            // Logout + device status
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: onLogout,
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      child: Row(children: const [
                        Icon(Icons.logout, color: Colors.redAccent, size: 18),
                        SizedBox(width: 12),
                        Text('Logout',
                            style: TextStyle(
                                color: Colors.redAccent, fontSize: 14)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const _DeviceDot(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DEVICE DOT
// ─────────────────────────────────────────────────────────────────────────────
class _DeviceDot extends StatefulWidget {
  const _DeviceDot();
  @override
  State<_DeviceDot> createState() => _DeviceDotState();
}

class _DeviceDotState extends State<_DeviceDot> {
  bool _on = false;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _check();
    _t = Timer.periodic(const Duration(seconds: 3),
        (_) => _check()); // we are checking after every 3 to 5 secs
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _check() async {
    try {
      final res = await http
          .get(Uri.parse('$kBackendBase/telemetry/latest'))
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      setState(
          () => _on = res.statusCode == 200 && body['status'] != 'waiting');
    } catch (_) {
      if (mounted) setState(() => _on = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _on ? SF.green : SF.muted.withAlpha(120),
          boxShadow: _on
              ? [BoxShadow(color: SF.green.withAlpha(120), blurRadius: 6)]
              : [],
        ),
      ),
      const SizedBox(width: 8),
      Text(
        _on ? 'Device: Connected' : 'Device: Disconnected',
        style: TextStyle(color: _on ? SF.green : SF.muted, fontSize: 12),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE TILE
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileTile extends StatelessWidget {
  final String email;
  const _ProfileTile({required this.email});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .snapshots(),
      builder: (_, snap) {
        final name = snap.data?.data()?['fullName']?.toString() ?? 'User';
        final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
        return Row(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [SF.greenDark, SF.green],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(initial,
                  style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(email,
                    style: TextStyle(color: SF.muted, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE SHELL
// ─────────────────────────────────────────────────────────────────────────────
class _PageShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget>? actions;

  const _PageShell({
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 900;
    // No Scaffold here — the parent DashboardShell owns the only Scaffold
    // and its drawer. We just return a Column so the menu button can reach
    // the outer Scaffold via Scaffold.of(context).
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: SF.card.withAlpha(200),
            border: Border(bottom: BorderSide(color: SF.glass(0.06))),
          ),
          child: Row(children: [
            if (!wide)
              // Builder is still needed so Scaffold.of finds the
              // DashboardShell Scaffold that actually has the drawer.
              Builder(
                builder: (ctx) => IconButton(
                  icon: Icon(Icons.menu, color: SF.text),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w800)),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: TextStyle(color: SF.muted, fontSize: 12)),
                ],
              ),
            ),
            if (actions != null) ...actions!,
          ]),
        ),
        Expanded(child: child),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOME DASHBOARD  — polls /telemetry/latest every 2 s
// ─────────────────────────────────────────────────────────────────────────────
class HomeDashboardPage extends StatefulWidget {
  const HomeDashboardPage({super.key});
  @override
  State<HomeDashboardPage> createState() => _HomeState();
}

class _HomeState extends State<HomeDashboardPage> {
  double? fuel_liters;
  double? fuel_percent;
  double? water_in_fuel;
  double? quality_score;
  String? contaminants;
  String? recommendation;
  String updated_at = '--';
  bool _ready = false;

  String _uid = '';
  String _vehicleId = 'veh_1';
  Timer? _timer;
  DateTime? _lastWrittenAt; // throttle Firestore writes

  @override
  void initState() {
    super.initState();
    _loadPath();
    _fetch();
    _timer = Timer.periodic(
        const Duration(seconds: 2),
        (_) =>
            _fetch()); // to extend or shorten the time of data fetching from sensor
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadPath() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final vid = (doc.data() ?? {})['activeVehicleId']?.toString() ?? 'veh_1';
    if (mounted)
      setState(() {
        _uid = uid;
        _vehicleId = vid;
      });
  }

  Future<void> _fetch() async {
    try {
      final res = await http
          .get(Uri.parse('$kBackendBase/telemetry/latest'))
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      if (d['status'] == 'waiting') {
        setState(() => _ready = false);
        return;
      }
      setState(() {
        _ready = true;
        fuel_liters = (d['fuel_liters'] as num?)?.toDouble();
        fuel_percent = (d['fuel_percent'] as num?)?.toDouble();
        water_in_fuel = (d['water_in_fuel'] as num?)?.toDouble();
        quality_score = (d['quality_score'] as num?)?.toDouble();
        contaminants = d['contaminants']?.toString();
        recommendation = d['recommendation']?.toString();
        updated_at = d['updated_at']?.toString() ?? '--';
      });

      // Write to Firestore every 30 s so charts & reports stay live
      if (_uid.isNotEmpty && fuel_liters != null) {
        final now = DateTime.now();
        if (_lastWrittenAt == null ||
            now.difference(_lastWrittenAt!) >= const Duration(seconds: 30)) {
          _lastWrittenAt = now;
          FirebaseFirestore.instance
              .collection('users')
              .doc(_uid)
              .collection('vehicles')
              .doc(_vehicleId)
              .collection('telemetry')
              .doc('history')
              .collection('items')
              .add({
            'type': 'reading',
            'liters': fuel_liters,
            'fuel_percent': fuel_percent,
            'water_in_fuel': water_in_fuel,
            'quality_score': quality_score,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  String _alert() {
    if (!_ready) return 'Waiting for device…';
    if (water_in_fuel == null) return 'Unknown';
    if (water_in_fuel! >= 1.0) return '⚠ Water detected';
    // if (water_in_fuel! >= 0.5) return '⚠ Water detected (LOW)';
    return '✅ No alerts';
  }

  Color _alertColor() {
    if (!_ready) return SF.muted;
    if (water_in_fuel != null && water_in_fuel! >= 0.5) {
      return Colors.orangeAccent;
    }
    return SF.green;
  }

  @override
  Widget build(BuildContext context) {
    final histRef = _uid.isEmpty
        ? null
        : FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('vehicles')
            .doc(_vehicleId)
            .collection('telemetry')
            .doc('history')
            .collection('items');

    final liveBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: (_ready ? SF.green : SF.muted).withAlpha(28),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: (_ready ? SF.green : SF.muted).withAlpha(60)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _ready ? SF.green : SF.muted,
            boxShadow: _ready
                ? [BoxShadow(color: SF.green.withAlpha(120), blurRadius: 6)]
                : [],
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _ready ? 'Live' : 'Offline',
          style: TextStyle(
              color: _ready ? SF.green : SF.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600),
        ),
      ]),
    );

    return _PageShell(
      title: 'Dashboard',
      subtitle: _ready ? 'Live · $updated_at' : 'Waiting for ESP32…',
      actions: [liveBadge],
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── NEW: Overview card — readings left | both graphs right ────
            _GlassBox(
              child: LayoutBuilder(builder: (_, bc) {
                final isWide = bc.maxWidth >= 540;

                // ── LEFT: gauge + 3 stat rows ──────────────────────────────
                final leftSide = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Live Readings',
                        style: TextStyle(
                            color: SF.green,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                    const SizedBox(height: 12),
                    Center(child: _GaugeWidget(pct: fuel_percent ?? 0)),
                    const SizedBox(height: 14),
                    // Fuel Available
                    _OverviewRow(
                      icon: Icons.local_gas_station_rounded,
                      label: 'Fuel Available',
                      value: fuel_liters == null
                          ? '--'
                          : '${fuel_liters!.toStringAsFixed(2)} L',
                      sub: fuel_percent == null
                          ? '--'
                          : '${fuel_percent!.toStringAsFixed(1)}%',
                      color: SF.green,
                    ),
                    const SizedBox(height: 8),
                    // Water in Fuel
                    _OverviewRow(
                      icon: Icons.water_drop_rounded,
                      label: 'Water in Fuel',
                      value: water_in_fuel == null
                          ? '--'
                          : water_in_fuel! >= 1.0
                              ? 'Detected'
                              : 'Clean',
                      sub: water_in_fuel == null
                          ? ''
                          : 'Raw: ${water_in_fuel!.toStringAsFixed(1)}',
                      color: water_in_fuel != null && water_in_fuel! >= 0.5
                          ? Colors.orangeAccent
                          : SF.green,
                    ),
                    const SizedBox(height: 8),
                    // Quality Score
                    _OverviewRow(
                      icon: Icons.verified_rounded,
                      label: 'Quality Score',
                      value: quality_score == null
                          ? '--'
                          : '${quality_score!.toStringAsFixed(1)}/10',
                      sub: contaminants != null && contaminants!.isNotEmpty
                          ? contaminants!
                          : 'Contaminants Found',
                      color: quality_score != null && quality_score! >= 8
                          ? SF.green
                          : quality_score != null
                              ? Colors.orangeAccent
                              : SF.muted,
                    ),
                  ],
                );

                // ── RIGHT: Fuel Over Time + Consumption Trend stacked ──────
                final rightSide = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Fuel Over Time
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Fuel Over Time',
                            style: TextStyle(
                                color: SF.green,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        _ChipBtn(
                          label: 'Simulate',
                          onTap: () =>
                              _seedHistory(uid: _uid, vehicleId: _vehicleId),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 140,
                      child: histRef == null
                          ? Center(
                              child: Text('Loading…',
                                  style: TextStyle(color: SF.muted)))
                          : _FuelLineChart(
                              query: histRef
                                  .orderBy('createdAt', descending: true)
                                  .limit(20)),
                    ),
                    const SizedBox(height: 14),
                    Divider(color: SF.glass(0.08)),
                    const SizedBox(height: 10),
                    // Consumption Trend (bar chart)
                    Text('Refueling Pattern',
                        style: TextStyle(
                            color: SF.green,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    Text('Last 12 readings',
                        style: TextStyle(color: SF.muted, fontSize: 11)),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 140,
                      child: histRef == null
                          ? Center(
                              child: Text('Loading…',
                                  style: TextStyle(color: SF.muted)))
                          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: histRef
                                  .orderBy('createdAt', descending: true)
                                  .limit(12)
                                  .snapshots(),
                              builder: (_, snap) {
                                final history = snap.data?.docs
                                        .map((d) => d.data())
                                        .toList() ??
                                    [];
                                if (history.isEmpty) {
                                  return Center(
                                    child: Text('No data yet',
                                        style: TextStyle(color: SF.muted)),
                                  );
                                }
                                return _BarChartWidget(history: history);
                              },
                            ),
                    ),
                  ],
                );

                if (isWide) {
                  return IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 4, child: leftSide),
                        VerticalDivider(
                            color: SF.glass(0.08), width: 24, thickness: 1),
                        Expanded(flex: 6, child: rightSide),
                      ],
                    ),
                  );
                } else {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      leftSide,
                      Divider(color: SF.glass(0.08), height: 28),
                      rightSide,
                    ],
                  );
                }
              }),
            ),
            const SizedBox(height: 16),

            // Alerts
            _StatTile(
              icon: Icons.notifications_none_outlined,
              label: 'Alerts',
              value: _alert(),
              sub: 'Quality & Sensors',
              valueColor: _alertColor(),
              valueFontSize: 13,
            ),
            const SizedBox(height: 16),

/*             // Map
            _GlassBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text('Nearest Fuel Pumps',
                          style: TextStyle(
                              color: SF.green,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                    ),
                    Text('Rawalpindi',
                        style: TextStyle(color: SF.muted, fontSize: 12)),
                  ]),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 240,
                      child: GoogleMap(
                        onMapCreated: (_) {},
                        initialCameraPosition: const CameraPosition(
                          target: LatLng(33.6844, 73.0479),
                          zoom: 12,
                        ),
                        markers: {
                          const Marker(
                            markerId: MarkerId('home_pin'),
                            position: LatLng(33.6844, 73.0479),
                          ),
                        },
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        myLocationButtonEnabled: false,
                        style: _kDarkMapStyle,
                      ),
                    ),
                  ),
                ],
              ),
            ), */
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SENSORS PAGE  — polls /sensors/latest every 2 s
// ─────────────────────────────────────────────────────────────────────────────
class SensorsPage extends StatefulWidget {
  const SensorsPage({super.key});
  @override
  State<SensorsPage> createState() => _SensorsState();
}

class _SensorsState extends State<SensorsPage> {
  double? fuel_liters;
  double? fuel_percent;
  double? water_in_fuel;
  String updated_at = '--';
  bool _ready = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 2),
        (_) => _fetch()); // for change the fetching in senso
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final res = await http
          .get(Uri.parse('$kBackendBase/sensors/latest'))
          .timeout(const Duration(seconds: 3));
      if (!mounted) return;
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      if (d['status'] == 'waiting') {
        setState(() => _ready = false);
        return;
      }
      setState(() {
        _ready = true;
        fuel_liters = (d['fuel_liters'] as num?)?.toDouble();
        fuel_percent = (d['fuel_percent'] as num?)?.toDouble();
        water_in_fuel = (d['water_in_fuel'] as num?)?.toDouble();
        updated_at = d['updated_at']?.toString() ?? '--';
      });
    } catch (_) {
      if (mounted) setState(() => _ready = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Sensors',
      subtitle: 'Live readings from ESP32',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (_, bc) {
              final cols = bc.maxWidth >= 600 ? 3 : 1;
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _SensorStatusCard(
                    label: 'Fuel Level',
                    value: fuel_liters == null
                        ? '--'
                        : '${fuel_liters!.toStringAsFixed(2)} L',
                    sub: fuel_percent == null
                        ? '--'
                        : '${fuel_percent!.toStringAsFixed(1)}%',
                    status: _ready ? 'OK' : 'WAITING',
                    icon: Icons.local_gas_station_outlined,
                  ),
                  _SensorStatusCard(
                    label: 'Water Sensor',
                    value: water_in_fuel == null
                        ? '--'
                        : water_in_fuel! >= 1.0
                            ? 'DETECTED'
                            : 'CLEAN',
                    sub: water_in_fuel == null
                        ? ''
                        : 'Raw: ${water_in_fuel!.toStringAsFixed(0)}',
                    status: !_ready
                        ? 'WAITING'
                        : water_in_fuel! >= 1.0
                            ? 'WARN'
                            : 'OK',
                    icon: Icons.water_drop_outlined,
                  ),
                  _SensorStatusCard(
                    label: 'Last Sync',
                    value: updated_at,
                    sub: _ready ? 'Receiving data' : 'No data yet',
                    status: _ready ? 'OK' : 'WAITING',
                    icon: Icons.sync_outlined,
                  ),
                ],
              );
            }),
            const SizedBox(height: 16),
            _GlassBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Raw Sensor Values',
                      style: TextStyle(
                          color: SF.green,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                  const SizedBox(height: 14),
                  _KV(
                      'fuel_liters',
                      fuel_liters == null
                          ? '--'
                          : '${fuel_liters!.toStringAsFixed(3)} L'),
                  _KV(
                      'fuel_percent',
                      fuel_percent == null
                          ? '--'
                          : '${fuel_percent!.toStringAsFixed(2)} %'),
                  _KV(
                      'water_in_fuel',
                      water_in_fuel == null
                          ? '--'
                          : water_in_fuel!.toStringAsFixed(1)),
                  _KV('updated_at', updated_at),
                  _KV('endpoint', '/sensors/latest'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REPORTS PAGE
// ─────────────────────────────────────────────────────────────────────────────
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsState();
}

class _ReportsState extends State<ReportsPage> {
  String _uid = '';
  String _vehicleId = 'veh_1';
  List<Map<String, dynamic>> _history = [];
  Map<String, dynamic> _vehicleData = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final vid = (doc.data() ?? {})['activeVehicleId']?.toString() ?? 'veh_1';
    final vDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('vehicles')
        .doc(vid)
        .get();
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('vehicles')
        .doc(vid)
        .collection('telemetry')
        .doc('history')
        .collection('items')
        .orderBy('createdAt', descending: true)
        .limit(200)
        .get();
    if (mounted) {
      setState(() {
        _uid = uid;
        _vehicleId = vid;
        _vehicleData = vDoc.data() ?? {};
        _history = snap.docs.map((d) => d.data()).toList();
        _loading = false;
      });
    }
  }

  void _exportCSV() {
    final lines = <String>['datetime,type,liters'];
    for (final e in _history) {
      final ts = e['createdAt'];
      String t = '--';
      if (ts is Timestamp) t = ts.toDate().toIso8601String();
      lines.add('$t,${e['type'] ?? ''},${e['liters'] ?? ''}');
    }
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: const Text('CSV copied to clipboard ✅'),
          backgroundColor: Colors.green.shade700),
    );
  }

  Future<void> _exportPDF() async {
    // Re-fetch latest data so the PDF always reflects the most recent readings
    await _load();

    final doc = pw.Document();
    final total = _history.fold<double>(
        0, (s, e) => s + ((e['liters'] as num?)?.toDouble() ?? 0));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context ctx) => [
          pw.Text(
            'SmartFuel — Readings Report',
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Vehicle: ${_vehicleData['vehicleNumber'] ?? '--'}  ${_vehicleData['vehicleModel'] ?? '--'}',
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.Text(
            'Tank Capacity: ${_vehicleData['tankCapacityL'] ?? '--'} L',
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.Text(
            'Total Readings: ${_history.length}    Total Tracked: ${total.toStringAsFixed(2)} L',
            style: const pw.TextStyle(fontSize: 12),
          ),
          pw.SizedBox(height: 16),
          pw.Table.fromTextArray(
            headers: ['Date/Time', 'Type', 'Liters'],
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellHeight: 24,
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
            },
            data: _history.take(200).map((e) {
              final ts = e['createdAt'];
              String t = '--';
              if (ts is Timestamp) t = ts.toDate().toIso8601String();
              return [
                t,
                e['type']?.toString() ?? '--',
                '${(e['liters'] as num?)?.toStringAsFixed(2) ?? '--'} L',
              ];
            }).toList(),
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => doc.save(),
    );
  }

  String _fmtTs(dynamic ts) {
    if (ts is! Timestamp) return '--';
    final dt = ts.toDate();
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final total = _history.fold<double>(
        0, (s, e) => s + ((e['liters'] as num?)?.toDouble() ?? 0));

    return _PageShell(
      title: 'Reports',
      subtitle: 'Summary & export',
      actions: [
        _ChipBtn(label: 'Copy CSV', onTap: _exportCSV),
        const SizedBox(width: 8),
        _ChipBtn(label: 'Download PDF', onTap: _exportPDF),
        const SizedBox(width: 8),
      ],
      child: _loading
          ? Center(child: CircularProgressIndicator(color: SF.green))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _GlassBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vehicle Summary',
                            style: TextStyle(
                                color: SF.green,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                        const SizedBox(height: 12),
                        _KV(
                          'Vehicle',
                          '${_vehicleData['vehicleNumber'] ?? '--'}  ${_vehicleData['vehicleModel'] ?? '--'}',
                        ),
                        _KV('Tank Capacity',
                            '${_vehicleData['tankCapacityL'] ?? '--'} L'),
                        _KV('Total Readings', '${_history.length}'),
                        _KV('Total Tracked', '${total.toStringAsFixed(2)} L'),
                        if (_history.isNotEmpty) ...[
                          _KV('First Reading',
                              _fmtTs(_history.last['createdAt'])),
                          _KV('Latest Reading',
                              _fmtTs(_history.first['createdAt'])),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _GlassBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                            child: Text('Recent Readings',
                                style: TextStyle(
                                    color: SF.green,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ),
                          Text('${_history.length} total',
                              style: TextStyle(color: SF.muted, fontSize: 12)),
                        ]),
                        const SizedBox(height: 12),
                        Table(
                          columnWidths: const {
                            0: FlexColumnWidth(2),
                            1: FlexColumnWidth(1),
                            2: FlexColumnWidth(1),
                          },
                          children: [
                            TableRow(children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('Date/Time',
                                    style: TextStyle(
                                        color: SF.muted, fontSize: 12)),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('Type',
                                    style: TextStyle(
                                        color: SF.muted, fontSize: 12)),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text('Liters',
                                    style: TextStyle(
                                        color: SF.muted, fontSize: 12)),
                              ),
                            ]),
                            ..._history.take(50).map((e) => TableRow(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 5),
                                      child: Text(_fmtTs(e['createdAt']),
                                          style: TextStyle(
                                              color: SF.muted, fontSize: 12)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 5),
                                      child: Text(e['type']?.toString() ?? '--',
                                          style: const TextStyle(fontSize: 12)),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 5),
                                      child: Text(
                                        '${(e['liters'] as num?)?.toStringAsFixed(2) ?? '--'} L',
                                        style: TextStyle(
                                            color: SF.green,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                )),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STATIONS PAGE
// ─────────────────────────────────────────────────────────────────────────────

// Typed station records — avoids Object cast errors with LatLng
// StationsPage, _StationData, _demoStations and _StationTile
// are now defined in stations_page.dart (part of this library).

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS PAGE
// ─────────────────────────────────────────────────────────────────────────────

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  String _uid = '';
  String _activeVehicleId = 'veh_1';
  bool _loadingProfile = true;

  // Profile fields
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _savingProfile = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this)
      ..addListener(() => setState(() {}));
    appTheme.addListener(_rebuild);
    themeModeNotifier.addListener(_rebuild);
    _loadProfile();
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _tab.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    appTheme.removeListener(_rebuild);
    themeModeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!mounted) return;
    final d = doc.data() ?? {};
    setState(() {
      _uid = uid;
      _activeVehicleId = d['activeVehicleId']?.toString() ?? 'veh_1';
      _nameCtrl.text = d['fullName']?.toString() ?? '';
      _phoneCtrl.text = d['phone']?.toString() ?? '';
      _loadingProfile = false;
    });
  }

  Future<void> _saveProfile() async {
    if (_uid.isEmpty) return;
    setState(() => _savingProfile = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid).update({
        'fullName': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
      });
      _snack('Profile saved ✅', success: true);
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green.shade700 : Colors.redAccent,
    ));
  }

  // ── Tab labels ──────────────────────────────────────────────────────────────
  static const _tabs = ['Profile', 'Vehicles', 'Appearance'];

  @override
  Widget build(BuildContext context) {
    return _PageShell(
      title: 'Settings',
      subtitle: 'Profile · Vehicles · Appearance',
      child: Column(
        children: [
          // ── Tab bar ──────────────────────────────────────────────
          Container(
            color: SF.card.withAlpha(160),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TabBar(
              controller: _tab,
              labelColor: SF.green,
              unselectedLabelColor: SF.muted,
              indicatorColor: SF.green,
              indicatorWeight: 2.5,
              labelStyle:
                  GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 13),
              unselectedLabelStyle: GoogleFonts.dmSans(fontSize: 13),
              tabs: _tabs.map((t) => Tab(text: t)).toList(),
            ),
          ),

          // ── Tab content ──────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                // Tab 0 — Profile
                _ProfileTab(
                  uid: _uid,
                  nameCtrl: _nameCtrl,
                  phoneCtrl: _phoneCtrl,
                  loading: _loadingProfile,
                  saving: _savingProfile,
                  onSave: _saveProfile,
                ),

                // Tab 1 — Vehicles
                _VehiclesTab(
                  uid: _uid,
                  activeVehicleId: _activeVehicleId,
                  onActiveChanged: (vid) =>
                      setState(() => _activeVehicleId = vid),
                ),

                // Tab 2 — Appearance
                const _AppearanceTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 0 — PROFILE
// ─────────────────────────────────────────────────────────────────────────────
class _ProfileTab extends StatelessWidget {
  final String uid;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final bool loading;
  final bool saving;
  final VoidCallback onSave;

  const _ProfileTab({
    required this.uid,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.loading,
    required this.saving,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Center(child: CircularProgressIndicator(color: SF.green));
    }

    final email = FirebaseAuth.instance.currentUser?.email ?? '--';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar card
          _SBox(
            child: Row(
              children: [
                // Avatar circle
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [SF.greenDark, SF.green]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Text(
                      nameCtrl.text.isNotEmpty
                          ? nameCtrl.text[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nameCtrl.text.isEmpty ? 'Your Name' : nameCtrl.text,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(email,
                          style: TextStyle(color: SF.muted, fontSize: 12)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: SF.green.withAlpha(28),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: SF.green.withAlpha(70)),
                        ),
                        child: Text('SmartFuel User',
                            style: TextStyle(
                                color: SF.green,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Editable fields
          _SBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('Personal Information'),
                const SizedBox(height: 14),
                _SInput(
                    ctrl: nameCtrl,
                    hint: 'Full Name',
                    icon: Icons.person_outline),
                const SizedBox(height: 10),
                _SInput(
                    ctrl: phoneCtrl,
                    hint: 'Phone Number',
                    icon: Icons.phone_outlined,
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 10),
                // Email (read-only, copyable)
                _ReadonlyField(label: 'Email (read-only)', value: email),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Account info
          _SBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('Account'),
                const SizedBox(height: 12),
                _KVRow('Firebase UID', uid.isEmpty ? '--' : uid,
                    copyable: true),
                _KVRow('Signed in as', email),
                _KVRow('Auth provider', 'Email / Password'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _GBtn(
            text: saving ? 'Saving…' : 'Save Profile',
            icon: Icons.save_outlined,
            onTap: saving ? null : onSave,
          ),
          // AFTER the Save Profile button block, before the closing ],
          const SizedBox(height: 8),
          _SBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('Support'),
                const SizedBox(height: 10),
                Text(
                  'For additional queries or complaints, contact us at:',
                  style: TextStyle(color: SF.muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final uri = Uri(
                      scheme: 'mailto',
                      path: 'waleedawann14@gmail.com',
                      queryParameters: {
                        'subject': 'SmartFuel Support / Complaint',
                      },
                    );
                    try {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } catch (_) {
                      await launchUrl(uri);
                    }
                  },
                  child: Row(
                    children: [
                      Icon(Icons.email_outlined, color: SF.green, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'waleedawann14@gmail.com',
                        style: TextStyle(
                          color: SF.green,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.underline,
                          decorationColor: SF.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 1 — VEHICLES
// ─────────────────────────────────────────────────────────────────────────────
class _VehiclesTab extends StatefulWidget {
  final String uid;
  final String activeVehicleId;
  final void Function(String) onActiveChanged;

  const _VehiclesTab({
    required this.uid,
    required this.activeVehicleId,
    required this.onActiveChanged,
  });

  @override
  State<_VehiclesTab> createState() => _VehiclesTabState();
}

class _VehiclesTabState extends State<_VehiclesTab> {
  bool _showAddForm = false;

  // Add-vehicle form controllers
  final _vNoCtrl = TextEditingController();
  final _vModelCtrl = TextEditingController();
  final _vYearCtrl = TextEditingController();
  final _vTankCtrl = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _vNoCtrl.dispose();
    _vModelCtrl.dispose();
    _vYearCtrl.dispose();
    _vTankCtrl.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _vehiclesCol =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('vehicles');

  Future<void> _addVehicle() async {
    final no = _vNoCtrl.text.trim().toUpperCase();
    final model = _vModelCtrl.text.trim();
    final year = int.tryParse(_vYearCtrl.text.trim()) ?? 0;
    final tank = double.tryParse(_vTankCtrl.text.trim()) ?? 0;

    if (no.isEmpty || model.isEmpty) {
      _snack('Vehicle number and model are required');
      return;
    }

    setState(() => _adding = true);
    try {
      final docId = 'veh_${DateTime.now().millisecondsSinceEpoch}';
      await _vehiclesCol.doc(docId).set({
        'vehicleNumber': no,
        'vehicleModel': model,
        'modelYear': year,
        'tankCapacityL': tank,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _vNoCtrl.clear();
      _vModelCtrl.clear();
      _vYearCtrl.clear();
      _vTankCtrl.clear();
      if (mounted) {
        setState(() => _showAddForm = false);
        _snack('Vehicle added ✅', success: true);
      }
    } catch (e) {
      _snack(e.toString());
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _setActive(String vehicleId) async {
    if (widget.uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({'activeVehicleId': vehicleId});
      widget.onActiveChanged(vehicleId);
      _snack('Active vehicle updated ✅', success: true);
    } catch (e) {
      _snack(e.toString());
    }
  }

  Future<void> _deleteVehicle(String vehicleId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Remove Vehicle',
        message:
            'This will permanently delete this vehicle and cannot be undone.',
        confirmLabel: 'Remove',
        danger: true,
      ),
    );
    if (confirm != true) return;

    try {
      await _vehiclesCol.doc(vehicleId).delete();

      // If deleted vehicle was active, reset to veh_1 or first available
      if (widget.activeVehicleId == vehicleId) {
        final remaining = await _vehiclesCol.get();
        final firstId =
            remaining.docs.isNotEmpty ? remaining.docs.first.id : 'veh_1';
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.uid)
            .update({'activeVehicleId': firstId});
        widget.onActiveChanged(firstId);
      }
      _snack('Vehicle removed', success: true);
    } catch (e) {
      _snack(e.toString());
    }
  }

  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? Colors.green.shade700 : Colors.redAccent,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.uid.isEmpty) {
      return Center(child: CircularProgressIndicator(color: SF.green));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Active Vehicle Summary Card ────────────────────────
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(widget.uid)
                .collection('vehicles')
                .doc(widget.activeVehicleId)
                .snapshots(),
            builder: (_, snap) {
              final d = snap.data?.data();
              if (d == null) return const SizedBox.shrink();

              final vNo = d['vehicleNumber']?.toString() ?? '--';
              final vModel = d['vehicleModel']?.toString() ?? '--';
              final vYear = (d['modelYear'] as num?)?.toInt() ?? 0;
              final vTank = (d['tankCapacityL'] as num?)?.toDouble() ?? 0;
              final initial = vModel.isNotEmpty ? vModel[0].toUpperCase() : 'V';

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [SF.green.withAlpha(30), SF.green.withAlpha(10)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border:
                      Border.all(color: SF.green.withAlpha(100), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: SF.green.withAlpha(20), blurRadius: 16),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: SF.green.withAlpha(40),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: SF.green.withAlpha(100)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: SF.green,
                              boxShadow: [
                                BoxShadow(
                                    color: SF.green.withAlpha(150),
                                    blurRadius: 4)
                              ],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text('ACTIVE VEHICLE',
                              style: TextStyle(
                                  color: SF.green,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.8)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient:
                              LinearGradient(colors: [SF.greenDark, SF.green]),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: Text(initial,
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 22)),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(vNo,
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: SF.text)),
                              Text(vModel,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: SF.muted,
                                      fontWeight: FontWeight.w500)),
                            ]),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Row(children: [
                      _ActiveVehicleStat(
                          icon: Icons.calendar_today_outlined,
                          label: 'Year',
                          value: vYear == 0 ? '--' : vYear.toString()),
                      const SizedBox(width: 10),
                      _ActiveVehicleStat(
                          icon: Icons.local_gas_station_outlined,
                          label: 'Tank',
                          value: '${vTank.toStringAsFixed(0)} L'),
                      const SizedBox(width: 10),
                      _ActiveVehicleStat(
                          icon: Icons.fingerprint,
                          label: 'Doc ID',
                          value: widget.activeVehicleId.length > 8
                              ? '…${widget.activeVehicleId.substring(widget.activeVehicleId.length - 6)}'
                              : widget.activeVehicleId),
                    ]),
                  ],
                ),
              );
            },
          ),

          // ── Header row ─────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('My Vehicles',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: SF.text)),
                    Text('Manage your registered vehicles',
                        style: TextStyle(color: SF.muted, fontSize: 12)),
                  ],
                ),
              ),
              _ChipButton(
                label: _showAddForm ? 'Cancel' : '+ Add Vehicle',
                color: _showAddForm ? Colors.redAccent : SF.green,
                onTap: () => setState(() => _showAddForm = !_showAddForm),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Add form (animated) ────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: _showAddForm
                ? _SBox(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Label('Add New Vehicle'),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                            child: _SInput(
                              ctrl: _vNoCtrl,
                              hint: 'Vehicle Number (ABC-123)',
                              icon: Icons.directions_car_outlined,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SInput(
                              ctrl: _vModelCtrl,
                              hint: 'Model (e.g. Honda Civic)',
                              icon: Icons.car_repair,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(
                            child: _SInput(
                              ctrl: _vYearCtrl,
                              hint: 'Year (e.g. 2022)',
                              icon: Icons.calendar_today_outlined,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SInput(
                              ctrl: _vTankCtrl,
                              hint: 'Tank Capacity (L)',
                              icon: Icons.local_gas_station_outlined,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        Row(children: [
                          Expanded(
                            child: _GBtn(
                              text: _adding ? 'Adding…' : 'Add Vehicle',
                              icon: Icons.add_circle_outline,
                              onTap: _adding ? null : _addVehicle,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _OBtn(
                              text: 'Cancel',
                              onTap: () => setState(() => _showAddForm = false),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          if (_showAddForm) const SizedBox(height: 14),

          // ── Vehicle list ───────────────────────────────────────
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _vehiclesCol.snapshots(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                    child: CircularProgressIndicator(color: SF.green));
              }
              final docs = snap.data?.docs ?? [];
              // Sort: active vehicle first, then by createdAt if available
              final sorted = [...docs]..sort((a, b) {
                  final aActive = a.id == widget.activeVehicleId ? 0 : 1;
                  final bActive = b.id == widget.activeVehicleId ? 0 : 1;
                  if (aActive != bActive) return aActive.compareTo(bActive);
                  final aTs = a.data()['createdAt'];
                  final bTs = b.data()['createdAt'];
                  if (aTs is Timestamp && bTs is Timestamp) {
                    return aTs.compareTo(bTs);
                  }
                  return 0;
                });
              if (sorted.isEmpty) {
                return _SBox(
                  child: Column(
                    children: [
                      Icon(Icons.directions_car_outlined,
                          color: SF.muted, size: 40),
                      const SizedBox(height: 10),
                      Text('No vehicles yet',
                          style: TextStyle(
                              color: SF.muted, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('Tap "+ Add Vehicle" to register one.',
                          style: TextStyle(color: SF.muted, fontSize: 12)),
                    ],
                  ),
                );
              }

              return Column(
                children: sorted.map((doc) {
                  return _VehicleCard(
                    docId: doc.id,
                    data: doc.data(),
                    isActive: doc.id == widget.activeVehicleId,
                    onSetActive: () => _setActive(doc.id),
                    onDelete: () => _deleteVehicle(doc.id),
                    onEdited: () {},
                    vehiclesCol: _vehiclesCol,
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── Active vehicle stat chip ───────────────────────────────────────────────
class _ActiveVehicleStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _ActiveVehicleStat(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: SF.green.withAlpha(18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SF.green.withAlpha(50)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: SF.green, size: 13),
          const SizedBox(height: 3),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13, color: SF.text)),
          Text(label, style: TextStyle(color: SF.muted, fontSize: 10)),
        ]),
      ),
    );
  }
}

// ─── Vehicle card with inline edit ─────────────────────────────────────────
class _VehicleCard extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  final bool isActive;
  final VoidCallback onSetActive;
  final VoidCallback onDelete;
  final VoidCallback onEdited;
  final CollectionReference<Map<String, dynamic>> vehiclesCol;

  const _VehicleCard({
    required this.docId,
    required this.data,
    required this.isActive,
    required this.onSetActive,
    required this.onDelete,
    required this.onEdited,
    required this.vehiclesCol,
  });

  @override
  State<_VehicleCard> createState() => _VehicleCardState();
}

class _VehicleCardState extends State<_VehicleCard> {
  bool _editing = false;
  bool _saving = false;

  late final _noCtrl = TextEditingController(
      text: widget.data['vehicleNumber']?.toString() ?? '');
  late final _modelCtrl = TextEditingController(
      text: widget.data['vehicleModel']?.toString() ?? '');
  late final _yearCtrl = TextEditingController(
      text: (widget.data['modelYear'] as num?)?.toString() ?? '');
  late final _tankCtrl = TextEditingController(
      text: (widget.data['tankCapacityL'] as num?)?.toString() ?? '');

  @override
  void dispose() {
    _noCtrl.dispose();
    _modelCtrl.dispose();
    _yearCtrl.dispose();
    _tankCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveEdit() async {
    setState(() => _saving = true);
    try {
      await widget.vehiclesCol.doc(widget.docId).update({
        'vehicleNumber': _noCtrl.text.trim().toUpperCase(),
        'vehicleModel': _modelCtrl.text.trim(),
        'modelYear': int.tryParse(_yearCtrl.text.trim()) ?? 0,
        'tankCapacityL': double.tryParse(_tankCtrl.text.trim()) ?? 0,
      });
      if (mounted) {
        setState(() => _editing = false);
        widget.onEdited();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final no = widget.data['vehicleNumber']?.toString() ?? '--';
    final model = widget.data['vehicleModel']?.toString() ?? '--';
    final year = (widget.data['modelYear'] as num?)?.toInt() ?? 0;
    final tank = (widget.data['tankCapacityL'] as num?)?.toDouble() ?? 0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SF.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.isActive ? SF.green.withAlpha(120) : SF.glass(0.06),
          width: widget.isActive ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: widget.isActive ? SF.green.withAlpha(24) : SF.shadow(),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ──────────────────────────────────────
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: widget.isActive
                      ? LinearGradient(colors: [SF.greenDark, SF.green])
                      : null,
                  color: widget.isActive ? null : SF.glass(0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.directions_car_rounded,
                  color: widget.isActive ? Colors.black : SF.muted,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(no,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 15)),
                        if (widget.isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: SF.green.withAlpha(28),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: SF.green.withAlpha(80)),
                            ),
                            child: Text('ACTIVE',
                                style: TextStyle(
                                    color: SF.green,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5)),
                          ),
                        ],
                      ],
                    ),
                    Text('$model  ·  ${year == 0 ? '--' : year}',
                        style: TextStyle(color: SF.muted, fontSize: 12)),
                  ],
                ),
              ),
              // Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IconBtn(
                    icon: _editing ? Icons.close_rounded : Icons.edit_outlined,
                    color: SF.muted,
                    tooltip: _editing ? 'Cancel edit' : 'Edit',
                    onTap: () => setState(() => _editing = !_editing),
                  ),
                  if (!widget.isActive)
                    _IconBtn(
                      icon: Icons.delete_outline_rounded,
                      color: Colors.redAccent,
                      tooltip: 'Remove vehicle',
                      onTap: widget.onDelete,
                    ),
                ],
              ),
            ],
          ),

          // ── Quick stats (view mode) ───────────────────────────
          if (!_editing) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _MiniStat(
                  icon: Icons.local_gas_station_outlined,
                  label: 'Tank',
                  value: '${tank.toStringAsFixed(0)} L',
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.calendar_today_outlined,
                  label: 'Year',
                  value: year == 0 ? '--' : year.toString(),
                ),
                const SizedBox(width: 10),
                _MiniStat(
                  icon: Icons.fingerprint,
                  label: 'ID',
                  value: widget.docId.length > 8
                      ? '…${widget.docId.substring(widget.docId.length - 6)}'
                      : widget.docId,
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Set active button
            if (!widget.isActive)
              _GBtn(
                text: 'Set as Active Vehicle',
                icon: Icons.check_circle_outline,
                onTap: widget.onSetActive,
                height: 38,
              ),
          ],

          // ── Edit form (inline) ────────────────────────────────
          if (_editing) ...[
            const SizedBox(height: 14),
            Divider(color: SF.glass(0.06)),
            const SizedBox(height: 10),
            _Label('Edit Vehicle Details'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _SInput(
                    ctrl: _noCtrl,
                    hint: 'Vehicle Number',
                    icon: Icons.directions_car_outlined),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SInput(
                    ctrl: _modelCtrl,
                    hint: 'Vehicle Model',
                    icon: Icons.car_repair),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _SInput(
                  ctrl: _yearCtrl,
                  hint: 'Model Year',
                  icon: Icons.calendar_today_outlined,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SInput(
                  ctrl: _tankCtrl,
                  hint: 'Tank Capacity (L)',
                  icon: Icons.local_gas_station_outlined,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _GBtn(
                  text: _saving ? 'Saving…' : 'Save Changes',
                  icon: Icons.save_outlined,
                  onTap: _saving ? null : _saveEdit,
                  height: 38,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OBtn(
                  text: 'Cancel',
                  onTap: () => setState(() => _editing = false),
                  height: 38,
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB 2 — APPEARANCE
// ─────────────────────────────────────────────────────────────────────────────
class _AppearanceTab extends StatefulWidget {
  const _AppearanceTab();
  @override
  State<_AppearanceTab> createState() => _AppearanceTabState();
}

class _AppearanceTabState extends State<_AppearanceTab> {
  @override
  void initState() {
    super.initState();
    appTheme.addListener(_rebuild);
    themeModeNotifier.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    appTheme.removeListener(_rebuild);
    themeModeNotifier.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Dark / Light Mode ──────────────────────────────────
          _SBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('Theme Mode'),
                const SizedBox(height: 14),
                // Big toggle cards
                Row(children: [
                  Expanded(
                    child: _ThemeModeCard(
                      label: 'Dark',
                      icon: Icons.dark_mode_rounded,
                      selected: themeModeNotifier.isDark,
                      onTap: () => themeModeNotifier.set(ThemeMode.dark),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ThemeModeCard(
                      label: 'Light',
                      icon: Icons.light_mode_rounded,
                      selected: !themeModeNotifier.isDark,
                      onTap: () => themeModeNotifier.set(ThemeMode.light),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                // Toggle switch row
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: SF.glass(0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SF.glass(0.08)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        themeModeNotifier.isDark
                            ? Icons.nights_stay_rounded
                            : Icons.wb_sunny_rounded,
                        color: SF.green,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              themeModeNotifier.isDark
                                  ? 'Dark Mode'
                                  : 'Light Mode',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            Text(
                              themeModeNotifier.isDark
                                  ? 'Easy on the eyes in low light'
                                  : 'Great for bright environments',
                              style: TextStyle(color: SF.muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Switch.adaptive(
                        value: themeModeNotifier.isDark,
                        activeColor: SF.green,
                        onChanged: (_) => themeModeNotifier.toggle(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Accent Colour ──────────────────────────────────────
          _SBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('Accent Colour'),
                const SizedBox(height: 4),
                Text('Changes the highlight colour across the whole app.',
                    style: TextStyle(color: SF.muted, fontSize: 11)),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: AppTheme.accents.entries.map((e) {
                    final active = appTheme.accentName == e.key;
                    return GestureDetector(
                      onTap: () => appTheme.setAccent(e.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: e.value.withAlpha(active ? 50 : 18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: active ? e.value : e.value.withAlpha(60),
                            width: active ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: e.value,
                                shape: BoxShape.circle,
                                boxShadow: active
                                    ? [
                                        BoxShadow(
                                            color: e.value.withAlpha(120),
                                            blurRadius: 6)
                                      ]
                                    : [],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              e.key,
                              style: TextStyle(
                                color: e.value,
                                fontSize: 13,
                                fontWeight:
                                    active ? FontWeight.w700 : FontWeight.w500,
                              ),
                            ),
                            if (active) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check_rounded,
                                  color: e.value, size: 14),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Backend info ───────────────────────────────────────
          _SBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('Backend & Device'),
                const SizedBox(height: 12),
                _KVRow('Backend URL', kBackendBase, copyable: true),
                _KVRow('Telemetry endpoint', '/telemetry/latest'),
                _KVRow('Sensors endpoint', '/sensors/latest'),
                _KVRow('Quality endpoint', '/quality/latest'),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withAlpha(18),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.orangeAccent.withAlpha(60)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          color: Colors.orangeAccent, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Edit kBackendBase in main.dart to change the ESP32 URL.',
                          style: TextStyle(
                              color: Colors.orangeAccent.withAlpha(220),
                              fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── App info ───────────────────────────────────────────
          _SBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Label('App Info'),
                const SizedBox(height: 12),
                _KVRow('App name', 'SmartFuel'),
                _KVRow('Version', '1.0.0'),
                _KVRow('Platform', 'Flutter / Firebase'),
                _KVRow('Build', 'Release'),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Danger zone ────────────────────────────────────────
          _SBox(
            borderColor: Colors.redAccent.withAlpha(80),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.redAccent, size: 16),
                  const SizedBox(width: 8),
                  Text('Danger Zone',
                      style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ]),
                const SizedBox(height: 12),
                _OBtn(
                  text: 'Sign Out',
                  onTap: () => FirebaseAuth.instance.signOut(),
                  color: Colors.redAccent,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LOCAL WIDGETS (private to this file)
// ─────────────────────────────────────────────────────────────────────────────

// Glass section box
class _SBox extends StatelessWidget {
  final Widget child;
  final Color? borderColor;

  const _SBox({required this.child, this.borderColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SF.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? SF.glass(0.07)),
        boxShadow: [BoxShadow(color: SF.shadow(), blurRadius: 18)],
      ),
      child: child,
    );
  }
}

// Section label
class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 3,
        height: 14,
        decoration: BoxDecoration(
          color: SF.green,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(text,
          style: TextStyle(
              color: SF.green, fontWeight: FontWeight.w700, fontSize: 13)),
    ]);
  }
}

// Key-value row
class _KVRow extends StatelessWidget {
  final String k;
  final String v;
  final bool copyable;

  const _KVRow(this.k, this.v, {this.copyable = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text('$k:', style: TextStyle(color: SF.muted, fontSize: 12)),
          ),
          Expanded(
            child: Text(v,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ),
          if (copyable)
            GestureDetector(
              onTap: () => Clipboard.setData(ClipboardData(text: v)),
              child: Icon(Icons.copy_rounded, size: 14, color: SF.muted),
            ),
        ],
      ),
    );
  }
}

// Read-only text field (grey, not editable)
class _ReadonlyField extends StatelessWidget {
  final String label;
  final String value;

  const _ReadonlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: SF.glass(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SF.glass(0.08)),
      ),
      child: Row(children: [
        Icon(Icons.email_outlined, color: SF.muted, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: SF.muted, fontSize: 10)),
              Text(value, style: TextStyle(color: SF.muted, fontSize: 13)),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => Clipboard.setData(ClipboardData(text: value)),
          child: Icon(Icons.copy_rounded,
              size: 14, color: SF.muted.withAlpha(140)),
        ),
      ]),
    );
  }
}

// Gradient button
class _GBtn extends StatelessWidget {
  final String text;
  final IconData? icon;
  final VoidCallback? onTap;
  final double height;

  const _GBtn({
    required this.text,
    this.icon,
    required this.onTap,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [SF.green, SF.greenDark]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: SF.green.withAlpha(55),
                  blurRadius: 10,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.black, size: 16),
                const SizedBox(width: 6),
              ],
              Text(text,
                  style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w800,
                      fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }
}

// Outline button
class _OBtn extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final Color? color;
  final double height;

  const _OBtn({
    required this.text,
    required this.onTap,
    this.color,
    this.height = 46,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? SF.muted;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withAlpha(100)),
          color: c.withAlpha(15),
        ),
        child: Center(
          child: Text(text,
              style: TextStyle(
                  color: c, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
      ),
    );
  }
}

// Chip-style button (header actions)
class _ChipButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ChipButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(28),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Text(label,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// Icon button (edit/delete)
class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}

// Mini stat chip (used in vehicle card)
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: SF.glass(0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: SF.glass(0.07)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: SF.muted, size: 13),
            const SizedBox(height: 3),
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text(label, style: TextStyle(color: SF.muted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

// Theme mode selection card
class _ThemeModeCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeModeCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: selected ? SF.green.withAlpha(28) : SF.glass(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? SF.green : SF.glass(0.10),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? SF.green : SF.muted,
              size: 26,
            ),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: selected ? SF.green : SF.muted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    fontSize: 13)),
            if (selected) ...[
              const SizedBox(height: 4),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: SF.green,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: SF.green.withAlpha(150), blurRadius: 6)
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Text input (matches _SFInput style from main.dart)
class _SInput extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const _SInput({
    required this.ctrl,
    required this.hint,
    required this.icon,
    this.obscure = false,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: SF.muted, fontSize: 14),
        prefixIcon: Icon(icon, color: SF.muted, size: 18),
        filled: true,
        fillColor: SF.bg.withAlpha(180),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SF.glass(0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SF.glass(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SF.green, width: 1.5),
        ),
      ),
    );
  }
}

// Confirm dialog
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final bool danger;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? Colors.redAccent : SF.green;
    return AlertDialog(
      backgroundColor: SF.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(children: [
        Icon(
          danger ? Icons.warning_amber_rounded : Icons.check_circle_outline,
          color: color,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(title,
            style: TextStyle(
                color: color, fontWeight: FontWeight.w700, fontSize: 16)),
      ]),
      content: Text(message, style: TextStyle(color: SF.muted, fontSize: 13)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('Cancel', style: TextStyle(color: SF.muted)),
        ),
        GestureDetector(
          onTap: () => Navigator.pop(context, true),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: color.withAlpha(28),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withAlpha(80)),
            ),
            child: Text(confirmLabel,
                style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _GlassBox extends StatelessWidget {
  final Widget child;
  const _GlassBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SF.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SF.glass(0.06)),
        boxShadow: [BoxShadow(color: SF.shadow(), blurRadius: 20)],
      ),
      child: child,
    );
  }
}

class _GlassCard extends StatelessWidget {
  final double width;
  final Widget child;
  const _GlassCard({required this.width, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: SF.card.withAlpha(230),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: SF.glass(0.08)),
        boxShadow: [BoxShadow(color: SF.shadow(), blurRadius: 40)],
      ),
      child: child,
    );
  }
}

class _OverviewRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Color color;

  const _OverviewRow({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(50)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: SF.muted, fontSize: 10)),
                Text(value,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 14)),
              ],
            ),
          ),
          if (sub != null && sub!.isNotEmpty)
            Text(sub!,
                style: TextStyle(
                    color: SF.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;
  final double? valueFontSize;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.valueColor,
    this.valueFontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SF.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SF.glass(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: SF.green, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: TextStyle(color: SF.muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: valueFontSize ?? 18,
              fontWeight: FontWeight.w800,
              color: valueColor ?? SF.text,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (sub != null && sub!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(sub!,
                style: TextStyle(color: SF.muted, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

class _SensorStatusCard extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final String status;
  final IconData icon;

  const _SensorStatusCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.status,
    required this.icon,
  });

  Color _sc() {
    if (status == 'WARN') return Colors.orangeAccent;
    if (status == 'WAITING') return SF.muted;
    return SF.green;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SF.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _sc().withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: _sc(), size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: TextStyle(color: SF.muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _sc().withAlpha(28),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(status,
                  style: TextStyle(
                      color: _sc(), fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: _sc()),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          if (sub.isNotEmpty)
            Text(sub,
                style: TextStyle(color: SF.muted, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _KV extends StatelessWidget {
  final String k;
  final String v;
  const _KV(this.k, this.v);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text('$k:', style: TextStyle(color: SF.muted, fontSize: 13)),
          ),
          Expanded(
            child: Text(v,
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
            color: SF.green, fontWeight: FontWeight.w700, fontSize: 13));
  }
}

class _GradBtn extends StatelessWidget {
  final String text;
  final VoidCallback? onTap;
  const _GradBtn({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: onTap == null ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [SF.green, SF.greenDark]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: SF.green.withAlpha(60),
                  blurRadius: 12,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Center(
            child: Text(text,
                style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 15)),
          ),
        ),
      ),
    );
  }
}

class _OutlineBtn extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _OutlineBtn({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SF.glass(0.18)),
        ),
        child: Center(
          child: Text(text,
              style: TextStyle(
                  color: SF.text, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ),
    );
  }
}

class _ChipBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _ChipBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: SF.green.withAlpha(28),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SF.green.withAlpha(80)),
        ),
        child: Text(label,
            style: TextStyle(
                color: SF.green, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _SFInput extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final IconData icon;
  final bool obscure;

  const _SFInput({
    required this.ctrl,
    required this.hint,
    required this.icon,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: SF.muted, fontSize: 14),
        prefixIcon: Icon(icon, color: SF.muted, size: 18),
        filled: true,
        fillColor: SF.bg.withAlpha(180),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SF.glass(0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SF.glass(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: SF.green, width: 1.5),
        ),
      ),
    );
  }
}

class _LogoRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [SF.green, SF.greenDark]),
          borderRadius: BorderRadius.circular(10),
        ),
        child:
            const Icon(Icons.local_gas_station, color: Colors.black, size: 20),
      ),
      const SizedBox(width: 10),
      Text('SmartFuel',
          style: TextStyle(
              color: SF.green, fontSize: 18, fontWeight: FontWeight.w800)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CHART WIDGETS
// ─────────────────────────────────────────────────────────────────────────────
class _FuelLineChart extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  const _FuelLineChart({required this.query});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (_, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
              child: Text('No history yet', style: TextStyle(color: SF.muted)));
        }
        final pts = docs.reversed
            .toList()
            .asMap()
            .entries
            .map((e) => FlSpot(
                  e.key.toDouble(),
                  (e.value.data()['liters'] as num?)?.toDouble() ?? 0,
                ))
            .toList();

        return LineChart(LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: SF.glass(0.06), strokeWidth: 1),
          ),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: pts,
              isCurved: true,
              barWidth: 2.5,
              color: SF.green,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    SF.green.withAlpha(80),
                    SF.green.withAlpha(0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ));
      },
    );
  }
}

class _BarChartWidget extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _BarChartWidget({required this.history});

  @override
  Widget build(BuildContext context) {
    final items = history.reversed.take(12).toList();
    return BarChart(BarChartData(
      barGroups: items.asMap().entries.map((e) {
        return BarChartGroupData(
          x: e.key,
          barRods: [
            BarChartRodData(
              toY: (e.value['liters'] as num?)?.toDouble() ?? 0,
              color: SF.green,
              width: 14,
              borderRadius: BorderRadius.circular(4),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY: 15,
                color: SF.glass(0.04),
              ),
            ),
          ],
        );
      }).toList(),
      gridData: const FlGridData(show: false),
      titlesData: const FlTitlesData(show: false),
      borderData: FlBorderData(show: false),
      barTouchData: BarTouchData(enabled: false),
    ));
  }
}

class _GaugeWidget extends StatelessWidget {
  final double pct;
  const _GaugeWidget({required this.pct});

  @override
  Widget build(BuildContext context) {
    final p = pct.clamp(0.0, 100.0);
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(PieChartData(
            sectionsSpace: 0,
            centerSpaceRadius: 58,
            sections: [
              PieChartSectionData(
                  value: p, radius: 20, color: SF.green, title: ''),
              PieChartSectionData(
                  value: 100 - p, radius: 20, color: SF.glass(0.08), title: ''),
            ],
          )),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${p.toStringAsFixed(0)}%',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: SF.green)),
            Text('Fuel', style: TextStyle(color: SF.muted, fontSize: 12)),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BACKGROUND GRID
// ─────────────────────────────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2ECC71).withAlpha(10)
      ..strokeWidth = 0.5;
    const step = 40.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────
Route _fade(Widget page) => PageRouteBuilder(
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
      transitionDuration: const Duration(milliseconds: 250),
    );

Future<void> _seedHistory(
    {required String uid, required String vehicleId}) async {
  if (uid.isEmpty) return;
  final rand = Random();
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('vehicles')
      .doc(vehicleId)
      .collection('telemetry')
      .doc('history')
      .collection('items')
      .add({
    'type': 'reading',
    'liters': (15 + rand.nextInt(25)).toDouble(),
    'createdAt': FieldValue.serverTimestamp(),
  });
}
