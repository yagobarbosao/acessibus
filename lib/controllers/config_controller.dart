import 'package:flutter/material.dart';
import '../services/preferences_service.dart';
import '../services/theme_service.dart';
import '../services/dispositivo_service.dart';

/// Controller para gerenciar configurações
/// Responsável por coordenar as operações de configurações do app
class ConfigController extends ChangeNotifier {
  final PreferencesService _prefs = PreferencesService();
  final ThemeService _themeService = ThemeService();
  final DispositivoService _dispositivoService = DispositivoService();
  
  bool _isLoading = true;
  bool _conectando = false;
  bool _conectado = false;
  String _mensagemConexao = 'Procurando dispositivo...';
  String? _dispositivoEncontrado;
  String _deviceId = '';
  String _ipESP8266 = '';
  String _idOnibusRealtime = '';
  
  // Configurações de acessibilidade
  bool _darkTheme = false;
  bool _altoContraste = false;
  bool _leitorTela = true;
  double _tamanhoFonte = 1.0;
  int _tamanhoFonteEspecifico = 18;
  bool _vibracao = true;
  bool _som = true;
  bool _luz = true;
  
  bool get isLoading => _isLoading;
  bool get conectando => _conectando;
  bool get conectado => _conectado;
  String get mensagemConexao => _mensagemConexao;
  String? get dispositivoEncontrado => _dispositivoEncontrado;
  String get deviceId => _deviceId;
  String get ipESP8266 => _ipESP8266;
  String get idOnibusRealtime => _idOnibusRealtime;
  
  bool get darkTheme => _darkTheme;
  bool get altoContraste => _altoContraste;
  bool get leitorTela => _leitorTela;
  double get tamanhoFonte => _tamanhoFonte;
  int get tamanhoFonteEspecifico => _tamanhoFonteEspecifico;
  bool get vibracao => _vibracao;
  bool get som => _som;
  bool get luz => _luz;
  
  /// Carrega todas as configurações
  Future<void> carregarConfiguracoes() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      _darkTheme = await _prefs.getDarkTheme();
      _altoContraste = await _prefs.getAltoContraste();
      _leitorTela = await _prefs.getLeitorTela();
      _tamanhoFonte = await _prefs.getTamanhoFonte();
      _tamanhoFonteEspecifico = await _prefs.getTamanhoFonteEspecifico();
      _vibracao = await _prefs.getVibracao();
      _som = await _prefs.getSom();
      _luz = await _prefs.getLuz();
      _deviceId = await _prefs.getDeviceIdFirebase() ?? '';
      _ipESP8266 = await _prefs.getIpESP8266() ?? '';
      _idOnibusRealtime = await _prefs.getIdOnibusRealtime() ?? '';
      _conectado = _dispositivoService.conectado;
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  /// Salva configurações de dispositivo
  Future<void> salvarConfiguracoesDispositivo({
    String? deviceId,
    String? ipESP8266,
    String? idOnibusRealtime,
    bool mostrarMensagem = true,
  }) async {
    if (deviceId != null) {
      await _prefs.setDeviceIdFirebase(deviceId);
      _deviceId = deviceId;
    }
    if (ipESP8266 != null) {
      await _prefs.setIpESP8266(ipESP8266);
      _ipESP8266 = ipESP8266;
    }
    if (idOnibusRealtime != null) {
      await _prefs.setIdOnibusRealtime(idOnibusRealtime);
      _idOnibusRealtime = idOnibusRealtime;
    }
    
    notifyListeners();
  }
  
