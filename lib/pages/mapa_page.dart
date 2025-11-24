import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../services/database_service.dart';
import '../models/linha_onibus_model.dart';
import '../models/ponto_parada_model.dart';
import '../services/directions_service.dart';
import '../services/theme_service.dart';

class MapaPage extends StatefulWidget {
  const MapaPage({super.key});

  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> {
  GoogleMapController? _mapController;
  final DatabaseService _dbService = DatabaseService();
  final DirectionsService _directionsService = DirectionsService();
  final ThemeService _themeService = ThemeService();
  List<PontoParada> _pontos = [];
  List<LinhaOnibus> _linhas = [];
  Position? _currentPosition;
  bool _isLoading = true;
  LinhaOnibus? _linhaSelecionada;
  PontoParada? _pontoSelecionado;
  Set<Polyline> _polylines = {};
  Set<Marker> _markers = {};
  bool _altoContraste = false;
  bool _isAnimating = false; // Flag para controlar animações simultâneas
  String? _mapError; // Erro ao carregar o mapa

  // Coordenadas padrão (centro da cidade fictícia)
  static const CameraPosition _kInitialPosition = CameraPosition(
    target: LatLng(-23.5505, -46.6333),
    zoom: 13.0,
  );

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoes();
    _themeService.addListener(_onThemeChanged);
    _loadData();
    if (_isPlatformSupported()) {
      _getCurrentLocation();
      // Verifica se o mapa carregou após 5 segundos
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _mapController == null && _mapError == null) {
          setState(() {
            final platform = Platform.isIOS
                ? 'iOS (Info.plist)'
                : Platform.isAndroid
                ? 'Android (local.properties)'
                : 'plataforma';
            _mapError =
                'O mapa não carregou. Verifique se a Google Maps API Key está configurada corretamente para $platform';
          });
        }
      });
    }
  }

  Future<void> _carregarConfiguracoes() async {
    await _themeService.carregarConfiguracoes();
    setState(() {
      _altoContraste = _themeService.altoContraste;
    });
  }

  void _onThemeChanged() {
    setState(() {
      _altoContraste = _themeService.altoContraste;
    });
  }

  /// Verifica se a plataforma suporta Google Maps
  bool _isPlatformSupported() {
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;
    return true;
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final pontos = await _dbService.getAllPontos();
      final linhas = await _dbService.getAllLinhas();
      setState(() {
        _pontos = pontos;
        _linhas = linhas;
        _isLoading = false;
      });
      _updateMarkers();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao carregar dados: $e')));
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
      });

      // Anima a câmera de forma segura, evitando múltiplas animações simultâneas
      _safeAnimateCamera(
        CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
      );

      _updateMarkers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao obter localização: $e')),
        );
      }
    }
  }

  void _updateMarkers() {
    Set<Marker> markers = {};

    // Marcar localização atual
    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('current_location'),
          position: LatLng(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Sua Localização'),
        ),
      );
    }

    // Marcar pontos de parada
    for (var ponto in _pontos) {
      final isSelected = _pontoSelecionado?.id == ponto.id;
      markers.add(
        Marker(
          markerId: MarkerId('ponto_${ponto.id}'),
          position: LatLng(ponto.latitude, ponto.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            isSelected ? BitmapDescriptor.hueRed : BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: ponto.nome,
            snippet: ponto.descricao ?? 'Ponto de parada',
          ),
          onTap: () {
            _selecionarPonto(ponto);
          },
        ),
      );
    }

    setState(() {
      _markers = markers;
    });
  }

  Future<void> _mostrarRotaLinha(LinhaOnibus linha) async {
    setState(() {
      _linhaSelecionada = linha;
      _polylines.clear();
    });

    // Buscar pontos de parada relacionados à linha (simulado)
    // Em produção, você buscaria da tabela linha_ponto
    List<PontoParada> pontosLinha = _pontos.where((ponto) {
      // Lógica simplificada: usar os primeiros pontos como exemplo
      return ponto.nome.toLowerCase().contains(linha.origem.toLowerCase()) ||
          ponto.nome.toLowerCase().contains(linha.destino.toLowerCase());
    }).toList();

    if (pontosLinha.isEmpty) {
      // Usar pontos fictícios baseados na origem e destino
      pontosLinha = _pontos.take(2).toList();
    }

    if (pontosLinha.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há pontos suficientes para traçar a rota'),
        ),
      );
      return;
    }

    // Mostrar loading
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buscando rota...'),
          duration: Duration(seconds: 1),
        ),
      );
    }

    // Buscar rota entre origem e destino
    final origin = LatLng(
      pontosLinha.first.latitude,
      pontosLinha.first.longitude,
    );
    final destination = LatLng(
      pontosLinha.last.latitude,
      pontosLinha.last.longitude,
    );

    // Se houver pontos intermediários
    List<LatLng>? waypoints;
    if (pontosLinha.length > 2) {
      waypoints = pontosLinha
          .sublist(1, pontosLinha.length - 1)
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();
    }

    final result = await _directionsService.getRoute(
      origin: origin,
      destination: destination,
      waypoints: waypoints,
      travelMode: 'transit', // Modo transporte público
    );

    if (result != null && result.points.isNotEmpty) {
      setState(() {
        _polylines = {
          Polyline(
            polylineId: PolylineId('rota_${linha.numero}'),
            points: result.points,
            color: Colors.blue,
            width: 5,
            patterns: [],
          ),
        };
      });

      // Ajustar câmera para mostrar toda a rota
      if (result.bounds != null) {
        _safeAnimateCamera(CameraUpdate.newLatLngBounds(result.bounds!, 100));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rota da Linha ${linha.numero} exibida'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível traçar a rota'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _limparRota() {
    setState(() {
      _linhaSelecionada = null;
      _polylines.clear();
    });
    _updateMarkers();
  }

  void _selecionarPonto(PontoParada ponto) {
    setState(() {
      _pontoSelecionado = ponto;
    });
    _updateMarkers();

    // Centraliza o mapa no ponto selecionado
    _safeAnimateCamera(
      CameraUpdate.newLatLng(LatLng(ponto.latitude, ponto.longitude)),
    );

    // Mostra mensagem informativa
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Parada selecionada: ${ponto.nome}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
          action: SnackBarAction(
            label: 'Limpar',
            textColor: Colors.white,
            onPressed: () {
              setState(() {
                _pontoSelecionado = null;
              });
              _updateMarkers();
            },
          ),
        ),
      );
    }
  }

  void _limparPontoSelecionado() {
    setState(() {
      _pontoSelecionado = null;
    });
    _updateMarkers();
  }

  /// Anima a câmera de forma segura, evitando múltiplas animações simultâneas
  /// que podem causar problemas com buffers de imagem no Android
  Future<void> _safeAnimateCamera(CameraUpdate update) async {
    if (_mapController == null || _isAnimating || !mounted) return;

    try {
      _isAnimating = true;
      await _mapController!.animateCamera(update);
    } catch (e) {
      // Ignora erros de animação se o widget foi desmontado
      if (mounted) {
        debugPrint('Erro ao animar câmera: $e');
      }
    } finally {
      // Aguarda um delay maior antes de permitir nova animação (aumentado para 800ms)
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _isAnimating = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _altoContraste
          ? Colors.black
          : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? Theme.of(context).colorScheme.surface
            : Colors.green,
        title: Semantics(
          header: true,
          child: const Text(
            'Mapa de Linhas de Ônibus',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        actions: [],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _mapError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Erro ao carregar o mapa',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _mapError!,
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _mapError = null;
                          _isLoading = true;
                        });
                        _loadData();
                      },
                      child: const Text('Tentar novamente'),
                    ),
                  ],
                ),
              ),
            )
          : _isPlatformSupported()
          ? Stack(
              children: [
                GoogleMap(
                  mapType: MapType.normal,
                  initialCameraPosition: _kInitialPosition,
                  markers: _markers,
                  polylines: _polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: true,
                  zoomGesturesEnabled: true,
                  scrollGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  rotateGesturesEnabled: true,
                  onMapCreated: (GoogleMapController controller) {
                    print('Mapa: GoogleMap criado com sucesso');
                    _mapController = controller;
                    _updateMarkers();
                  },
                  onCameraMoveStarted: () {
                    debugPrint('Mapa: Câmera começou a se mover');
                  },
                  onCameraIdle: () {
                    debugPrint('Mapa: Câmera parou');
                  },
                  onTap: (LatLng position) {
                    debugPrint(
                      'Mapa: Tocado em ${position.latitude}, ${position.longitude}',
                    );
                  },
                ),
                // Painel de seleção de linha
                Positioned(
                  top: 10,
                  left: 10,
                  right: 10,
                  child: Card(
                    elevation: 4,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.directions_bus,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Selecione uma linha:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              if (_linhaSelecionada != null)
                                IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  onPressed: _limparRota,
                                  tooltip: 'Limpar rota',
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 40,
                            child: ListView.builder(
                              scrollDirection: Axis.horizontal,
                              itemCount: _linhas.length,
                              itemBuilder: (context, index) {
                                final linha = _linhas[index];
                                final isSelected =
                                    _linhaSelecionada?.numero == linha.numero;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isSelected
                                          ? Colors.blue
                                          : Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    onPressed: () {
                                      _mostrarRotaLinha(linha);
                                      // Mostra opção para ver mais detalhes
                                      if (mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Rota da Linha ${linha.numero} exibida',
                                            ),
                                            backgroundColor: Colors.green,
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                            action: SnackBarAction(
                                              label: 'Ver Detalhes',
                                              textColor: Colors.white,
                                              onPressed: () {
                                                Navigator.pushNamed(
                                                  context,
                                                  '/informacoesOnibus',
                                                  arguments: {'linha': linha},
                                                );
                                              },
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                    child: Text(
                                      'Linha ${linha.numero}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_linhaSelecionada != null) ...[
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () {
                                // Navega para informações do ônibus
                                Navigator.pushNamed(
                                  context,
                                  '/informacoesOnibus',
                                  arguments: {'linha': _linhaSelecionada!},
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.blue,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.info_outline,
                                      size: 16,
                                      color: Colors.blue,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${_linhaSelecionada!.origem} → ${_linhaSelecionada!.destino}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    const Icon(
                                      Icons.arrow_forward_ios,
                                      size: 14,
                                      color: Colors.blue,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (_pontoSelecionado != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.red, width: 1),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.place,
                                    size: 16,
                                    color: Colors.red,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _pontoSelecionado!.nome,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (_pontoSelecionado!.descricao !=
                                            null)
                                          Text(
                                            _pontoSelecionado!.descricao!,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 16),
                                    color: Colors.red,
                                    onPressed: _limparPontoSelecionado,
                                    tooltip: 'Limpar parada selecionada',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : _buildUnsupportedPlatformView(),
      floatingActionButton: FloatingActionButton(
        onPressed: _getCurrentLocation,
        backgroundColor: Colors.green,
        child: const Icon(Icons.my_location, color: Colors.white),
      ),
    );
  }

  /// Widget para plataformas não suportadas (Windows, Linux, Web)
  Widget _buildUnsupportedPlatformView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mensagem de aviso
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mapa não disponível nesta plataforma',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'O Google Maps está disponível apenas em Android e iOS. Use um dispositivo móvel ou emulador para visualizar o mapa.',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Lista de linhas de ônibus
          const Text(
            'Linhas de Ônibus Disponíveis',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 16),
          ..._linhas.map((linha) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Text(
                    linha.numero,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  'Linha ${linha.numero} - ${linha.nome}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${linha.origem} → ${linha.destino}',
                  style: const TextStyle(fontSize: 14),
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () {
                  // Navega para a tela de informações do ônibus
                  Navigator.pushNamed(
                    context,
                    '/informacoesOnibus',
                    arguments: {'linha': linha},
                  );
                },
              ),
            );
          }),
          const SizedBox(height: 24),
          // Lista de pontos de parada
          const Text(
            'Pontos de Parada',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 16),
          ..._pontos.map((ponto) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.location_on, color: Colors.green),
                title: Text(
                  ponto.nome,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Lat: ${ponto.latitude.toStringAsFixed(4)}, Lng: ${ponto.longitude.toStringAsFixed(4)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                trailing: ponto.descricao != null
                    ? Text(
                        ponto.descricao!,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        textAlign: TextAlign.right,
                      )
                    : null,
                onTap: () {
                  // Seleciona o ponto e centraliza no mapa (se estiver na versão com mapa)
                  _selecionarPonto(ponto);
                  // Se estiver na versão sem mapa, mostra informações
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Ponto selecionado: ${ponto.nome}${ponto.descricao != null ? '\n${ponto.descricao}' : ''}',
                      ),
                      backgroundColor: Colors.green,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _themeService.removeListener(_onThemeChanged);
    // Cancela qualquer animação em andamento
    _isAnimating = false;
    // Limpa o controller do mapa de forma segura
    _mapController?.dispose();
    _mapController = null;
    super.dispose();
  }
}
