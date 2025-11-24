import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/linha_onibus_model.dart';
import '../models/ponto_parada_model.dart';

/// Serviço de Banco de Dados
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  static Database? _database;

  Future<Database?> get database async {
    // SQLite não funciona na web, retornar null
    if (kIsWeb) return null;

    if (_database != null) return _database!;
    try {
      _database = await _initDatabase();
      return _database!;
    } catch (e) {
      // Se falhar na inicialização, retornar null
      // Os métodos que usam database já têm try/catch para usar fallback
      print('Erro ao inicializar banco de dados: $e');
      return null;
    }
  }

  Future<Database> _initDatabase() async {
    try {
      String path = join(await getDatabasesPath(), 'acessibus.db');
      return await openDatabase(
        path,
        version: 2, // Incrementado para forçar atualização
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      // Se falhar (ex: web), retorna null e usar dados estáticos
      print('Erro ao inicializar banco de dados: $e');
      rethrow;
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    // Tabela de linhas de ônibus
    await db.execute('''
      CREATE TABLE linhas_onibus (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        numero TEXT NOT NULL UNIQUE,
        nome TEXT NOT NULL,
        origem TEXT NOT NULL,
        destino TEXT NOT NULL,
        descricao TEXT
      )
    ''');

    // Tabela de pontos de parada
    await db.execute('''
      CREATE TABLE pontos_parada (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome TEXT NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        descricao TEXT
      )
    ''');

    // Tabela de relação entre linhas e pontos (rota)
    await db.execute('''
      CREATE TABLE linha_ponto (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        linha_id INTEGER NOT NULL,
        ponto_id INTEGER NOT NULL,
        ordem INTEGER NOT NULL,
        FOREIGN KEY (linha_id) REFERENCES linhas_onibus(id),
        FOREIGN KEY (ponto_id) REFERENCES pontos_parada(id)
      )
    ''');

    // Inserir dados de teste
    await _insertDadosTeste(db);
  }

  /// Atualiza o banco de dados quando a versão muda
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('Atualizando banco de dados da versão $oldVersion para $newVersion');

    if (oldVersion < 2) {
      // Versão 2: Atualiza as linhas de teste
      // Limpa as linhas antigas e insere as novas
      await db.delete('linhas_onibus');
      await _insertDadosTeste(db);
      print('✅ Dados de teste atualizados com sucesso!');
    }
  }

  Future<void> _insertDadosTeste(Database db) async {
    // Inserir linhas de ônibus (configuração real do ESP8266)
    final linhas = [
      // Linhas reais configuradas no ESP8266
      LinhaOnibus(
        numero: '132A',
        nome: 'Centro - Terminal',
        origem: 'Centro',
        destino: 'Terminal Rodoviário',
        descricao: 'Linha configurada no ESP8266 - Botão Visual (GPIO 14)',
      ),
      LinhaOnibus(
        numero: '251B',
        nome: 'Universidade - Shopping',
        origem: 'Universidade',
        destino: 'Shopping Center',
        descricao: 'Linha configurada no ESP8266 - Botão Auditivo (GPIO 14)',
      ),
      // Outras linhas para demonstração
      LinhaOnibus(
        numero: '301',
        nome: 'Bairro Novo - Centro',
        origem: 'Bairro Novo',
        destino: 'Centro',
        descricao: 'Linha de conexão do novo bairro ao centro',
      ),
      LinhaOnibus(
        numero: '401',
        nome: 'Hospital - Centro',
        origem: 'Hospital Regional',
        destino: 'Centro',
        descricao: 'Linha de acesso ao hospital',
      ),
      LinhaOnibus(
        numero: '501',
        nome: 'Aeroporto - Centro',
        origem: 'Aeroporto',
        destino: 'Centro',
        descricao: 'Linha de conexão do aeroporto ao centro',
      ),
    ];

    for (var linha in linhas) {
      await db.insert('linhas_onibus', linha.toMap());
    }

    // Inserir pontos de parada (coordenadas de exemplo - devem ser atualizadas com dados reais)
    final pontos = [
      PontoParada(
        nome: 'Terminal Central',
        latitude: -23.5505,
        longitude: -46.6333,
        descricao: 'Terminal principal de ônibus',
      ),
      PontoParada(
        nome: 'Praça da República',
        latitude: -23.5431,
        longitude: -46.6428,
        descricao: 'Parada em frente à praça',
      ),
      PontoParada(
        nome: 'Shopping Center',
        latitude: -23.5489,
        longitude: -46.6388,
        descricao: 'Parada no shopping',
      ),
      PontoParada(
        nome: 'Universidade',
        latitude: -23.5525,
        longitude: -46.6338,
        descricao: 'Parada na entrada da universidade',
      ),
      PontoParada(
        nome: 'Hospital Regional',
        latitude: -23.5475,
        longitude: -46.6415,
        descricao: 'Parada em frente ao hospital',
      ),
      PontoParada(
        nome: 'Aeroporto',
        latitude: -23.4325,
        longitude: -46.4691,
        descricao: 'Terminal de ônibus do aeroporto',
      ),
      PontoParada(
        nome: 'Bairro Novo',
        latitude: -23.5550,
        longitude: -46.6400,
        descricao: 'Parada principal do bairro',
      ),
    ];

    for (var ponto in pontos) {
      await db.insert('pontos_parada', ponto.toMap());
    }
  }

  // Métodos para Linhas de Ônibus
  Future<List<LinhaOnibus>> getAllLinhas() async {
    // Se web, retornar dados estáticos diretamente
    if (kIsWeb) {
      return _getLinhasTeste();
    }

    try {
      final db = await database;
      if (db == null) {
        return _getLinhasTeste();
      }
      final List<Map<String, dynamic>> maps = await db.query('linhas_onibus');
      if (maps.isEmpty) {
        // Se banco vazio, retornar dados de teste
        return _getLinhasTeste();
      }
      return List.generate(maps.length, (i) => LinhaOnibus.fromMap(maps[i]));
    } catch (e) {
      // Se falhar, retornar dados estáticos
      print('Erro ao buscar linhas do banco: $e');
      return _getLinhasTeste();
    }
  }

  /// Retorna dados estáticos (fallback para web)
  List<LinhaOnibus> _getLinhasTeste() {
    return [
      // Linhas reais configuradas no ESP8266
      LinhaOnibus(
        id: 1,
        numero: '132A',
        nome: 'Centro - Terminal',
        origem: 'Centro',
        destino: 'Terminal Rodoviário',
        descricao: 'Linha configurada no ESP8266 - Botão Visual (GPIO 14)',
      ),
      LinhaOnibus(
        id: 2,
        numero: '251B',
        nome: 'Universidade - Shopping',
        origem: 'Universidade',
        destino: 'Shopping Center',
        descricao: 'Linha configurada no ESP8266 - Botão Auditivo (GPIO 14)',
      ),
      // Outras linhas para demonstração
      LinhaOnibus(
        id: 3,
        numero: '301',
        nome: 'Bairro Novo - Centro',
        origem: 'Bairro Novo',
        destino: 'Centro',
        descricao: 'Linha de conexão do novo bairro ao centro',
      ),
      LinhaOnibus(
        id: 4,
        numero: '401',
        nome: 'Hospital - Centro',
        origem: 'Hospital Regional',
        destino: 'Centro',
        descricao: 'Linha de acesso ao hospital',
      ),
      LinhaOnibus(
        id: 5,
        numero: '501',
        nome: 'Aeroporto - Centro',
        origem: 'Aeroporto',
        destino: 'Centro',
        descricao: 'Linha de conexão do aeroporto ao centro',
      ),
    ];
  }

  Future<LinhaOnibus?> getLinhaByNumero(String numero) async {
    // Se web, buscar nos dados estáticos
    if (kIsWeb) {
      final linhasTeste = _getLinhasTeste();
      try {
        return linhasTeste.firstWhere((linha) => linha.numero == numero);
      } catch (_) {
        return null;
      }
    }

    try {
      final db = await database;
      if (db == null) {
        final linhasTeste = _getLinhasTeste();
        try {
          return linhasTeste.firstWhere((linha) => linha.numero == numero);
        } catch (_) {
          return null;
        }
      }
      final List<Map<String, dynamic>> maps = await db.query(
        'linhas_onibus',
        where: 'numero = ?',
        whereArgs: [numero],
      );
      if (maps.isEmpty) {
        // Buscar nos dados de teste
        final linhasTeste = _getLinhasTeste();
        try {
          return linhasTeste.firstWhere((linha) => linha.numero == numero);
        } catch (_) {
          return null;
        }
      }
      return LinhaOnibus.fromMap(maps.first);
    } catch (e) {
      // Se falhar, buscar nos dados de teste
      final linhasTeste = _getLinhasTeste();
      try {
        return linhasTeste.firstWhere((linha) => linha.numero == numero);
      } catch (_) {
        return null;
      }
    }
  }

  Future<List<LinhaOnibus>> buscarLinhas(String query) async {
    // Se web, buscar nos dados estáticos
    if (kIsWeb) {
      final linhasTeste = _getLinhasTeste();
      final queryLower = query.toLowerCase();
      return linhasTeste.where((linha) {
        return linha.numero.toLowerCase().contains(queryLower) ||
            linha.nome.toLowerCase().contains(queryLower) ||
            linha.origem.toLowerCase().contains(queryLower) ||
            linha.destino.toLowerCase().contains(queryLower);
      }).toList();
    }

    try {
      final db = await database;
      if (db == null) {
        final linhasTeste = _getLinhasTeste();
        final queryLower = query.toLowerCase();
        return linhasTeste.where((linha) {
          return linha.numero.toLowerCase().contains(queryLower) ||
              linha.nome.toLowerCase().contains(queryLower) ||
              linha.origem.toLowerCase().contains(queryLower) ||
              linha.destino.toLowerCase().contains(queryLower);
        }).toList();
      }
      final List<Map<String, dynamic>> maps = await db.query(
        'linhas_onibus',
        where:
            'numero LIKE ? OR nome LIKE ? OR origem LIKE ? OR destino LIKE ?',
        whereArgs: ['%$query%', '%$query%', '%$query%', '%$query%'],
      );
      if (maps.isEmpty) {
        // Buscar nos dados de teste
        final linhasTeste = _getLinhasTeste();
        final queryLower = query.toLowerCase();
        return linhasTeste.where((linha) {
          return linha.numero.toLowerCase().contains(queryLower) ||
              linha.nome.toLowerCase().contains(queryLower) ||
              linha.origem.toLowerCase().contains(queryLower) ||
              linha.destino.toLowerCase().contains(queryLower);
        }).toList();
      }
      return List.generate(maps.length, (i) => LinhaOnibus.fromMap(maps[i]));
    } catch (e) {
      // Se falhar, buscar nos dados de teste
      final linhasTeste = _getLinhasTeste();
      final queryLower = query.toLowerCase();
      return linhasTeste.where((linha) {
        return linha.numero.toLowerCase().contains(queryLower) ||
            linha.nome.toLowerCase().contains(queryLower) ||
            linha.origem.toLowerCase().contains(queryLower) ||
            linha.destino.toLowerCase().contains(queryLower);
      }).toList();
    }
  }

  // Métodos para Pontos de Parada
  Future<List<PontoParada>> getAllPontos() async {
    // Se web, retornar dados estáticos diretamente
    if (kIsWeb) {
      return _getPontosTeste();
    }

    try {
      final db = await database;
      if (db == null) {
        return _getPontosTeste();
      }
      final List<Map<String, dynamic>> maps = await db.query('pontos_parada');
      if (maps.isEmpty) {
        return _getPontosTeste();
      }
      return List.generate(maps.length, (i) => PontoParada.fromMap(maps[i]));
    } catch (e) {
      // Se falhar, retornar dados estáticos
      print('Erro ao buscar pontos do banco: $e');
      return _getPontosTeste();
    }
  }

  /// Retorna pontos de teste estáticos (fallback para web)
  List<PontoParada> _getPontosTeste() {
    return [
      PontoParada(
        id: 1,
        nome: 'Terminal Central',
        latitude: -23.5505,
        longitude: -46.6333,
        descricao: 'Terminal principal de ônibus',
      ),
      PontoParada(
        id: 2,
        nome: 'Praça da República',
        latitude: -23.5431,
        longitude: -46.6428,
        descricao: 'Parada em frente à praça',
      ),
      PontoParada(
        id: 3,
        nome: 'Shopping Center',
        latitude: -23.5489,
        longitude: -46.6388,
        descricao: 'Parada no shopping',
      ),
      PontoParada(
        id: 4,
        nome: 'Universidade',
        latitude: -23.5525,
        longitude: -46.6338,
        descricao: 'Parada na entrada da universidade',
      ),
      PontoParada(
        id: 5,
        nome: 'Hospital Regional',
        latitude: -23.5475,
        longitude: -46.6415,
        descricao: 'Parada em frente ao hospital',
      ),
      PontoParada(
        id: 6,
        nome: 'Aeroporto',
        latitude: -23.4325,
        longitude: -46.4691,
        descricao: 'Terminal de ônibus do aeroporto',
      ),
      PontoParada(
        id: 7,
        nome: 'Bairro Novo',
        latitude: -23.5550,
        longitude: -46.6400,
        descricao: 'Parada principal do bairro',
      ),
    ];
  }

  Future<PontoParada?> getPontoById(int id) async {
    // Se web, buscar nos dados estáticos
    if (kIsWeb) {
      final pontosTeste = _getPontosTeste();
      try {
        return pontosTeste.firstWhere((p) => p.id == id);
      } catch (_) {
        return null;
      }
    }

    try {
      final db = await database;
      if (db == null) {
        final pontosTeste = _getPontosTeste();
        try {
          return pontosTeste.firstWhere((p) => p.id == id);
        } catch (_) {
          return null;
        }
      }
      final List<Map<String, dynamic>> maps = await db.query(
        'pontos_parada',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (maps.isEmpty) {
        final pontosTeste = _getPontosTeste();
        try {
          return pontosTeste.firstWhere((p) => p.id == id);
        } catch (_) {
          return null;
        }
      }
      return PontoParada.fromMap(maps.first);
    } catch (e) {
      // Se falhar, buscar nos dados de teste
      final pontosTeste = _getPontosTeste();
      try {
        return pontosTeste.firstWhere((p) => p.id == id);
      } catch (_) {
        return null;
      }
    }
  }

  Future<List<PontoParada>> buscarPontos(String query) async {
    // Se web, buscar nos dados estáticos
    if (kIsWeb) {
      final pontosTeste = _getPontosTeste();
      final queryLower = query.toLowerCase();
      return pontosTeste.where((ponto) {
        return ponto.nome.toLowerCase().contains(queryLower) ||
            (ponto.descricao?.toLowerCase().contains(queryLower) ?? false);
      }).toList();
    }

    try {
      final db = await database;
      if (db == null) {
        final pontosTeste = _getPontosTeste();
        final queryLower = query.toLowerCase();
        return pontosTeste.where((ponto) {
          return ponto.nome.toLowerCase().contains(queryLower) ||
              (ponto.descricao?.toLowerCase().contains(queryLower) ?? false);
        }).toList();
      }
      final List<Map<String, dynamic>> maps = await db.query(
        'pontos_parada',
        where: 'nome LIKE ? OR descricao LIKE ?',
        whereArgs: ['%$query%', '%$query%'],
      );
      if (maps.isEmpty) {
        final pontosTeste = _getPontosTeste();
        final queryLower = query.toLowerCase();
        return pontosTeste.where((ponto) {
          return ponto.nome.toLowerCase().contains(queryLower) ||
              (ponto.descricao?.toLowerCase().contains(queryLower) ?? false);
        }).toList();
      }
      return List.generate(maps.length, (i) => PontoParada.fromMap(maps[i]));
    } catch (e) {
      // Se falhar, buscar nos dados de teste
      final pontosTeste = _getPontosTeste();
      final queryLower = query.toLowerCase();
      return pontosTeste.where((ponto) {
        return ponto.nome.toLowerCase().contains(queryLower) ||
            (ponto.descricao?.toLowerCase().contains(queryLower) ?? false);
      }).toList();
    }
  }
}
