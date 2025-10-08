import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'core/api.dart';
import 'core/auth_state.dart';
import 'core/chat_api.dart';
import 'screens/login_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/appointments_screen.dart';
import 'screens/create_design_screen.dart';
import 'screens/artist_profile_screen.dart';
import 'screens/threads_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.init();
  runApp(const ARTattooApp());
}

class ARTattooApp extends StatelessWidget {
  const ARTattooApp({super.key});

  // Paleta ArtTattoo
  static const Color kYellow = Color(0xFFFFCC00);
  static const Color kYellowDark = Color(0xFFE6B800);
  static const Color kBlack = Color(0xFF000000);
  static const Color kSurfaceDark = Color(0xFF121212);

  // Esquema de color oscuro
  static const ColorScheme _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: kYellow,
    onPrimary: kBlack,
    secondary: kYellowDark,
    onSecondary: kBlack,
    error: Color(0xFFFF4D4F),
    onError: Colors.white,
    background: kBlack,
    onBackground: Colors.white,
    surface: kSurfaceDark,
    onSurface: Colors.white,
  );

  static ThemeData get _darkTheme {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme);

    return base.copyWith(
      colorScheme: _darkScheme,
      scaffoldBackgroundColor: kBlack,
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: kBlack,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStatePropertyAll(_darkScheme.primary),
          foregroundColor: MaterialStatePropertyAll(_darkScheme.onPrimary),
          shape: MaterialStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          padding: const MaterialStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: MaterialStatePropertyAll(_darkScheme.primary),
          foregroundColor: MaterialStatePropertyAll(_darkScheme.onPrimary),
          shape: MaterialStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStatePropertyAll(_darkScheme.primary),
          overlayColor: MaterialStatePropertyAll(kYellow.withOpacity(0.08)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: kSurfaceDark,
        hintStyle: const TextStyle(color: Colors.white70),
        labelStyle: const TextStyle(color: Colors.white),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: kYellow, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: kBlack,
        selectedItemColor: kYellow,
        unselectedItemColor: Colors.white60,
        showUnselectedLabels: false,
        type: BottomNavigationBarType.fixed,
      ),
      cardTheme: CardThemeData(
        color: kSurfaceDark,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(12),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: kSurfaceDark,
        selectedColor: kYellow.withOpacity(0.15),
        side: const BorderSide(color: Colors.white24),
        labelStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      dividerColor: Colors.white12,
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: kYellow,
        foregroundColor: kBlack,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: kSurfaceDark,
        contentTextStyle: TextStyle(color: Colors.white),
        actionTextColor: kYellow,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ARTattoo',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark, // Forzar oscuro; cambia a system si quieres
      theme: _darkTheme,
      darkTheme: _darkTheme,
      home: ValueListenableBuilder<AuthState>(
        valueListenable: authState,
        builder: (_, state, __) =>
            state.isLoggedIn ? const CatalogScreen() : const LoginScreen(),
      ),
      routes: {
        CatalogScreen.route: (_) => const CatalogScreen(),
        AppointmentsScreen.route: (_) => const AppointmentsScreen(),
        '/create-design': (_) => const CreateDesignScreen(),
        // Ruta nombrada para ver hilos de chat
        ThreadsScreen.route: (_) {
          final t = authState.token;
          if (t == null || t.isEmpty) {
            // Si no hay sesión, redirige a login
            return const LoginScreen();
          }
          return ThreadsScreen(api: ChatApi(t));
        },
        // Ruta rápida al perfil del artista (sin args -> placeholder)
        ArtistProfileScreen.route: (_) => const ArtistProfileScreen(artistId: 0),
      },
      // onGenerateRoute para pasar argumentos dinámicos (artistId/artistName)
      onGenerateRoute: (settings) {
        if (settings.name == ArtistProfileScreen.route &&
            settings.arguments is Map) {
          final args = settings.arguments as Map;
          final int artistId = args['artistId'] as int;
          final String? artistName = args['artistName'] as String?;
          return MaterialPageRoute(
            builder: (_) => ArtistProfileScreen(
              artistId: artistId,
              artistName: artistName,
            ),
            settings: settings,
          );
        }
        // Ruta para Threads con posibilidad de inyectar token (poco común, pero útil en tests)
        if (settings.name == ThreadsScreen.route &&
            settings.arguments is String) {
          final token = settings.arguments as String;
          return MaterialPageRoute(
            builder: (_) => ThreadsScreen(api: ChatApi(token)),
            settings: settings,
          );
        }
        return null;
      },
    );
  }
}
