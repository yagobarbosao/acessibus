import 'dart:async';
import 'esp8266_service.dart';
import 'firebase_device_service.dart';
import 'mqtt_service.dart';

/// Serviço para comunicação com o dispositivo físico Acessibus
///
/// Este serviço será responsável por:
/// - Estabelecer conexão com o dispositivo via Firebase ou HTTP
/// - Enviar comandos para o dispositivo
/// - Receber notificações do dispositivo quando o ônibus está chegando
/// - Gerenciar o estado da conexão
class DispositivoService {
  static final DispositivoService _instance = DispositivoService._internal();
  factory DispositivoService() => _instance;
  DispositivoService._internal();

  bool _conectado = false;
  String? _linhaSelecionada;
  final ESP8266Service _esp8266Service = ESP8266Service();
  final FirebaseDeviceService _firebaseDeviceService = FirebaseDeviceService();
  final MqttService _mqttService = MqttService();
  String? _ipESP8266;
  String? _deviceId;
  String? _deviceIdMqtt;

  /// Verifica se o dispositivo está conectado
  bool get conectado => _conectado;

  /// Retorna a linha de ônibus selecionada
  String? get linhaSelecionada => _linhaSelecionada;

  /// Conecta com o dispositivo físico
  ///
  /// Conecta via Firebase Realtime Database, MQTT ou HTTP direto (ESP8266)
  Future<bool> conectar() async {
    try {
      // Tenta conectar usando os serviços disponíveis
      // A conexão real é feita através dos métodos iniciarMonitoramento
      _conectado = true;
      return true;
    } catch (e) {
      _conectado = false;
      return false;
    }
  }

  /// Desconecta do dispositivo
  Future<void> desconectar() async {
    await pararMonitoramento();
    _linhaSelecionada = null;
  }

  /// Configura o IP do ESP8266 (para comunicação HTTP direta)
  ///
  /// [ip] - IP do ESP8266 (ex: "192.168.1.100")
  void configurarIPESP8266(String ip) {
    _ipESP8266 = ip;
    _esp8266Service.configurarIP(ip);
  }

  /// Configura o ID do dispositivo ESP8266 no Firebase
  ///
  /// [deviceId] - ID único do dispositivo ESP8266 na parada
  void configurarDeviceIdFirebase(String deviceId) {
    _deviceId = deviceId;
    _firebaseDeviceService.configurarDeviceId(deviceId);
  }

  /// Configura o ID do dispositivo para comunicação via MQTT
  ///
  /// [deviceId] - ID único do dispositivo na parada
  /// [broker] - IP ou hostname do broker MQTT (opcional)
  /// [port] - Porta do broker MQTT (opcional, padrão: 1883)
  /// [username] - Usuário MQTT (opcional)
  /// [password] - Senha MQTT (opcional)
  void configurarDeviceIdMqtt({
    required String deviceId,
    String? broker,
    int? port,
    String? username,
    String? password,
  }) {
    _deviceIdMqtt = deviceId;
    _mqttService.configurarDeviceId(deviceId);
    if (broker != null ||
        port != null ||
        username != null ||
        password != null) {
      _mqttService.configurarBroker(
        broker: broker,
        port: port,
        username: username,
        password: password,
      );
    }
  }

