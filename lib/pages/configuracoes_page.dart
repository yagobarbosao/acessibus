import 'package:flutter/material.dart';
import '../controllers/config_controller.dart';
import '../services/theme_service.dart';

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage> {
  final ConfigController _configController = ConfigController();
  final ThemeService _themeService = ThemeService();
  final _deviceIdController = TextEditingController();
  final _ipESP8266Controller = TextEditingController();
  final _idOnibusRealtimeController = TextEditingController();
  bool _altoContraste = false;
  bool _darkTheme = false;

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
    _themeService.addListener(_onThemeChanged);
    _configController.addListener(_onConfigChanged);
  }

  void _onThemeChanged() {
    setState(() {
      _altoContraste = _themeService.altoContraste;
      _darkTheme = _themeService.darkTheme;
    });
  }

  void _onConfigChanged() {
    if (mounted) {
      setState(() {
        _deviceIdController.text = _configController.deviceId ?? '';
        _ipESP8266Controller.text = _configController.ipESP8266 ?? '';
        _idOnibusRealtimeController.text = _configController.idOnibusRealtime ?? '';
      });
    }
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    _configController.removeListener(_onConfigChanged);
    _deviceIdController.dispose();
    _ipESP8266Controller.dispose();
    _idOnibusRealtimeController.dispose();
    super.dispose();
  }

  Future<void> _carregarConfiguracoes() async {
    await _configController.carregarConfiguracoes();
    await _themeService.carregarConfiguracoes();
    setState(() {
      _altoContraste = _themeService.altoContraste;
      _darkTheme = _themeService.darkTheme;
    });
  }

  Future<void> _conectarDispositivo() async {
    await _configController.conectarDispositivo();
    if (mounted) {
      setState(() {});
    }
  }


  Future<void> _desconectarDispositivo() async {
    await _configController.desconectarDispositivo();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dispositivo desconectado'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // Função auxiliar para determinar a cor do texto baseada no tema
  Color _getTextColor({bool isSubtitle = false}) {
    if (_altoContraste) {
      return isSubtitle ? Colors.grey[300]! : Colors.white;
    }
    if (_darkTheme) {
      return isSubtitle ? Colors.grey[300]! : Colors.white;
    }
    return isSubtitle ? Colors.grey[600]! : Colors.black87;
  }

  @override
  Widget build(BuildContext context) {
    // Garante que o controller está carregado antes de renderizar
    if (_configController.isLoading) {
      return Scaffold(
        backgroundColor: _altoContraste ? Colors.black : const Color(0xFFF5F5DC),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: _altoContraste
          ? Colors.black
          : theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: _altoContraste ? Colors.grey[900] : (theme.brightness == Brightness.dark ? theme.colorScheme.surface : Colors.green),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Voltar',
        ),
        title: Semantics(
          header: true,
          child: const Text(
            "Configurações",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      body: _configController.isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Seção de Acessibilidade
                  Semantics(
                    header: true,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _altoContraste
                            ? Colors.grey[900]
                            : (_darkTheme ? theme.cardColor : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _altoContraste
                              ? Colors.white
                              : Colors.green,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.accessibility_new,
                                color: _altoContraste
                                    ? Colors.white
                                    : Colors.green,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Acessibilidade',
                                      style: TextStyle(
                                        fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                        fontWeight: FontWeight.bold,
                                        color: _altoContraste
                                            ? Colors.white
                                            : Colors.green,
                                      ),
                                    ),
                                    Text(
                                      'Personalize a interface para melhor uso',
                                      style: TextStyle(
                                        fontSize: ((_configController.tamanhoFonteEspecifico ?? 18) - 3).toDouble(),
                                        color: _altoContraste
                                            ? Colors.grey[300]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          // Alto Contraste
                          Semantics(
                            label: 'Ativar ou desativar modo alto contraste',
                            child: SwitchListTile(
                              title:                                     Text(
                                      'Alto Contraste',
                                      style: TextStyle(
                                        fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                        color: _getTextColor(),
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Aumenta o contraste das cores',
                                      style: TextStyle(
                                        fontSize: ((_configController.tamanhoFonteEspecifico ?? 18) - 2)
                                            .toDouble(),
                                        color: _getTextColor(isSubtitle: true),
                                      ),
                                    ),
                              value: _configController.altoContraste,
                              activeThumbColor: Colors.green,
                              onChanged: (valor) => _configController.setAltoContraste(valor),
                            ),
                          ),
                          const Divider(),
                          // Dark Theme
                          Semantics(
                            label: 'Ativar ou desativar tema escuro',
                            child: SwitchListTile(
                              title:                                     Text(
                                      'Tema Escuro',
                                      style: TextStyle(
                                        fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                        color: _getTextColor(),
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Ativa o modo escuro do aplicativo',
                                      style: TextStyle(
                                        fontSize: ((_configController.tamanhoFonteEspecifico ?? 18) - 2)
                                            .toDouble(),
                                        color: _getTextColor(isSubtitle: true),
                                      ),
                                    ),
                              value: _configController.darkTheme,
                              activeThumbColor: Colors.green,
                              onChanged: (valor) => _configController.setDarkTheme(valor),
                            ),
                          ),
                          const Divider(),
                          // Leitor de Tela
                          Semantics(
                            label: 'Ativar ou desativar leitor de tela',
                            child: SwitchListTile(
                              title:                                     Text(
                                      'Leitor de Tela',
                                      style: TextStyle(
                                        fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                        color: _getTextColor(),
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Ativa suporte para leitores de tela',
                                      style: TextStyle(
                                        fontSize: ((_configController.tamanhoFonteEspecifico ?? 18) - 2)
                                            .toDouble(),
                                        color: _getTextColor(isSubtitle: true),
                                      ),
                                    ),
                              value: _configController.leitorTela,
                              activeThumbColor: Colors.green,
                              onChanged: (valor) => _configController.setLeitorTela(valor),
                            ),
                          ),
                          const Divider(),
                          // Tamanho da Fonte
                          Semantics(
                            label: 'Ajustar tamanho da fonte',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  child:                                     Text(
                                      'Tamanho da Fonte: ${_configController.tamanhoFonteEspecifico ?? 18}px',
                                      style: TextStyle(
                                        fontSize:
                                            (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                        fontWeight: FontWeight.bold,
                                        color: _getTextColor(),
                                      ),
                                    ),
                                ),
                                Slider(
                                  value: _configController.tamanhoFonte,
                                  min: 0.8,
                                  max: 2.0,
                                  divisions: 12,
                                  activeColor: Colors.green,
                                  label: '${(_configController.tamanhoFonte * 18).round()}px',
                                  onChanged: (value) {
                                    _configController.setTamanhoFonte(value);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Seção de Alertas Multimodais
                  Semantics(
                    header: true,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _altoContraste
                            ? Colors.grey[900]
                            : (_darkTheme ? theme.cardColor : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _altoContraste
                              ? Colors.white
                              : Colors.blue,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.notifications_active,
                                color: _altoContraste
                                    ? Colors.white
                                    : Colors.blue,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Alertas de Chegada do Ônibus',
                                      style: TextStyle(
                                        fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                        fontWeight: FontWeight.bold,
                                        color: _altoContraste
                                            ? Colors.white
                                            : Colors.blue,
                                      ),
                                    ),
                                    Text(
                                      'Configure notificações multimodais',
                                      style: TextStyle(
                                        fontSize: ((_configController.tamanhoFonteEspecifico ?? 18) - 3).toDouble(),
                                        color: _altoContraste
                                            ? Colors.grey[300]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Descrição explicativa
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: Text(
                              'Configure como deseja ser notificado quando o ônibus selecionado estiver se aproximando da parada. Você pode ativar um ou mais tipos de alerta conforme sua preferência ou necessidade.',
                              style: TextStyle(
                                fontSize: ((_configController.tamanhoFonteEspecifico ?? 18) - 2).toDouble(),
                                color: _getTextColor(isSubtitle: true),
                              ),
                              textAlign: TextAlign.justify,
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Vibração
                          Semantics(
                            label: 'Ativar ou desativar alertas por vibração quando o ônibus se aproximar',
                            child: SwitchListTile(
                              title:                                     Text(
                                      'Vibração',
                                      style: TextStyle(
                                        fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                        color: _getTextColor(),
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Vibrar o dispositivo quando o ônibus estiver se aproximando',
                                      style: TextStyle(
                                        fontSize: ((_configController.tamanhoFonteEspecifico ?? 18) - 2)
                                            .toDouble(),
                                        color: _getTextColor(isSubtitle: true),
                                      ),
                                    ),
                              value: _configController.vibracao,
                              activeThumbColor: Colors.green,
                              onChanged: (valor) => _configController.setVibracao(valor),
                            ),
                          ),
                          const Divider(),
                          // Som
                          Semantics(
                            label: 'Ativar ou desativar alertas sonoros quando o ônibus se aproximar',
                            child: SwitchListTile(
                              title:                                     Text(
                                      'Som',
                                      style: TextStyle(
                                        fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                        color: _getTextColor(),
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Emitir som quando o ônibus estiver se aproximando',
                                      style: TextStyle(
                                        fontSize: ((_configController.tamanhoFonteEspecifico ?? 18) - 2)
                                            .toDouble(),
                                        color: _getTextColor(isSubtitle: true),
                                      ),
                                    ),
                              value: _configController.som,
                              activeThumbColor: Colors.green,
                              onChanged: (valor) => _configController.setSom(valor),
                            ),
                          ),
                          const Divider(),
                          // Luz
                          Semantics(
                            label: 'Ativar ou desativar alertas luminosos quando o ônibus se aproximar',
                            child: SwitchListTile(
                              title:                                     Text(
                                      'Sinais Luminosos',
                                      style: TextStyle(
                                        fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                        color: _getTextColor(),
                                      ),
                                    ),
                                    subtitle: Text(
                                      'Acender luzes no dispositivo quando o ônibus estiver se aproximando',
                                      style: TextStyle(
                                        fontSize: ((_configController.tamanhoFonteEspecifico ?? 18) - 2)
                                            .toDouble(),
                                        color: _getTextColor(isSubtitle: true),
                                      ),
                                    ),
                              value: _configController.luz,
                              activeThumbColor: Colors.green,
                              onChanged: (valor) => _configController.setLuz(valor),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Seção de Conexão com Dispositivo
                  Semantics(
                    header: true,
                    child: GestureDetector(
                      onTap: () {
                        // Quando o card é clicado, executa a ação de conectar/desconectar
                        if (!_configController.conectando) {
                          if (_configController.conectado) {
                            _desconectarDispositivo();
                          } else {
                            _conectarDispositivo();
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _altoContraste
                              ? Colors.grey[900]
                              : (_darkTheme ? theme.cardColor : Colors.white),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _altoContraste
                                ? Colors.white
                                : Colors.orange,
                            width: 2,
                          ),
                        ),
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.devices,
                                color: _altoContraste
                                    ? Colors.white
                                    : Colors.orange,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Conexão com Dispositivo',
                                      style: TextStyle(
                                        fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                        fontWeight: FontWeight.bold,
                                        color: _altoContraste
                                            ? Colors.white
                                            : Colors.orange,
                                      ),
                                    ),
                                    Text(
                                      'Configure a conexão com o dispositivo físico',
                                      style: TextStyle(
                                        fontSize: ((_configController.tamanhoFonteEspecifico ?? 18) - 3).toDouble(),
                                        color: _altoContraste
                                            ? Colors.grey[300]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          // Status da conexão - Centralizado
                          Semantics(
                            label: _configController.conectado
                                ? 'Status: Dispositivo conectado com sucesso'
                                : 'Status: Dispositivo não conectado. Pressione o botão abaixo para conectar.',
                            child: Container(
                              padding: EdgeInsets.all((_configController.tamanhoFonteEspecifico ?? 18) * 1.0),
                              decoration: BoxDecoration(
                                color: _configController.conectado
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: _configController.conectado ? Colors.green : Colors.grey,
                                  width: _altoContraste ? 3 : 2,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _configController.conectado ? Icons.check_circle : Icons.info_outline,
                                    color: _configController.conectado ? Colors.green : Colors.grey,
                                    size: (_configController.tamanhoFonteEspecifico ?? 18) * 1.5,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _configController.conectado
                                        ? 'Dispositivo Conectado'
                                        : 'Dispositivo Não Conectado',
                                    style: TextStyle(
                                      fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                      fontWeight: FontWeight.bold,
                                      color: _configController.conectado 
                                          ? Colors.green 
                                          : _getTextColor(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 48),
                          // Mensagem de status ou dispositivo encontrado
                          if (_configController.conectando)
                            Semantics(
                              label: 'Procurando dispositivo. Aguarde...',
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Column(
                                    children: [
                                      const SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            Colors.green,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        _configController.mensagemConexao,
                                        style: TextStyle(
                                          fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                          fontWeight: FontWeight.w500,
                                          color: _getTextColor(),
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            )
                          else if (_configController.conectado && _configController.dispositivoEncontrado != null)
                            Semantics(
                              label: 'Dispositivo encontrado: ${_configController.dispositivoEncontrado}',
                              child: Container(
                                padding: EdgeInsets.all((_configController.tamanhoFonteEspecifico ?? 18) * 0.8),
                                margin: const EdgeInsets.symmetric(horizontal: 24),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.green,
                                    width: _altoContraste ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                      size: (_configController.tamanhoFonteEspecifico ?? 18) * 1.2,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _configController.dispositivoEncontrado!,
                                        style: TextStyle(
                                          fontSize: ((_configController.tamanhoFonteEspecifico ?? 18) - 1).toDouble(),
                                          color: _getTextColor(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            Semantics(
                              header: true,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Text(
                                    'Conecte o dispositivo para receber alertas quando o ônibus se aproximar',
                                    style: TextStyle(
                                      fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                      color: _getTextColor(),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(height: 48),
                          // Botão principal único - Grande e claro
                          Semantics(
                            label: _configController.conectado
                                ? 'Botão para desconectar do dispositivo. Pressione para desconectar.'
                                : 'Botão para conectar ao dispositivo. Pressione para iniciar a conexão.',
                            hint: _configController.conectado
                                ? 'Desconecta o dispositivo e para de receber alertas'
                                : 'Conecta ao dispositivo na parada de ônibus para receber alertas',
                            button: true,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _configController.conectando
                                      ? null
                                      : (_configController.conectado
                                          ? _desconectarDispositivo
                                          : _conectarDispositivo),
                                  icon: _configController.conectando
                                      ? SizedBox(
                                          width: (_configController.tamanhoFonteEspecifico ?? 18) * 1.0,
                                          height: (_configController.tamanhoFonteEspecifico ?? 18) * 1.0,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 3,
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                          ),
                                        )
                                      : Icon(
                                          _configController.conectado ? Icons.link_off : Icons.link,
                                          size: (_configController.tamanhoFonteEspecifico ?? 18) * 1.4,
                                        ),
                                  label: Text(
                                    _configController.conectando
                                        ? _configController.mensagemConexao
                                        : (_configController.conectado ? 'Desconectar' : 'Conectar Dispositivo'),
                                    style: TextStyle(
                                      fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _configController.conectado
                                        ? Colors.red
                                        : Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: (_configController.tamanhoFonteEspecifico ?? 18) * 1.5,
                                      vertical: (_configController.tamanhoFonteEspecifico ?? 18) * 1.2,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    elevation: _altoContraste ? 0 : 4,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Botão de Perfil
                  Semantics(
                    label: 'Botão para abrir tela de perfil',
                    button: true,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _altoContraste
                            ? Colors.grey[900]
                            : (_darkTheme ? theme.cardColor : Colors.white),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _altoContraste
                              ? Colors.white
                              : Colors.green,
                          width: 2,
                        ),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.person,
                          color: _altoContraste
                              ? Colors.white
                              : Colors.green,
                          size: 28,
                        ),
                        title: Text(
                          'Meu Perfil',
                          style: TextStyle(
                            fontSize: (_configController.tamanhoFonteEspecifico ?? 18).toDouble(),
                            fontWeight: FontWeight.bold,
                            color: _getTextColor(),
                          ),
                        ),
                        subtitle: Text(
                          'Alterar dados pessoais',
                          style: TextStyle(
                            fontSize: ((_configController.tamanhoFonteEspecifico ?? 18) - 2).toDouble(),
                            color: _getTextColor(isSubtitle: true),
                          ),
                        ),
                        trailing: Icon(
                          Icons.arrow_forward_ios,
                          color: _darkTheme || _altoContraste
                              ? Colors.white
                              : Colors.grey,
                        ),
                        onTap: () {
                          try {
                            Navigator.pushNamed(context, '/perfil');
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Erro ao abrir perfil: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

