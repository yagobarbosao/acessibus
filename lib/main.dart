import 'package:flutter/material.dart';
import 'welcome.dart';
import 'login.dart';
import 'cadastro.dart';
import 'linha_onibus.dart';
import 'selecionar_linha.dart';

void main() {
  runApp(const MeuApp());
}

class MeuApp extends StatelessWidget {
  const MeuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'App Acessibus',
      initialRoute: '/welcome', // <- agora começa na tela de boas-vindas
      routes: {
        '/welcome': (context) => const WelcomePage(),
        '/login': (context) => const LoginPage(),
        '/cadastro': (context) => const CadastroPage(),
        '/linhaOnibus': (context) => const LinhaOnibusPage(),
        '/selecionarLinha': (context) => const SelecionarLinhaPage(),
      },
    );
  }
}