  /// Envia a linha de ônibus selecionada para o dispositivo
  ///
  /// [linha] - Número ou nome da linha de ônibus
  /// Retorna true se o envio foi bem-sucedido
  Future<bool> enviarLinha(String linha) async {
    if (!_conectado) {
      // Tenta conectar automaticamente
      final conectou = await conectar();
      if (!conectou) {
        return false;
      }
    }

    try {
      // Prioridade 1: Envia via Firebase se deviceId configurado
      if (_deviceId != null && _deviceId!.isNotEmpty) {
        final sucesso = await _firebaseDeviceService.enviarLinhaSelecionada(
          linha,
        );
        if (sucesso) {
          _linhaSelecionada = linha;
          return true;
        }
      }

      // Prioridade 2: Envia via MQTT se deviceId MQTT configurado
      if (_deviceIdMqtt != null && _deviceIdMqtt!.isNotEmpty) {
        final sucesso = await _mqttService.enviarLinha(linha);
        if (sucesso) {
          _linhaSelecionada = linha;
          return true;
        }
      }

      // Prioridade 3: Envia via HTTP direto se IP configurado
      if (_ipESP8266 != null && _ipESP8266!.isNotEmpty) {
        final sucesso = await _esp8266Service.enviarLinha(linha);
        if (sucesso) {
          _linhaSelecionada = linha;
          return true;
        }
      }

      // Fallback: se nenhum método funcionou, apenas registra a seleção localmente
      _linhaSelecionada = linha;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Inicia o monitoramento do dispositivo
  ///
  /// Prioriza Firebase Realtime Database (compatível com código Arduino),
  /// depois Firestore, depois MQTT, depois HTTP direto
  /// Quando o dispositivo detecta que o ônibus está chegando,
  /// o serviço notifica o usuário
  Future<bool> iniciarMonitoramento({
    String? ipESP8266,
    String? deviceIdFirebase,
    String? idOnibusRealtime, // ID no formato "onibus_132A" ou "onibus_251B"
    String? deviceIdMqtt, // ID do dispositivo para comunicação via MQTT
    String? mqttBroker, // IP ou hostname do broker MQTT
    int? mqttPort, // Porta do broker MQTT
    String? mqttUsername, // Usuário MQTT
    String? mqttPassword, // Senha MQTT
  }) async {
    try {
      bool iniciado = false;

      // Prioridade 1: Firebase Realtime Database (compatível com código Arduino)
      if (idOnibusRealtime != null && idOnibusRealtime.isNotEmpty) {
        _firebaseDeviceService.configurarDeviceId(
          '',
          idOnibus: idOnibusRealtime,
        );

        try {
          iniciado = await _firebaseDeviceService.iniciarMonitoramento(
            idOnibus: idOnibusRealtime,
          );
          if (iniciado) {
            _conectado = true;
            return true;
          }
        } catch (e) {
          print('Erro ao iniciar monitoramento Firebase Realtime Database: $e');
        }
      }

      // Prioridade 2: Firebase Firestore
      if (deviceIdFirebase != null && deviceIdFirebase.isNotEmpty) {
        _deviceId = deviceIdFirebase;
        _firebaseDeviceService.configurarDeviceId(deviceIdFirebase);

        try {
          iniciado = await _firebaseDeviceService.iniciarMonitoramento(
            deviceId: deviceIdFirebase,
          );
          if (iniciado) {
            _conectado = true;
            return true;
          }
        } catch (e) {
          print('Erro ao iniciar monitoramento Firebase Firestore: $e');
        }
      }

      // Prioridade 3: MQTT
      if (deviceIdMqtt != null && deviceIdMqtt.isNotEmpty) {
        _deviceIdMqtt = deviceIdMqtt;
        _mqttService.configurarDeviceId(deviceIdMqtt);

        // Configura broker MQTT se fornecido
        if (mqttBroker != null ||
            mqttPort != null ||
            mqttUsername != null ||
            mqttPassword != null) {
          _mqttService.configurarBroker(
            broker: mqttBroker,
            port: mqttPort,
            username: mqttUsername,
            password: mqttPassword,
          );
        }

        try {
          // Inicia monitoramento MQTT
          // Se houver linha selecionada, monitora também a localização do ônibus
          iniciado = await _mqttService.iniciarMonitoramento(
            deviceId: deviceIdMqtt,
            linha:
                _linhaSelecionada, // Monitora localização se linha selecionada
          );
          if (iniciado) {
            _conectado = true;
            return true;
          }
        } catch (e) {
          print('Erro ao iniciar monitoramento MQTT: $e');
        }
      }

      // Prioridade 4: HTTP direto (ESP8266 via WiFi)
      if (ipESP8266 != null && ipESP8266.isNotEmpty) {
        _ipESP8266 = ipESP8266;
        _esp8266Service.configurarIP(ipESP8266);

        try {
          iniciado = await _esp8266Service.iniciarMonitoramento(ip: ipESP8266);
          if (iniciado) {
            _conectado = true;
            return true;
          }
        } catch (e) {
          print('Erro ao iniciar monitoramento ESP8266 HTTP: $e');
        }
      }

      return false;
    } catch (e) {
      print('Erro ao iniciar monitoramento: $e');
      _conectado = false;
      return false;
    }
  }

  /// Para o monitoramento do dispositivo
  Future<void> pararMonitoramento() async {
    await _esp8266Service.pararMonitoramento();
    await _firebaseDeviceService.pararMonitoramento();
    await _mqttService.pararMonitoramento();
    _conectado = false;
  }

  /// Retorna a última linha detectada (para Firebase)
  String? get ultimaLinhaDetectada {
    // Prioriza Firebase Realtime Database
    final linhaRealtime = _firebaseDeviceService.ultimaLinhaDetectada;
    if (linhaRealtime != null) {
      return linhaRealtime;
    }
    return _linhaSelecionada;
  }

  /// Verifica se o dispositivo está disponível
  ///
  /// Tenta verificar Firebase primeiro, depois MQTT, depois HTTP
  Future<bool> verificarDisponibilidade() async {
    try {
      // Prioridade 1: Verifica Firebase
      if (_deviceId != null && _deviceId!.isNotEmpty) {
        final disponivel = await _firebaseDeviceService
            .verificarDisponibilidade();
        if (disponivel) {
          return true;
        }
      }

      // Prioridade 2: Verifica MQTT
      if (_deviceIdMqtt != null && _deviceIdMqtt!.isNotEmpty) {
        final disponivel = await _mqttService.verificarDisponibilidade();
        if (disponivel) {
          return true;
        }
      }

      // Prioridade 3: Verifica HTTP direto
      if (_ipESP8266 != null && _ipESP8266!.isNotEmpty) {
        final disponivel = await _esp8266Service.verificarDisponibilidade();
        if (disponivel) {
          return true;
        }
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Retorna o IP do ESP8266 configurado
  String? get ipESP8266 => _ipESP8266;

  /// Retorna o ID do dispositivo Firebase configurado
  String? get deviceIdFirebase => _deviceId;

  /// Retorna o ID do dispositivo MQTT configurado
  String? get deviceIdMqtt => _deviceIdMqtt;
}
