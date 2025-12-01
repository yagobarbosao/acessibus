import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'pages/welcome_page.dart';
import 'pages/login_page.dart';
import 'pages/cadastro_page.dart';
import 'pages/linha_onibus_page.dart';
import 'pages/selecionar_linha_page.dart';
import 'pages/mapa_page.dart';
import 'pages/configuracoes_page.dart';
import 'pages/perfil_page.dart';
import 'pages/alerta_onibus_page.dart';
import 'pages/informacoes_onibus_page.dart';
import 'services/notificacao_service.dart';
import 'services/theme_service.dart';
import 'services/mqtt_service.dart';
import 'models/linha_onibus_model.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
// Imports para configuração do Google Maps no Android
// Usando import com prefixo para evitar conflitos
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart'
    as google_maps_flutter_platform_interface;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Carregar variáveis de ambiente
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    print('Aviso: Arquivo .env não encontrado. Usando valores padrão.');
  }

  // Inicializa Firebase com timeout
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        print('⚠️ Firebase: Timeout na inicialização (10s)');
        throw TimeoutException('Firebase initialization timeout');
      },
    );
    print('✅ Firebase inicializado com sucesso');
  } catch (e) {
    print('❌ Erro ao inicializar Firebase: $e');
    print(
      '⚠️ Continuando sem Firebase - algumas funcionalidades podem não funcionar',
    );
    // Continua mesmo se Firebase falhar
  }

  // Força orientação portrait
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Inicializa serviço de notificações com timeout
  try {
    await NotificacaoService().inicializar().timeout(
      const Duration(seconds: 5),
    );
    print('✅ Serviço de notificações inicializado');
  } catch (e) {
    print('⚠️ Erro ao inicializar notificações: $e');
    // Continua mesmo se falhar
  }

  // Configura Google Maps para melhor performance em emuladores Android
  // Isso só é necessário no Android, iOS não precisa
  // Nota: Esta configuração ajuda a resolver problemas de renderização no emulador
  if (Platform.isAndroid) {
    try {
      final mapsPlatform = google_maps_flutter_platform_interface
          .GoogleMapsFlutterPlatform
          .instance;
      // Verifica se é a implementação Android e configura Texture Layer
      // Isso melhora a performance e resolve problemas de renderização em emuladores
      final platformType = mapsPlatform.runtimeType.toString();
      if (platformType.contains('Android')) {
        // Acessa a propriedade useAndroidViewSurface via reflection/dynamic
        // Isso força o uso de Texture Layer que funciona melhor em emuladores
        try {
          // ignore: avoid_dynamic_calls
          (mapsPlatform as dynamic).useAndroidViewSurface = true;
          print('✅ Google Maps configurado para Android (Texture Layer)');
        } catch (_) {
          // Se não conseguir acessar, não é crítico - o mapa ainda funciona
          print(
            'ℹ️ Google Maps: Texture Layer não disponível (normal em alguns casos)',
          );
        }
      }
    } catch (e) {
      print('⚠️ Não foi possível configurar Google Maps para Android: $e');
      // Continua mesmo se falhar - não é crítico para o funcionamento do app
    }
  }

  // Inicializa MQTT para receber avisos de chegada do ônibus
  // Conecta sem especificar linha para receber todos os avisos
  // Usa timeout para não travar a inicialização
  try {
    final mqttService = MqttService();
    print('=== Inicializando MQTT ===');
    final iniciado = await mqttService.iniciarMonitoramento().timeout(
      const Duration(seconds: 15),
    );
    if (iniciado) {
      print('✅ MQTT inicializado com sucesso!');
      // Verifica status após inicialização
      mqttService.verificarStatus();
    } else {
      print('❌ Falha ao inicializar MQTT');
      mqttService.verificarStatus();
    }
  } catch (e, stackTrace) {
    if (e is TimeoutException) {
      print('⚠️ MQTT: Timeout na inicialização (15s) - continuando sem MQTT');
    } else {
      print('❌ Erro ao inicializar MQTT: $e');
      print('Stack trace: $stackTrace');
    }
    // Continua mesmo se o MQTT falhar
  }

  runApp(const AcessibusApp());
}

class AcessibusApp extends StatefulWidget {
  const AcessibusApp({super.key});

