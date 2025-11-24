import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_database/firebase_database.dart';
import 'notificacao_service.dart';
import 'auth_service.dart';

/// Serviço para comunicação com dispositivos IoT via MQTT
///
/// Este serviço permite:
/// - Conectar ao broker MQTT
/// - Subscrever tópicos para receber dados do dispositivo
/// - Publicar comandos para o dispositivo
/// - Receber notificações quando o ônibus está chegando
class MqttService {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  final NotificacaoService _notificacaoService = NotificacaoService();
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final AuthService _authService = AuthService();
  MqttServerClient? _client;
  bool _conectado = false;
  bool _monitorando = false;
  String? _linhaSelecionada;
  String? _deviceId;
  bool _salvarNoFirebase = true; // Flag para controlar se salva no Firebase

  // Configurações padrão do broker MQTT (carregadas do .env ou valores padrão)
  String get _broker {
    try {
      if (dotenv.isInitialized) {
        return dotenv.env['MQTT_BROKER'] ?? '134.209.9.157';
      }
    } catch (e) {}
    return '134.209.9.157';
  }

  int get _port {
    try {
      if (dotenv.isInitialized) {
        return int.tryParse(dotenv.env['MQTT_PORT'] ?? '1883') ?? 1883;
      }
    } catch (e) {}
    return 1883;
  }

  String get _username {
    try {
      if (dotenv.isInitialized) {
        return dotenv.env['MQTT_USERNAME'] ?? 'acessibus';
      }
    } catch (e) {}
    return 'acessibus';
  }

  String get _password {
    try {
      if (dotenv.isInitialized) {
        return dotenv.env['MQTT_PASSWORD'] ?? '123456';
      }
    } catch (e) {}
    return '123456';
  }

  String _clientId = 'acessibus_app_${DateTime.now().millisecondsSinceEpoch}';

  // Tópicos MQTT (conforme códigos Arduino)
  static const String _topicoParadasSolicitacoes = 'paradas/solicitacoes';
  static const String _topicoParadasSelecao =
      'paradas/selecao'; // Seleção de botões
  static const String _topicoOnibusChegando =
      'onibus/chegando'; // Notificação de chegada
  static const String _topicoLocalizacaoOnibus = 'localizacao_onibus';

  // Callbacks para notificar quando receber dados
  Function(String linha, double distancia, String alerta)? _onDadosParada;
  Function(String linha, double lat, double lon)? _onLocalizacaoOnibus;
  Function(String linha, String tipoDeficiencia, String alerta)? _onAlertaBotao;
  Function(String linha, String tipoDeficiencia, String paradaId)?
  _onSelecaoBotao;
  Function(String linha, String paradaId)?
  _onOnibusChegando; // Callback para aviso de chegada

  // Armazena seleções de botões por parada
  Map<String, Map<String, String>> _selecoesParadas =
      {}; // {paradaId: {linha, tipo}}

  // Variáveis internas para sobrescrever valores padrão
  String? _brokerOverride;
  int? _portOverride;
  String? _usernameOverride;
  String? _passwordOverride;

  String get _brokerValue => _brokerOverride ?? _broker;
  int get _portValue => _portOverride ?? _port;
  String get _usernameValue => _usernameOverride ?? _username;
  String get _passwordValue => _passwordOverride ?? _password;

  /// Configura as credenciais do broker MQTT
  ///
  /// [broker] - IP ou hostname do broker MQTT
  /// [port] - Porta do broker (padrão: 1883)
  /// [username] - Usuário para autenticação
  /// [password] - Senha para autenticação
  void configurarBroker({
    String? broker,
    int? port,
    String? username,
    String? password,
  }) {
    if (broker != null) _brokerOverride = broker;
    if (port != null) _portOverride = port;
    if (username != null) _usernameOverride = username;
    if (password != null) _passwordOverride = password;
  }

  /// Configura o ID do dispositivo
  ///
  /// [deviceId] - ID único do dispositivo na parada
  void configurarDeviceId(String deviceId) {
    _deviceId = deviceId;
  }

  /// Configura callback para receber dados da parada
  ///
  /// [callback] - Função chamada quando receber dados: (linha, distancia, alerta)
  void onDadosParada(
    Function(String linha, double distancia, String alerta) callback,
  ) {
    _onDadosParada = callback;
  }

  /// Configura callback para receber localização do ônibus
  ///
  /// [callback] - Função chamada quando receber localização: (linha, lat, lon)
  void onLocalizacaoOnibus(
    Function(String linha, double lat, double lon) callback,
  ) {
    _onLocalizacaoOnibus = callback;
  }

  /// Configura callback para receber alertas dos botões (visual/auditivo)
  ///
  /// [callback] - Função chamada quando receber alerta: (linha, tipoDeficiencia, alerta)
  /// tipoDeficiencia: "visual" ou "auditivo"
  void onAlertaBotao(
    Function(String linha, String tipoDeficiencia, String alerta) callback,
  ) {
    _onAlertaBotao = callback;
  }

