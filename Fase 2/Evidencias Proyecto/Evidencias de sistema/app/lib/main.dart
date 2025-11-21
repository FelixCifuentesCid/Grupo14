import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'core/api.dart';
import 'core/auth_state.dart';
import 'core/chat_api.dart';

// Screens
import 'screens/login_screen.dart';
import 'screens/catalog_screen.dart';
import 'screens/appointments_screen.dart';
import 'screens/create_design_screen.dart';
import 'screens/artist_profile_screen.dart';
import 'screens/threads_screen.dart';
import 'screens/favorites_screen.dart';

// Firebase + FCM + PNS
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/pns.dart';

// Deep links para volver desde el pago
import 'core/deeplinks.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Handler de mensajes en segundo plano (debe declararse top-level)
  FirebaseMessaging.onBackgroundMessage(Pns.onBackgroundMessage);

  // Bootstrap de tu app (JWT, sesión, etc.)
  await Api.init();

  // Inicializa notificaciones (canales + listeners + FCM init)
  await Pns.init();

  runApp(const ARTattooApp());

  // 🔗 Importante: inicializar deep links DESPUÉS de montar la app,
  // para que navigatorKey ya esté conectado y podamos navegar.
  Future.microtask(() => DeepLinks.init(Pns.navigatorKey));
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
          backgroundColor: const MaterialStatePropertyAll(kYellow),
          foregroundColor: const MaterialStatePropertyAll(kBlack),
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
          backgroundColor: const MaterialStatePropertyAll(kYellow),
          foregroundColor: const MaterialStatePropertyAll(kBlack),
          shape: MaterialStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const MaterialStatePropertyAll(kYellow),
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
      themeMode: ThemeMode.dark,
      theme: _darkTheme,
      darkTheme: _darkTheme,

      // clave para que PNS y deep links naveguen
      navigatorKey: Pns.navigatorKey,

      // Si está logueado → catálogo; si no → login
      home: ValueListenableBuilder<AuthState>(
        valueListenable: authState,
        builder: (_, state, __) =>
            state.isLoggedIn ? const CatalogScreen() : const LoginScreen(),
      ),

      // Rutas declaradas
      routes: {
        CatalogScreen.route: (_) => const CatalogScreen(),
        AppointmentsScreen.route: (_) => const AppointmentsScreen(),
        '/create-design': (_) => const CreateDesignScreen(),
        FavoritesScreen.route: (_) => const FavoritesScreen(),
        ThreadsScreen.route: (_) {
          final t = authState.token;
          if (t == null || t.isEmpty) return const LoginScreen();
          return ThreadsScreen(api: ChatApi(t));
        },
        // Por defecto podemos navegar al perfil del artista con artistId=0
        ArtistProfileScreen.route: (_) => const ArtistProfileScreen(artistId: 0),
      },

      // Rutas con argumentos
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