  @override
  State<AcessibusApp> createState() => _AcessibusAppState();
}

class _AcessibusAppState extends State<AcessibusApp> {
  final ThemeService _themeService = ThemeService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _carregarTema();
  }

  Future<void> _carregarTema() async {
    await _themeService.carregarConfiguracoes();
    _themeService.addListener(_onThemeChanged);
    setState(() {
      _isLoading = false;
    });
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const MaterialApp(
        title: 'Acessibus',
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    // Garante que o ThemeService está inicializado
    final darkTheme = _themeService.darkTheme;
    final altoContraste = _themeService.altoContraste;

    // Cores para alto contraste (WCAG AAA)
    final altoContrasteBackground = altoContraste ? Colors.black : null;
    final altoContrasteSurface = altoContraste ? Colors.grey[900] : null;
    final altoContrastePrimary = altoContraste ? Colors.yellow : Colors.green;
    final altoContrasteOnPrimary = altoContraste ? Colors.black : Colors.white;
    final altoContrasteText = altoContraste ? Colors.white : null;
    final altoContrasteBorder = altoContraste ? Colors.yellow : Colors.green;

    // Garante que todas as rotas estão definidas antes de construir o MaterialApp
    final routes = <String, WidgetBuilder>{
      '/welcome': (context) => const WelcomePage(),
      '/login': (context) => const LoginPage(),
      '/cadastro': (context) => const CadastroPage(),
      '/linhaOnibus': (context) => const LinhaOnibusPage(),
      '/selecionarLinha': (context) => const SelecionarLinhaPage(),
      '/mapa': (context) => const MapaPage(),
      '/configuracoes': (context) => const ConfiguracoesPage(),
      '/perfil': (context) => const PerfilPage(),
      '/alerta': (context) {
        final route = ModalRoute.of(context);
        if (route == null) {
          return const WelcomePage();
        }
        final args = route.settings.arguments as Map<String, dynamic>?;
        return AlertaOnibusPage(
          linha: args?['linha'] ?? '',
          distancia: args?['distancia'],
        );
      },
      '/informacoesOnibus': (context) {
        final route = ModalRoute.of(context);
        if (route == null) {
          return const WelcomePage();
        }
        final args = route.settings.arguments as Map<String, dynamic>?;
        if (args == null || args['linha'] == null) {
          return const WelcomePage();
        }
        final linha = args['linha'];
        if (linha is! LinhaOnibus) {
          return const WelcomePage();
        }
        return InformacoesOnibusPage(linha: linha);
      },
    };

    // Tema claro
    final lightTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: altoContraste ? altoContrastePrimary : Colors.green,
        brightness: Brightness.light,
        primary: altoContraste ? altoContrastePrimary : Colors.green,
        onPrimary: altoContraste ? altoContrasteOnPrimary : Colors.white,
        surface: altoContraste
            ? (altoContrasteSurface ?? Colors.grey[900]!)
            : Colors.white,
        onSurface: altoContraste ? altoContrasteText : Colors.black87,
      ),
      scaffoldBackgroundColor: altoContraste
          ? (altoContrasteBackground ?? Colors.black)
          : const Color(0xFFF5F5DC),
      useMaterial3: false,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: altoContraste ? Colors.grey[900] : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: altoContraste ? altoContrasteBorder : Colors.green,
            width: altoContraste ? 2 : 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: altoContraste ? altoContrasteBorder : Colors.green,
            width: altoContraste ? 2 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: altoContraste ? altoContrasteBorder : Colors.green,
            width: altoContraste ? 3 : 2,
          ),
        ),
        labelStyle: TextStyle(
          color: altoContraste ? altoContrasteText : Colors.black87,
        ),
        hintStyle: TextStyle(
          color: altoContraste ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: altoContraste ? altoContrastePrimary : Colors.green,
          foregroundColor: altoContraste
              ? altoContrasteOnPrimary
              : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: altoContraste
                ? BorderSide(color: altoContrasteBorder, width: 2)
                : BorderSide.none,
          ),
          textStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: altoContraste ? altoContrasteOnPrimary : Colors.white,
          ),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(
          color: altoContraste ? altoContrasteText : Colors.black87,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: altoContraste ? altoContrasteText : Colors.black87,
          fontSize: 14,
        ),
        titleLarge: TextStyle(
          color: altoContraste ? altoContrasteText : Colors.black87,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    // Tema escuro - cores modernas e equilibradas
    final darkBackground = altoContraste
        ? (altoContrasteBackground ?? Colors.black)
        : const Color(0xFF121212); // Material Design dark background

    final darkSurface = altoContraste
        ? (altoContrasteSurface ?? Colors.grey[900]!)
        : const Color(0xFF1E1E1E); // Surface um pouco mais claro

    final darkPrimary = altoContraste
        ? altoContrastePrimary
        : const Color(0xFF66BB6A); // Verde mais claro e suave para dark theme

    final darkOnPrimary = altoContraste
        ? altoContrasteOnPrimary
        : Colors.white; // Texto branco no botão verde

    final darkText = altoContraste
        ? (altoContrasteText ?? Colors.white)
        : Colors.white.withOpacity(0.87); // Texto principal com opacidade

    final darkTextSecondary = altoContraste
        ? (Colors.grey[300] ?? Colors.grey)
        : Colors.white.withOpacity(0.60); // Texto secundário

    final darkThemeData = ThemeData(
      colorScheme: ColorScheme.dark(
        brightness: Brightness.dark,
        primary: darkPrimary,
        onPrimary: darkOnPrimary,
        secondary: altoContraste
            ? altoContrastePrimary
            : const Color(0xFF81C784),
        onSecondary: altoContraste ? altoContrasteOnPrimary : Colors.black,
        surface: darkSurface,
        onSurface: darkText,
        background: darkBackground,
        onBackground: darkText,
        error: altoContraste
            ? (Colors.red[700] ?? Colors.red)
            : (Colors.red[400] ?? Colors.red),
        onError: Colors.white,
        surfaceVariant: altoContraste
            ? (Colors.grey[800] ?? Colors.grey)
            : const Color(0xFF2C2C2C),
        onSurfaceVariant: darkTextSecondary,
      ),
      scaffoldBackgroundColor: darkBackground,
      useMaterial3: false,
      cardColor: darkSurface,
      dividerColor: altoContraste
          ? altoContrasteBorder
          : Colors.white.withOpacity(0.12),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: altoContraste ? Colors.grey[900] : darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: altoContraste
                ? altoContrasteBorder
                : Colors.white.withOpacity(0.23),
            width: altoContraste ? 2 : 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: altoContraste
                ? altoContrasteBorder
                : Colors.white.withOpacity(0.23),
            width: altoContraste ? 2 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: altoContraste ? altoContrasteBorder : darkPrimary,
            width: altoContraste ? 3 : 2,
          ),
        ),
        labelStyle: TextStyle(color: darkText),
        hintStyle: TextStyle(color: darkTextSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimary,
          foregroundColor: darkOnPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: altoContraste
                ? BorderSide(color: altoContrasteBorder, width: 2)
                : BorderSide.none,
          ),
          elevation: 2,
          textStyle: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: darkOnPrimary,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: darkPrimary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: darkPrimary,
          side: BorderSide(
            color: altoContraste ? altoContrasteBorder : darkPrimary,
            width: altoContraste ? 2 : 1,
          ),
        ),
      ),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: darkText, fontSize: 16),
        bodyMedium: TextStyle(color: darkText, fontSize: 14),
        bodySmall: TextStyle(color: darkTextSecondary, fontSize: 12),
        titleLarge: TextStyle(
          color: darkText,
          fontWeight: FontWeight.bold,
          fontSize: 22,
        ),
        titleMedium: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
        titleSmall: TextStyle(
          color: darkText,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
        headlineLarge: TextStyle(
          color: darkText,
          fontWeight: FontWeight.bold,
          fontSize: 28,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkText,
        elevation: 0,
        iconTheme: IconThemeData(color: darkText),
      ),
      cardTheme: CardThemeData(
        color: darkSurface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: ListTileThemeData(
        textColor: darkText,
        iconColor: darkText,
      ),
      iconTheme: IconThemeData(color: darkText),
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.12),
        thickness: 1,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Acessibus',
      home: const WelcomePage(),
      theme: lightTheme,
      darkTheme: darkThemeData,
      themeMode: darkTheme ? ThemeMode.dark : ThemeMode.light,
      routes: routes,
    );
  }
}