  /// Configura callback para receber seleções de botões da parada
  ///
  /// [callback] - Função chamada quando receber seleção: (linha, tipoDeficiencia, paradaId)
  void onSelecaoBotao(
    Function(String linha, String tipoDeficiencia, String paradaId) callback,
  ) {
    _onSelecaoBotao = callback;
  }

  /// Configura callback para receber avisos de chegada do ônibus
  ///
  /// [callback] - Função chamada quando receber aviso: (linha, paradaId)
  void onOnibusChegando(Function(String linha, String paradaId) callback) {
    _onOnibusChegando = callback;
  }

  /// Publica notificação de chegada do ônibus para uma parada específica
  ///
  /// [paradaId] - ID da parada (ex: "parada_123")
  /// [linha] - Linha do ônibus que chegou
  Future<bool> publicarChegadaOnibus(String paradaId, String linha) async {
    if (!_conectado || _client == null) {
      print('MQTT: Não conectado, tentando conectar...');
      final conectou = await conectar();
      if (!conectou) {
        print('MQTT: ❌ Falha ao conectar para publicar chegada');
        return false;
      }
    }

    try {
      final topico = '$_topicoOnibusChegando/$paradaId';
      final payload = '{"linha":"$linha"}';

      print('MQTT: Preparando publicação de chegada...');
      print('MQTT: Tópico: $topico');
      print('MQTT: Payload: $payload');

      final builder = MqttClientPayloadBuilder();
      builder.addString(payload);

      _client!.publishMessage(topico, MqttQos.atLeastOnce, builder.payload!);

      print(
        'MQTT: ✅ Publicado chegada do ônibus - Parada: $paradaId, Linha: $linha',
      );
      print(
        'MQTT: O dispositivo físico $paradaId deve receber o alerta agora!',
      );
      return true;
    } catch (e, stackTrace) {
      print('MQTT: ❌ Erro ao publicar chegada do ônibus: $e');
      print('Stack trace: $stackTrace');
      return false;
    }
  }

  /// Calcula distância entre duas coordenadas (Haversine)
  ///
  /// Retorna distância em metros
  double _calcularDistancia(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double raioTerra = 6371000; // Raio da Terra em metros

    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return raioTerra * c;
  }

  /// Configura coordenadas de uma parada para cálculo de proximidade
  ///
  /// [paradaId] - ID da parada
  /// [lat] - Latitude da parada
  /// [lon] - Longitude da parada
  void configurarParada(String paradaId, double lat, double lon) {
    if (!_coordenadasParadas.containsKey(paradaId)) {
      _coordenadasParadas[paradaId] = {'lat': lat, 'lon': lon};
      print('MQTT: Parada configurada - ID: $paradaId, Lat: $lat, Lon: $lon');
    }
  }

  // Armazena coordenadas das paradas
  Map<String, Map<String, double>> _coordenadasParadas = {};

  /// Define a distância mínima para considerar o ônibus próximo (em metros)
  double distanciaProximidade = 50.0; // 50 metros por padrão

