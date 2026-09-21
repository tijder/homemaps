import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../models/profiel.dart';

/// Wat de gebruiker instelt en wat een herstart moet overleven.
class Instellingen {
  const Instellingen({
    this.server = '',
    this.stijl = 'osm-bright',
    this.profiel = Profiel.auto,
    this.liveVerkeer = true,
    this.vermijdSnelwegen = false,
    this.vermijdTol = false,
    this.vermijdVeren = false,
  });

  /// Alleen op Android nodig: op het web is de server de eigen origin.
  final String server;
  final String stijl;
  final Profiel profiel;
  final bool liveVerkeer;
  final bool vermijdSnelwegen;
  final bool vermijdTol;
  final bool vermijdVeren;

  Instellingen kopie({
    String? server,
    String? stijl,
    Profiel? profiel,
    bool? liveVerkeer,
    bool? vermijdSnelwegen,
    bool? vermijdTol,
    bool? vermijdVeren,
  }) => Instellingen(
    server: server ?? this.server,
    stijl: stijl ?? this.stijl,
    profiel: profiel ?? this.profiel,
    liveVerkeer: liveVerkeer ?? this.liveVerkeer,
    vermijdSnelwegen: vermijdSnelwegen ?? this.vermijdSnelwegen,
    vermijdTol: vermijdTol ?? this.vermijdTol,
    vermijdVeren: vermijdVeren ?? this.vermijdVeren,
  );
}

const _doos = 'instellingen';

/// Opent de opslag; aanroepen vóór runApp.
Future<Box<dynamic>> openInstellingen() async {
  await Hive.initFlutter();
  return Hive.openBox<dynamic>(_doos);
}

/// In main() overschreven met de geopende doos; in tests met een lege.
final instellingenDoosProvider = Provider<Box<dynamic>?>((ref) => null);

class InstellingenNotifier extends Notifier<Instellingen> {
  @override
  Instellingen build() {
    final doos = ref.watch(instellingenDoosProvider);
    if (doos == null) return const Instellingen();
    return Instellingen(
      server: doos.get('server', defaultValue: '') as String,
      stijl: doos.get('stijl', defaultValue: 'osm-bright') as String,
      profiel: Profiel.values.firstWhere(
        (p) => p.name == doos.get('profiel'),
        orElse: () => Profiel.auto,
      ),
      liveVerkeer: doos.get('liveVerkeer', defaultValue: true) as bool,
      vermijdSnelwegen:
          doos.get('vermijdSnelwegen', defaultValue: false) as bool,
      vermijdTol: doos.get('vermijdTol', defaultValue: false) as bool,
      vermijdVeren: doos.get('vermijdVeren', defaultValue: false) as bool,
    );
  }

  void wijzig(Instellingen nieuw) {
    state = nieuw;
    ref.read(instellingenDoosProvider)?.putAll({
      'server': nieuw.server,
      'stijl': nieuw.stijl,
      'profiel': nieuw.profiel.name,
      'liveVerkeer': nieuw.liveVerkeer,
      'vermijdSnelwegen': nieuw.vermijdSnelwegen,
      'vermijdTol': nieuw.vermijdTol,
      'vermijdVeren': nieuw.vermijdVeren,
    });
  }
}

final instellingenProvider =
    NotifierProvider<InstellingenNotifier, Instellingen>(
      InstellingenNotifier.new,
    );