  /// Conecta dispositivo
  /// 
  /// Tenta conectar ao dispositivo da parada usando as configurações salvas.
  /// Prioriza: Firebase Realtime Database > Firebase Firestore > MQTT > HTTP direto (ESP8266)
  Future<void> conectarDispositivo() async {
    _conectando = true;
    _mensagemConexao = 'Procurando dispositivo da parada...';
    notifyListeners();
    
    try {
      // Tenta conectar usando as configurações salvas
      bool conectou = false;
      String? dispositivoInfo;
      
      // Prioridade 1: Firebase Realtime Database (compatível com código Arduino)
      if (_idOnibusRealtime.isNotEmpty) {
        _mensagemConexao = 'Conectando via Firebase Realtime Database...';
        notifyListeners();
        
        conectou = await _dispositivoService.iniciarMonitoramento(
          idOnibusRealtime: _idOnibusRealtime,
        );
        
        if (conectou) {
          dispositivoInfo = 'Dispositivo conectado (Firebase Realtime)';
        }
      }
      
      // Prioridade 2: Firebase Firestore
      if (!conectou && _deviceId.isNotEmpty) {
        _mensagemConexao = 'Conectando via Firebase Firestore...';
        notifyListeners();
        
        conectou = await _dispositivoService.iniciarMonitoramento(
          deviceIdFirebase: _deviceId,
        );
        
        if (conectou) {
          dispositivoInfo = 'Dispositivo conectado (Firebase Firestore)';
        }
      }
      
      // Prioridade 3: MQTT (se configurado)
      if (!conectou) {
        _mensagemConexao = 'Tentando conectar via MQTT...';
        notifyListeners();
        
        // Tenta conectar via MQTT (usa configurações padrão do MqttService)
        conectou = await _dispositivoService.iniciarMonitoramento(
          deviceIdMqtt: 'parada_dispositivo', // ID padrão, pode ser configurado depois
        );
        
        if (conectou) {
          dispositivoInfo = 'Dispositivo conectado (MQTT)';
        }
      }
      
      // Prioridade 4: HTTP direto (ESP8266 via WiFi)
      if (!conectou && _ipESP8266.isNotEmpty) {
        _mensagemConexao = 'Conectando via WiFi (ESP8266)...';
        notifyListeners();
        
        conectou = await _dispositivoService.iniciarMonitoramento(
          ipESP8266: _ipESP8266,
        );
        
        if (conectou) {
          dispositivoInfo = 'Dispositivo conectado (ESP8266: $_ipESP8266)';
        }
      }
      
      // Atualiza o estado baseado no resultado
      _conectado = conectou && _dispositivoService.conectado;
      
      if (_conectado) {
        _dispositivoEncontrado = dispositivoInfo;
        _mensagemConexao = 'Dispositivo da parada conectado com sucesso!';
      } else {
        _dispositivoEncontrado = null;
        _mensagemConexao = 'Nenhum dispositivo encontrado. Verifique as configurações.';
      }
      
      _conectando = false;
      notifyListeners();
    } catch (e) {
      _conectado = false;
      _conectando = false;
      _mensagemConexao = 'Erro ao conectar: ${e.toString()}';
      _dispositivoEncontrado = null;
      notifyListeners();
    }
  }
  
  /// Desconecta dispositivo
  Future<void> desconectarDispositivo() async {
    await _dispositivoService.pararMonitoramento();
    _conectado = false;
    _dispositivoEncontrado = null;
    _mensagemConexao = 'Procurando dispositivo...';
    notifyListeners();
  }
  
  /// Atualiza dark theme
  Future<void> setDarkTheme(bool valor) async {
    await _themeService.setDarkTheme(valor);
    _darkTheme = valor;
    notifyListeners();
  }

  /// Atualiza alto contraste
  Future<void> setAltoContraste(bool valor) async {
    await _themeService.setAltoContraste(valor);
    _altoContraste = valor;
    notifyListeners();
  }
  
  /// Atualiza tamanho da fonte
  Future<void> setTamanhoFonte(double valor) async {
    await _themeService.setTamanhoFonte(valor);
    _tamanhoFonte = valor;
    _tamanhoFonteEspecifico = _themeService.tamanhoFonteEspecifico;
    notifyListeners();
  }
  
  /// Atualiza leitor de tela
  Future<void> setLeitorTela(bool valor) async {
    await _themeService.setLeitorTela(valor);
    _leitorTela = valor;
    notifyListeners();
  }
  
  /// Atualiza vibração
  Future<void> setVibracao(bool valor) async {
    await _prefs.setVibracao(valor);
    _vibracao = valor;
    notifyListeners();
  }
  
  /// Atualiza som
  Future<void> setSom(bool valor) async {
    await _prefs.setSom(valor);
    _som = valor;
    notifyListeners();
  }
  
  /// Atualiza luz
  Future<void> setLuz(bool valor) async {
    await _prefs.setLuz(valor);
    _luz = valor;
    notifyListeners();
  }
}