  /// Conecta ao broker MQTT
  Future<bool> conectar() async {
    if (_conectado && _client != null) {
      print('MQTT: Já está conectado');
      return true;
    }

    try {
      print('MQTT: Iniciando conexão...');
      print('MQTT: Broker: $_brokerValue');
      print('MQTT: Porta: $_portValue');
      print('MQTT: Usuário: $_usernameValue');
      print('MQTT: Client ID: $_clientId');

      // Cria cliente MQTT
      _client = MqttServerClient.withPort(_brokerValue, _clientId, _portValue);
      _client!.logging(on: true); // Ativa logs para debug
      _client!.keepAlivePeriod = 20;
      _client!.autoReconnect = true;
      _client!.onDisconnected = _onDisconnected;
      _client!.onConnected = _onConnected;
      _client!.onSubscribed = _onSubscribed;

      // Configura credenciais
      final connMessage = MqttConnectMessage()
          .withClientIdentifier(_clientId)
          .startClean()
          .withWillQos(MqttQos.atLeastOnce)
          .authenticateAs(_usernameValue, _passwordValue);

      _client!.connectionMessage = connMessage;

      // Conecta
      print('MQTT: Tentando conectar...');
      await _client!.connect();

      print('MQTT: Status da conexão: ${_client!.connectionStatus?.state}');

      if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
        _conectado = true;
        print(
          'MQTT: ✅ Conectado com sucesso ao broker $_brokerValue:$_portValue',
        );
        return true;
      } else {
        print(
          'MQTT: ❌ Falha ao conectar. Estado: ${_client!.connectionStatus?.state}',
        );
        print('MQTT: Return code: ${_client!.connectionStatus?.returnCode}');
        return false;
      }
    } catch (e, stackTrace) {
      print('MQTT: ❌ Erro ao conectar: $e');
      print('Stack trace: $stackTrace');
      _conectado = false;
      return false;
    }
  }

  /// Verifica o status atual da conexão MQTT
  void verificarStatus() {
    print('=== STATUS MQTT ===');
    print('Conectado: $_conectado');
    print('Monitorando: $_monitorando');
    print('Client: ${_client != null ? "Criado" : "Null"}');
    if (_client != null) {
      print('Estado da conexão: ${_client!.connectionStatus?.state}');
      print('Return code: ${_client!.connectionStatus?.returnCode}');
    }
    print('Broker: $_brokerValue');
    print('Porta: $_portValue');
    print('Client ID: $_clientId');
    print('==================');
  }

  /// Desconecta do broker MQTT
  Future<void> desconectar() async {
    await pararMonitoramento();

    if (_client != null) {
      _client!.disconnect();
      _client = null;
    }

    _conectado = false;
  }

  /// Callback quando conecta ao broker
  void _onConnected() {
    print('MQTT: ✅ Callback _onConnected chamado - Conectado ao broker');
    _conectado = true;
  }

  /// Callback quando desconecta do broker
  void _onDisconnected() {
    print('MQTT: Desconectado do broker');
    _conectado = false;
  }

  /// Callback quando subscreve em um tópico
  void _onSubscribed(String topic) {
    print('MQTT: ✅ Subscrito com sucesso ao tópico: $topic');
  }

  /// Inicia monitoramento de dados do dispositivo via MQTT
  ///
  /// Subscreve aos tópicos:
  /// - paradas/solicitacoes/{idOnibus} - dados da parada (distância, alerta)
  /// - localizacao_onibus/linha_{linha} - localização do ônibus (lat, lon)
  ///
  /// [deviceId] - ID do dispositivo na parada (opcional)
  /// [linha] - Número da linha para monitorar localização (opcional)
  Future<bool> iniciarMonitoramento({String? deviceId, String? linha}) async {
    if (_monitorando) return true;

    if (deviceId != null) {
      _deviceId = deviceId;
    }

    // Conecta se não estiver conectado
    if (!_conectado) {
      final conectou = await conectar();
      if (!conectou) {
        return false;
      }
    }

    try {
      // Subscreve aos tópicos usando wildcards para receber todas as mensagens
      // Tópico: paradas/solicitacoes/+ (recebe todas as solicitações)
      _client!.subscribe(
        '${_topicoParadasSolicitacoes}/+',
        MqttQos.atLeastOnce,
      );

      // Subscreve ao tópico de seleção de botões (paradas/selecao/+)
      final topicoSelecao = '$_topicoParadasSelecao/+';
      print('MQTT: Tentando subscrever ao tópico: $topicoSelecao');
      _client!.subscribe(topicoSelecao, MqttQos.atLeastOnce);
      print('MQTT: ✅ Comando de subscrição enviado para: $topicoSelecao');

      // Subscreve ao tópico de chegada do ônibus (onibus/chegando/+)
      _client!.subscribe('$_topicoOnibusChegando/+', MqttQos.atLeastOnce);
      print('MQTT: Subscrito ao tópico de chegada: $_topicoOnibusChegando/+');

      // Subscreve ao tópico de localização do ônibus usando wildcard para receber todas as linhas
      // Isso permite receber localização de qualquer linha (132A, 251B, etc.)
      final topicoLocalizacaoWildcard = '$_topicoLocalizacaoOnibus/+';
      _client!.subscribe(topicoLocalizacaoWildcard, MqttQos.atLeastOnce);
      print(
        'MQTT: Subscrito ao tópico de localização (wildcard): $topicoLocalizacaoWildcard',
      );

      // Se uma linha foi especificada, também subscreve especificamente (para garantir)
      if (linha != null && linha.isNotEmpty) {
        final topicoLocalizacao = '$_topicoLocalizacaoOnibus/linha_$linha';
        _client!.subscribe(topicoLocalizacao, MqttQos.atLeastOnce);
        _linhaSelecionada = linha;
        print(
          'MQTT: Subscrito ao tópico de localização específico: $topicoLocalizacao',
        );
      }

      // Listener para mensagens recebidas
      print('MQTT: Configurando listener de mensagens...');

      // Verifica se o stream de updates está disponível
      if (_client!.updates == null) {
        print('MQTT: ❌ ERRO CRÍTICO: Stream de updates é null!');
        return false;
      }

      print('MQTT: Stream de updates disponível, configurando listener...');

      _client!.updates!.listen(
        (List<MqttReceivedMessage<MqttMessage?>>? c) {
          print(
            'MQTT: 🔔 Listener acionado! Lista recebida: ${c?.length ?? 0} mensagens',
          );

          if (c == null || c.isEmpty) {
            print('MQTT: ⚠️ Mensagem recebida vazia ou nula');
            return;
          }

          print('MQTT: Processando ${c.length} mensagem(ns)...');

          for (int i = 0; i < c.length; i++) {
            try {
              final message = c[i];
              print('MQTT: Mensagem $i - Tipo: ${message.payload.runtimeType}');

              if (message.payload is MqttPublishMessage) {
                final recMess = message.payload as MqttPublishMessage;
                final topic = message.topic;
                final payload = MqttPublishPayload.bytesToStringAsString(
                  recMess.payload.message,
                );

                print('MQTT: 📨 Nova mensagem recebida!');
                print('MQTT: Tópico: $topic');
                print('MQTT: Payload: $payload');

                _processarMensagem(topic, payload);
              } else {
                print(
                  'MQTT: ⚠️ Mensagem não é do tipo MqttPublishMessage: ${message.payload.runtimeType}',
                );
                print('MQTT: Conteúdo: ${message.payload}');
              }
            } catch (e, stackTrace) {
              print('MQTT: ❌ Erro ao processar mensagem $i no listener: $e');
              print('Stack trace: $stackTrace');
            }
          }
        },
        onError: (error) {
          print('MQTT: ❌ Erro no listener de mensagens: $error');
        },
        onDone: () {
          print('MQTT: ⚠️ Listener de mensagens finalizado');
        },
        cancelOnError: false,
      );
      print('MQTT: ✅ Listener de mensagens configurado e ativo');

      _monitorando = true;
      print('MQTT: Monitoramento iniciado');
      return true;
    } catch (e) {
      print('Erro ao iniciar monitoramento MQTT: $e');
      _monitorando = false;
      return false;
    }
  }

  /// Processa mensagens recebidas do broker MQTT
  void _processarMensagem(String topic, String payload) {
    try {
      print('MQTT: ========== PROCESSANDO MENSAGEM ==========');
      print('MQTT: Tópico completo: $topic');
      print('MQTT: Payload completo: $payload');
      print('MQTT: Verificando tipo de mensagem...');

      // Processa mensagens de seleção de botões (paradas/selecao/{paradaId})
      if (topic.contains(_topicoParadasSelecao)) {
        print('MQTT: ✅ Tipo identificado: Seleção de botão');
        _processarSelecaoBotao(topic, payload);
      }

      // Processa mensagens da parada (paradas/solicitacoes/{idOnibus})
      if (topic.contains(_topicoParadasSolicitacoes)) {
        print('MQTT: ✅ Tipo identificado: Dados da parada');
        _processarDadosParada(topic, payload);
      }

      // Processa mensagens de localização do ônibus (localizacao_onibus/linha_{linha})
      if (topic.contains(_topicoLocalizacaoOnibus)) {
        print('MQTT: ✅ Tipo identificado: Localização do ônibus');
        print(
          'MQTT: Tópico contém "_topicoLocalizacaoOnibus": ${topic.contains(_topicoLocalizacaoOnibus)}',
        );
        print('MQTT: _topicoLocalizacaoOnibus = "$_topicoLocalizacaoOnibus"');
        _processarLocalizacaoOnibus(topic, payload);
      }

      // Processa mensagens de chegada do ônibus (onibus/chegando/{paradaId})
      if (topic.contains(_topicoOnibusChegando)) {
        print('MQTT: ✅ Tipo identificado: Chegada do ônibus');
        _processarOnibusChegando(topic, payload);
      }

      print('MQTT: ===========================================');
    } catch (e, stackTrace) {
      print('MQTT: ❌ Erro ao processar mensagem MQTT: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Processa seleção de botões da parada (paradas/selecao/{paradaId})
  ///
  /// Tópico exemplo: paradas/selecao/parada_123
  /// Payload exemplo: {"linha":"132A","tipo":"VISUAL"}
  void _processarSelecaoBotao(String topic, String payload) {
    try {
      // Extrai o ID da parada do tópico
      final parts = topic.split('/');
      final paradaId = parts.length > 2 ? parts[2] : '';

      // Faz parse do JSON
      final jsonData = jsonDecode(payload) as Map<String, dynamic>;
      final linha = jsonData['linha']?.toString() ?? '';
      final tipo = jsonData['tipo']?.toString().toUpperCase() ?? '';

      print(
        'MQTT: Seleção de botão - Parada: $paradaId, Linha: $linha, Tipo: $tipo',
      );

      // Armazena a seleção
      if (paradaId.isNotEmpty && linha.isNotEmpty && tipo.isNotEmpty) {
        _selecoesParadas[paradaId] = {'linha': linha, 'tipo': tipo};

        // Salva no Firebase se habilitado
        if (_salvarNoFirebase) {
          _salvarSelecaoBotaoNoFirebase(paradaId, linha, tipo);
        }

        // Verifica se a linha do botão corresponde à linha selecionada no app
        // Só notifica se corresponder
        _verificarENotificarSelecaoBotao(linha, tipo.toLowerCase(), paradaId);

        // Chama callback se configurado
        if (_onSelecaoBotao != null) {
          _onSelecaoBotao!(linha, tipo.toLowerCase(), paradaId);
        }
      }
    } catch (e) {
      print('Erro ao processar seleção de botão MQTT: $e');
    }
  }

  /// Verifica se há uma seleção ativa para uma parada e linha
  ///
  /// [paradaId] - ID da parada
  /// [linha] - Linha do ônibus
  /// Retorna o tipo de deficiência se houver seleção, null caso contrário
  String? getSelecaoParada(String paradaId, String linha) {
    final selecao = _selecoesParadas[paradaId];
    if (selecao != null && selecao['linha'] == linha) {
      return selecao['tipo']?.toLowerCase();
    }
    return null;
  }

  /// Processa dados da parada (paradas/solicitacoes/{idOnibus})
  ///
  /// Tópico exemplo: paradas/solicitacoes/onibus_132A
  /// Payload exemplo: {"distancia":0.45,"alerta":"ALERTA: Proximo!"}
  /// Payload com botão: {"botao":"visual","linha":"132A","alerta":"ALERTA: Botão Visual Pressionado!"}
  /// Payload com botão: {"botao":"auditivo","linha":"133B","alerta":"ALERTA: Botão Auditivo Pressionado!"}
  void _processarDadosParada(String topic, String payload) {
    try {
      // Extrai o ID do ônibus do tópico (ex: "onibus_132A" de "paradas/solicitacoes/onibus_132A")
      final parts = topic.split('/');
      final idOnibus = parts.length > 2 ? parts[2] : '';

      // Extrai o número da linha do ID (ex: "132A" de "onibus_132A")
      String linha = idOnibus;
      if (idOnibus.startsWith('onibus_')) {
        linha = idOnibus.substring(7); // Remove "onibus_"
      }

      // Faz parse do JSON
      final jsonData = jsonDecode(payload) as Map<String, dynamic>;

      // Verifica se é um alerta de botão (visual ou auditivo)
      final botaoStr = jsonData['botao']?.toString();
      if (botaoStr != null) {
        final botao = botaoStr.toLowerCase();
        if (botao == 'visual' || botao == 'auditivo') {
          // É um alerta de botão pressionado
          final linhaBotao = jsonData['linha']?.toString() ?? linha;
          final alerta =
              jsonData['alerta']?.toString() ??
              'Botão ${botao == 'visual' ? 'Visual' : 'Auditivo'} pressionado';

          print(
            'MQTT: Alerta de botão - Linha: $linhaBotao, Tipo: $botao, Alerta: $alerta',
          );

          // Chama callback específico para alertas de botão
          if (_onAlertaBotao != null) {
            _onAlertaBotao!(linhaBotao, botao, alerta);
          }

          // Processa o alerta com o tipo de deficiência
          _processarAlertaBotao(linhaBotao, botao, alerta);
          return;
        }
      }

      // Processamento normal (distância e alerta de proximidade)
      final distancia = (jsonData['distancia'] as num?)?.toDouble() ?? 0.0;
      final alerta = jsonData['alerta']?.toString() ?? '';

      print(
        'MQTT: Dados da parada - Linha: $linha, Distância: $distancia m, Alerta: $alerta',
      );

      // Chama callback se configurado
      if (_onDadosParada != null) {
        _onDadosParada!(linha, distancia, alerta);
      }

      // Verifica se o ônibus está próximo (distância < 0.5m conforme código Arduino)
      if (distancia < 0.5 && alerta.toLowerCase().contains('proximo')) {
        _processarAlerta(linha, distancia, alerta);
      }
    } catch (e) {
      print('Erro ao processar dados da parada MQTT: $e');
    }
  }

  /// Processa localização do ônibus (localizacao_onibus/linha_{linha})
  ///
  /// Tópico exemplo: localizacao_onibus/linha_132A
  /// Payload exemplo: {"lat":-8.047600,"lon":-34.877000}
  void _processarLocalizacaoOnibus(String topic, String payload) {
    try {
      print('MQTT: Processando localização do ônibus...');
      print('MQTT: Tópico: $topic');
      print('MQTT: Payload: $payload');

      // Extrai o número da linha do tópico (ex: "132A" de "localizacao_onibus/linha_132A")
      final parts = topic.split('/');
      String linha = '';
      if (parts.length > 1) {
        final linhaPart = parts[1];
        if (linhaPart.startsWith('linha_')) {
          linha = linhaPart.substring(6); // Remove "linha_"
        }
      }

      print('MQTT: Linha extraída do tópico: "$linha"');

      // Faz parse do JSON
      final jsonData = jsonDecode(payload) as Map<String, dynamic>;
      final lat = (jsonData['lat'] as num?)?.toDouble();
      final lon = (jsonData['lon'] as num?)?.toDouble();

      print('MQTT: Dados extraídos - Lat: $lat, Lon: $lon');

      if (lat != null && lon != null) {
        print(
          'MQTT: ✅ Localização do ônibus válida - Linha: $linha, Lat: $lat, Lon: $lon',
        );

        // Salva no Firebase se habilitado
        if (_salvarNoFirebase) {
          print('MQTT: Salvando localização no Firebase...');
          _salvarLocalizacaoNoFirebase(linha, lat, lon);
        }

        // Chama callback se configurado
        if (_onLocalizacaoOnibus != null) {
          print('MQTT: Chamando callback de localização...');
          try {
            _onLocalizacaoOnibus!(linha, lat, lon);
            print('MQTT: ✅ Callback de localização executado com sucesso');
          } catch (e, stackTrace) {
            print('MQTT: ❌ Erro ao executar callback de localização: $e');
            print('Stack trace: $stackTrace');
          }
        } else {
          print('MQTT: ⚠️ Nenhum callback de localização configurado');
        }

        // Verifica se há seleções ativas para esta linha e publica chegada se necessário
        _verificarProximidadeParadas(linha, lat, lon);
      } else {
        print('MQTT: ❌ Dados de localização inválidos - Lat: $lat, Lon: $lon');
      }
    } catch (e, stackTrace) {
      print('MQTT: ❌ Erro ao processar localização do ônibus MQTT: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Verifica se o ônibus está próximo de alguma parada com seleção ativa
  ///
  /// [linha] - Linha do ônibus
  /// [lat] - Latitude do ônibus
  /// [lon] - Longitude do ônibus
  void _verificarProximidadeParadas(String linha, double lat, double lon) {
    print(
      'MQTT: Verificando proximidade - Linha: $linha, Lat: $lat, Lon: $lon',
    );
    print('MQTT: Seleções ativas: ${_selecoesParadas.length}');

    // Para cada parada com seleção ativa
    _selecoesParadas.forEach((paradaId, selecao) {
      final linhaSelecionada = selecao['linha'];
      final tipoDeficiencia = selecao['tipo'];

      print(
        'MQTT: Verificando parada $paradaId - Linha selecionada: $linhaSelecionada, Tipo: $tipoDeficiencia',
      );

      // Se a linha selecionada corresponde à linha do ônibus
      if (linhaSelecionada == linha) {
        print(
          'MQTT: ✅ Linha $linha corresponde à seleção da parada $paradaId!',
        );

        // Verifica se temos coordenadas da parada
        final coordsParada = _coordenadasParadas[paradaId];

        if (coordsParada != null) {
          // Calcula distância real
          final distancia = _calcularDistancia(
            lat,
            lon,
            coordsParada['lat']!,
            coordsParada['lon']!,
          );

          print(
            'MQTT: Distância do ônibus $linha até parada $paradaId: ${distancia.toStringAsFixed(2)}m (limite: ${distanciaProximidade}m)',
          );

          // Se está próximo (dentro da distância configurada)
          if (distancia <= distanciaProximidade) {
            print(
              'MQTT: 🚌 Ônibus $linha está próximo! Publicando chegada para parada $paradaId',
            );
            publicarChegadaOnibus(paradaId, linha);

            // Remove a seleção após publicar (evita múltiplas publicações)
            _selecoesParadas.remove(paradaId);
            print(
              'MQTT: ✅ Seleção da parada $paradaId removida após publicar chegada',
            );
          } else {
            print(
              'MQTT: ⏳ Ônibus $linha ainda está longe da parada $paradaId (${distancia.toStringAsFixed(2)}m > ${distanciaProximidade}m)',
            );
          }
        } else {
          // Se não tem coordenadas configuradas, publica imediatamente
          print('MQTT: ⚠️ Parada $paradaId sem coordenadas configuradas');
          print(
            'MQTT: 🚌 Publicando chegada imediatamente para parada $paradaId',
          );
          publicarChegadaOnibus(paradaId, linha).then((publicado) {
            if (publicado) {
              print('MQTT: ✅ Chegada publicada com sucesso!');
            } else {
              print('MQTT: ❌ Falha ao publicar chegada');
            }
          });

          // Remove a seleção após publicar
          _selecoesParadas.remove(paradaId);
          print(
            'MQTT: ✅ Seleção da parada $paradaId removida após publicar chegada',
          );
        }
      } else {
        print(
          'MQTT: ⏭️ Linha $linha não corresponde à seleção da parada $paradaId (esperava: $linhaSelecionada)',
        );
      }
    });

    if (_selecoesParadas.isEmpty) {
      print('MQTT: ℹ️ Nenhuma seleção ativa no momento');
    }
  }

  /// Processa alertas de chegada do ônibus
  Future<void> _processarAlerta(
    String linha,
    double distancia,
    String alerta,
  ) async {
    try {
      print(
        'MQTT: Alerta - Linha: $linha, Distância: ${distancia.toStringAsFixed(2)}m',
      );

      // Notifica o usuário
      final distanciaStr = distancia.toStringAsFixed(2);
      await _notificacaoService.notificarOnibusChegando(
        linha,
        distancia: distanciaStr,
      );
    } catch (e) {
      print('Erro ao processar alerta MQTT: $e');
    }
  }

  /// Processa alertas de botão pressionado (visual ou auditivo)
  ///
  /// [linha] - Linha do ônibus associada ao botão
  /// [tipoDeficiencia] - "visual" ou "auditivo"
  /// [alerta] - Mensagem de alerta
  Future<void> _processarAlertaBotao(
    String linha,
    String tipoDeficiencia,
    String alerta,
  ) async {
    try {
      print(
        'MQTT: Alerta de botão - Linha: $linha, Tipo: $tipoDeficiencia, Alerta: $alerta',
      );

      // Notifica o usuário com o tipo de alerta apropriado
      await _notificacaoService.notificarAlertaBotao(
        linha,
        tipoDeficiencia: tipoDeficiencia,
        mensagem: alerta,
      );
    } catch (e) {
      print('Erro ao processar alerta de botão MQTT: $e');
    }
  }

  /// Processa mensagens de chegada do ônibus (onibus/chegando/{paradaId})
  ///
  /// Tópico exemplo: onibus/chegando/parada_123
  /// Payload exemplo: {"linha":"132A"}
  void _processarOnibusChegando(String topic, String payload) {
    try {
      // Extrai o ID da parada do tópico
      final parts = topic.split('/');
      final paradaId = parts.length > 2 ? parts[2] : '';

      // Faz parse do JSON
      final jsonData = jsonDecode(payload) as Map<String, dynamic>;
      final linha = jsonData['linha']?.toString() ?? '';

      print('MQTT: Ônibus chegando - Parada: $paradaId, Linha: $linha');

      // Chama callback se configurado
      if (_onOnibusChegando != null &&
          linha.isNotEmpty &&
          paradaId.isNotEmpty) {
        _onOnibusChegando!(linha, paradaId);
      }

      // Notifica o usuário no app
      _notificarChegadaOnibus(linha, paradaId);
    } catch (e) {
      print('Erro ao processar mensagem de chegada do ônibus: $e');
    }
  }

  /// Notifica o usuário quando o ônibus está chegando
  ///
  /// [linha] - Linha do ônibus
  /// [paradaId] - ID da parada
  Future<void> _notificarChegadaOnibus(String linha, String paradaId) async {
    try {
      if (linha.isEmpty) return;

      print('MQTT: Notificando chegada do ônibus $linha na parada $paradaId');

      // Salva no Firebase se habilitado
      if (_salvarNoFirebase) {
        _salvarChegadaNoFirebase(linha, paradaId);
      }

      // Mostra notificação no app
      await _notificacaoService.notificarOnibusChegando(
        linha,
        distancia: null, // Não temos distância exata neste caso
      );
    } catch (e) {
      print('Erro ao notificar chegada do ônibus: $e');
    }
  }

  /// Verifica se a linha do botão corresponde à linha selecionada no app e notifica
  ///
  /// [linha] - Linha do ônibus do botão
  /// [tipo] - "visual" ou "auditivo"
  /// [paradaId] - ID da parada
  Future<void> _verificarENotificarSelecaoBotao(
    String linha,
    String tipo,
    String paradaId,
  ) async {
    try {
      if (linha.isEmpty || tipo.isEmpty) return;

      print(
        'MQTT: Verificando seleção de botão - Linha: $linha, Tipo: $tipo, Parada: $paradaId',
      );

      // Busca a linha selecionada pelo usuário no app
      final linhaSelecionadaApp = await _obterLinhaSelecionadaApp();

      if (linhaSelecionadaApp == null || linhaSelecionadaApp.isEmpty) {
        print(
          'MQTT: ⚠️ Nenhuma linha selecionada no app. Botão pressionado será ignorado.',
        );
        return;
      }

      print('MQTT: Linha selecionada no app: $linhaSelecionadaApp');
      print('MQTT: Linha do botão: $linha');

      // Verifica se a linha do botão corresponde à linha selecionada no app
      if (linhaSelecionadaApp.toUpperCase() != linha.toUpperCase()) {
        print(
          'MQTT: ⚠️ Linha do botão ($linha) não corresponde à linha selecionada no app ($linhaSelecionadaApp). Notificação não será enviada.',
        );
        return;
      }

      print(
        'MQTT: ✅ Linha do botão corresponde à linha selecionada! Notificando usuário...',
      );

      // Determina a mensagem baseada no tipo
      final mensagem = tipo == 'visual'
          ? 'Botão Visual pressionado! Aguardando ônibus da linha $linha'
          : 'Botão Auditivo pressionado! Aguardando ônibus da linha $linha';

      // Mostra notificação no app com alerta apropriado
      await _notificacaoService.notificarAlertaBotao(
        linha,
        tipoDeficiencia: tipo,
        mensagem: mensagem,
      );

      print('MQTT: ✅ Notificação de seleção de botão enviada');
    } catch (e, stackTrace) {
      print('❌ Erro ao verificar e notificar seleção de botão: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Obtém a linha selecionada pelo usuário no app (do Firebase)
  ///
  /// Retorna o número da linha (ex: "132A") ou null se não houver seleção
  Future<String?> _obterLinhaSelecionadaApp() async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null || currentUser.isEmpty) {
        print('MQTT: Usuário não está logado');
        return null;
      }

      final emailKey = currentUser['emailKey'] as String?;
      if (emailKey == null || emailKey.isEmpty) {
        print('MQTT: EmailKey não encontrado');
        return null;
      }

      // Busca a linha selecionada no Firebase
      final linhaRef = _database
          .child('user')
          .child(emailKey)
          .child('linhaSelecionada');
      final snapshot = await linhaRef.get();

      if (!snapshot.exists || snapshot.value == null) {
        print('MQTT: Nenhuma linha selecionada no Firebase');
        return null;
      }

      final linhaData = snapshot.value as Map<dynamic, dynamic>?;
      if (linhaData == null) {
        return null;
      }

      final numeroLinha = linhaData['numero']?.toString();
      print('MQTT: Linha selecionada encontrada: $numeroLinha');
      return numeroLinha;
    } catch (e) {
      print('MQTT: Erro ao obter linha selecionada: $e');
      return null;
    }
  }

  /// Salva localização do ônibus no Firebase Realtime Database
  ///
  /// Formato: /dados/onibus_{linha}/latitude, longitude, timestamp
  Future<void> _salvarLocalizacaoNoFirebase(
    String linha,
    double lat,
    double lon,
  ) async {
    try {
      final idOnibus = 'onibus_$linha';
      final path = 'dados/$idOnibus';

      await _database.child(path).update({
        'latitude': lat,
        'longitude': lon,
        'timestamp': ServerValue.timestamp,
        'fonte': 'mqtt', // Indica que veio do MQTT
      });
      print('MQTT: ✅ Localização salva no Firebase - Linha: $linha');
    } catch (e, stackTrace) {
      print('❌ Erro ao salvar localização no Firebase: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Salva aviso de chegada do ônibus no Firebase
  ///
  /// Formato: /chegadas/{paradaId}/{timestamp}/linha, timestamp
  Future<void> _salvarChegadaNoFirebase(String linha, String paradaId) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = 'chegadas/$paradaId/$timestamp';

      await _database.child(path).set({
        'linha': linha,
        'timestamp': ServerValue.timestamp,
        'fonte': 'mqtt', // Indica que veio do MQTT
      });
      print(
        'MQTT: ✅ Chegada salva no Firebase - Parada: $paradaId, Linha: $linha',
      );
    } catch (e, stackTrace) {
      print('❌ Erro ao salvar chegada no Firebase: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Salva seleção de botão no Firebase
  ///
  /// Formato: /selecoes/{paradaId}/{timestamp}/linha, tipo, timestamp
  Future<void> _salvarSelecaoBotaoNoFirebase(
    String paradaId,
    String linha,
    String tipo,
  ) async {
    try {
      print(
        'MQTT: Tentando salvar seleção no Firebase - Parada: $paradaId, Linha: $linha, Tipo: $tipo',
      );
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = 'selecoes/$paradaId/$timestamp';

      final data = {
        'linha': linha,
        'tipo': tipo,
        'timestamp': ServerValue.timestamp,
        'fonte': 'mqtt', // Indica que veio do MQTT
      };

      print('MQTT: Caminho Firebase: $path');
      print('MQTT: Dados: $data');

      await _database.child(path).set(data);
      print('MQTT: ✅ Seleção de botão salva no Firebase com sucesso!');
    } catch (e, stackTrace) {
      print('❌ Erro ao salvar seleção de botão no Firebase: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Habilita ou desabilita o salvamento de dados MQTT no Firebase
  ///
  /// [habilitar] - true para salvar, false para não salvar
  void configurarSalvarNoFirebase(bool habilitar) {
    _salvarNoFirebase = habilitar;
    print(
      'MQTT: Salvamento no Firebase ${habilitar ? "habilitado" : "desabilitado"}',
    );
  }

  /// Envia a linha de ônibus selecionada para o dispositivo via MQTT
  ///
  /// NOTA: Atualmente não é usado, pois a parada publica automaticamente
  /// quando o botão é pressionado. Mantido para uso futuro.
  ///
  /// [linha] - Número ou nome da linha de ônibus
  Future<bool> enviarLinha(String linha) async {
    // Atualmente não implementado, pois a parada envia dados
    // automaticamente quando o botão é pressionado
    _linhaSelecionada = linha;
    return true;
  }

  /// Para o monitoramento do dispositivo
  Future<void> pararMonitoramento() async {
    if (!_monitorando) return;

    try {
      if (_client != null) {
        // Unsubscribe dos tópicos
        _client!.unsubscribe('${_topicoParadasSolicitacoes}/+');
        _client!.unsubscribe('$_topicoParadasSelecao/+');
        _client!.unsubscribe('$_topicoOnibusChegando/+');

        if (_linhaSelecionada != null && _linhaSelecionada!.isNotEmpty) {
          final topicoLocalizacao =
              '$_topicoLocalizacaoOnibus/linha_${_linhaSelecionada}';
          _client!.unsubscribe(topicoLocalizacao);
        }
      }

      _monitorando = false;
      print('MQTT: Monitoramento parado');
    } catch (e) {
      print('Erro ao parar monitoramento MQTT: $e');
    }
  }

  /// Verifica se o dispositivo está disponível via MQTT
  Future<bool> verificarDisponibilidade() async {
    if (!_conectado) {
      final conectou = await conectar();
      if (!conectou) {
        return false;
      }
    }

    // Se está conectado, assume que está disponível
    return _conectado;
  }

  /// Retorna se está conectado ao broker
  bool get conectado => _conectado;

  /// Retorna se está monitorando
  bool get monitorando => _monitorando;

  /// Retorna a linha selecionada
  String? get linhaSelecionada => _linhaSelecionada;

  /// Retorna o ID do dispositivo configurado
  String? get deviceId => _deviceId;

  /// Retorna o broker configurado
  String get broker => _brokerValue;

  /// Retorna a porta configurada
  int get port => _portValue;
}
