import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'notificacao_service.dart';

/// Serviço para comunicação com ESP8266 via Firebase Realtime Database
/// 
/// Compatível com o código Arduino que envia dados para:
/// /dados/{idOnibus}/distancia
/// /dados/{idOnibus}/alerta
/// /dados/{idOnibus}/onibus
class FirebaseRealtimeService {
  static final FirebaseRealtimeService _instance = FirebaseRealtimeService._internal();
  factory FirebaseRealtimeService() => _instance;
  FirebaseRealtimeService._internal();

  final NotificacaoService _notificacaoService = NotificacaoService();
  StreamSubscription<DatabaseEvent>? _realtimeSubscription;
  bool _monitorando = false;
  String? _linhaMonitorada;
  String? _linhaSelecionada;

  // Configurações Firebase
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  /// Inicia monitoramento de uma linha de ônibus no Realtime Database
  /// 
  /// [idOnibus] - ID do ônibus no formato "onibus_132A" ou "onibus_251B"
  /// Este formato corresponde ao código Arduino
  Future<bool> iniciarMonitoramentoRealtime({required String idOnibus}) async {
    if (_monitorando) {
      // Se já está monitorando outra linha, para primeiro
      await pararMonitoramento();
    }

    _linhaMonitorada = idOnibus;

    try {
      // Escuta mudanças no caminho /dados/{idOnibus}
      final path = 'dados/$idOnibus';
      _realtimeSubscription = _database.child(path).onValue.listen(
        (DatabaseEvent event) {
          if (event.snapshot.value == null) return;

          final data = event.snapshot.value as Map<dynamic, dynamic>?;
          if (data == null) return;

          // Extrai dados
          final distancia = data['distancia'];
          final alerta = data['alerta']?.toString() ?? '';
          final onibus = data['onibus']?.toString() ?? '';
          final latitude = data['latitude'];
          final longitude = data['longitude'];
          final fonte = data['fonte']?.toString() ?? '';
          final timestamp = data['timestamp'];

          // Converte distância para double (pode vir como num ou string)
          double? distanciaNum;
          if (distancia != null) {
            try {
              if (distancia is num) {
                distanciaNum = distancia.toDouble();
              } else {
                distanciaNum = double.parse(distancia.toString());
              }
            } catch (e) {
              print('Erro ao converter distância: $e');
            }
          }

          // Converte latitude e longitude para double
          double? latNum;
          double? lonNum;
          if (latitude != null) {
            try {
              if (latitude is num) {
                latNum = latitude.toDouble();
              } else {
                latNum = double.parse(latitude.toString());
              }
            } catch (e) {
              print('Erro ao converter latitude: $e');
            }
          }
          if (longitude != null) {
            try {
              if (longitude is num) {
                lonNum = longitude.toDouble();
              } else {
                lonNum = double.parse(longitude.toString());
              }
            } catch (e) {
              print('Erro ao converter longitude: $e');
            }
          }

          print('Firebase Realtime: Dados recebidos - Distância: $distanciaNum, Alerta: $alerta, Ônibus: $onibus');
          if (latNum != null && lonNum != null) {
            print('Firebase Realtime: Coordenadas - Lat: $latNum, Lon: $lonNum');
          }
          if (fonte.isNotEmpty) {
            print('Firebase Realtime: Fonte dos dados: $fonte');
          }
          if (timestamp != null) {
            print('Firebase Realtime: Timestamp: $timestamp');
          }

          // MODO TESTE: Para testar notificações, sempre notifica quando recebe dados
          // Altere para false em produção
          const bool modoTeste = true;
          
          // Verifica se o alerta indica proximidade ou se a distância está dentro do limite
          // Considera distâncias até 5 metros como "próximo" (ajustável)
          final distanciaLimite = 5.0; // metros
          final alertaIndicaProximo = alerta.toLowerCase().contains('proximo') || 
                                      alerta.toLowerCase().contains('chegando') ||
                                      alerta.toLowerCase().contains('próximo');
          
          // Em modo teste, sempre notifica quando recebe dados válidos
          // Em produção, usa a lógica normal de distância
          final onibusProximo = modoTeste 
              ? (onibus.isNotEmpty) // Modo teste: sempre notifica se tem dados do ônibus
              : ((distanciaNum != null && distanciaNum <= distanciaLimite) || alertaIndicaProximo);

          if (onibusProximo && onibus.isNotEmpty) {
            // Extrai número da linha do ID (ex: "onibus_132A" -> "132A")
            String linha = onibus;
            if (onibus.startsWith('onibus_')) {
              linha = onibus.substring(7); // Remove "onibus_"
            }

            _linhaSelecionada = linha;

            // Prepara mensagem de distância
            String? distanciaTexto;
            if (distanciaNum != null) {
              distanciaTexto = '${distanciaNum.toStringAsFixed(2)}m';
            }

            print('Firebase Realtime: ✅ Ônibus $linha está próximo! Notificando usuário...');
            
            // Notifica o usuário
            _notificacaoService.notificarOnibusChegando(
              linha,
              distancia: distanciaTexto,
            );
          } else {
            // Log quando ônibus não está próximo
            if (distanciaNum != null) {
              print('Firebase Realtime: ⏳ Ônibus ainda está longe (${distanciaNum.toStringAsFixed(2)}m > ${distanciaLimite}m)');
            }
            
            // Reset quando ônibus não está mais próximo
            if (_linhaSelecionada != null) {
              _linhaSelecionada = null;
            }
          }
        },
        onError: (error) {
          print('Erro ao escutar Realtime Database: $error');
        },
      );

      _monitorando = true;
      return true;
    } catch (e) {
      print('Erro ao iniciar monitoramento Realtime Database: $e');
      return false;
    }
  }

  /// Para o monitoramento
  Future<void> pararMonitoramento() async {
    _monitorando = false;
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _linhaMonitorada = null;
  }

  /// Verifica se o dispositivo está disponível
  /// 
  /// Verifica se existe dados no caminho /dados/{idOnibus}
  Future<bool> verificarDisponibilidade({required String idOnibus}) async {
    try {
      final path = 'dados/$idOnibus';
      final snapshot = await _database.child(path).get();
      return snapshot.exists;
    } catch (e) {
      print('Erro ao verificar disponibilidade Realtime Database: $e');
      return false;
    }
  }

  /// Retorna a linha monitorada
  String? get linhaMonitorada => _linhaMonitorada;

  /// Retorna a última linha detectada
  String? get ultimaLinhaDetectada => _linhaSelecionada;

  /// Verifica se está monitorando
  bool get isMonitorando => _monitorando;
}

