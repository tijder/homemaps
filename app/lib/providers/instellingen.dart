import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../l10n/app_localizations.dart';
import '../models/profiel.dart';

/// De kaartstijlen van de tileserver, met hun id in de stijl-URL.
enum KaartStijl {
  kaart('osm-bright'),
  licht('positron'),
  donker('dark-matter');

  const KaartStijl(this.id);

  final String id;

  String naam(AppLocalizations l) => switch (this) {
    kaart => l.stijlKaart,
    licht => l.stijlLicht,
    donker => l.stijlDonker,
  };

  static KaartStijl van(String id) =>
      values.firstWhere((s) => s.id == id, orElse: () => kaart);
}

/// Dag- of nachtversie van de kaart: met de telefoon mee, of altijd één van
/// de twee.
enum KaartThema {
  automatisch,
  dag,
  nacht;

  String naam(AppLocalizations l) => switch (this) {
    automatisch => l.themaAutomatisch,
    dag => l.themaDag,
    nacht => l.themaNacht,
  };
}

/// Wat de gebruiker instelt en wat een herstart moet overleven.
class Instellingen {
  const Instellingen({
    this.server = '',
    this.stijl = 'osm-bright',
    this.thema = KaartThema.automatisch,
    this.profiel = Profiel.auto,
    this.liveVerkeer = true,
    this.vermijdSnelwegen = false,
    this.vermijdTol = false,
    this.vermijdVeren = false,
    this.verkeerOpKaart = true,
    this.locatieAan = false,
  });

  /// Alleen op Android nodig: op het web is de server de eigen origin.
  final String server;
  final String stijl;

  /// Alleen voor de stijl "Kaart"; "Licht" en "Donker" zijn al een keuze.
  final KaartThema thema;
  final Profiel profiel;
  final bool liveVerkeer;
  final bool vermijdSnelwegen;
  final bool vermijdTol;
  final bool vermijdVeren;

  /// Afsluitingen, werk op de weg en files als laag over de kaart.
  final bool verkeerOpKaart;

  /// De gebruiker zette zijn locatie aan: bij de volgende start weer, als de
  /// toestemming er dan nog is.
  final bool locatieAan;

  Instellingen kopie({
    String? server,
    String? stijl,
    KaartThema? thema,
    Profiel? profiel,
    bool? liveVerkeer,
    bool? vermijdSnelwegen,
    bool? vermijdTol,
    bool? vermijdVeren,
    bool? verkeerOpKaart,
    bool? locatieAan,
  }) => Instellingen(
    server: server ?? this.server,
    stijl: stijl ?? this.stijl,
    thema: thema ?? this.thema,
    profiel: profiel ?? this.profiel,
    liveVerkeer: liveVerkeer ?? this.liveVerkeer,
    vermijdSnelwegen: vermijdSnelwegen ?? this.vermijdSnelwegen,
    vermijdTol: vermijdTol ?? this.vermijdTol,
    vermijdVeren: vermijdVeren ?? this.vermijdVeren,
    verkeerOpKaart: verkeerOpKaart ?? this.verkeerOpKaart,
    locatieAan: locatieAan ?? this.locatieAan,
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
      thema: KaartThema.values.firstWhere(
        (t) => t.name == doos.get('thema'),
        orElse: () => KaartThema.automatisch,
      ),
      profiel: Profiel.values.firstWhere(
        (p) => p.name == doos.get('profiel'),
        orElse: () => Profiel.auto,
      ),
      liveVerkeer: doos.get('liveVerkeer', defaultValue: true) as bool,
      vermijdSnelwegen:
          doos.get('vermijdSnelwegen', defaultValue: false) as bool,
      vermijdTol: doos.get('vermijdTol', defaultValue: false) as bool,
      vermijdVeren: doos.get('vermijdVeren', defaultValue: false) as bool,
      verkeerOpKaart: doos.get('verkeerOpKaart', defaultValue: true) as bool,
      locatieAan: doos.get('locatieAan', defaultValue: false) as bool,
    );
  }

  void wijzig(Instellingen nieuw) {
    state = nieuw;
    ref.read(instellingenDoosProvider)?.putAll({
      'server': nieuw.server,
      'stijl': nieuw.stijl,
      'thema': nieuw.thema.name,
      'profiel': nieuw.profiel.name,
      'liveVerkeer': nieuw.liveVerkeer,
      'vermijdSnelwegen': nieuw.vermijdSnelwegen,
      'vermijdTol': nieuw.vermijdTol,
      'vermijdVeren': nieuw.vermijdVeren,
      'verkeerOpKaart': nieuw.verkeerOpKaart,
      'locatieAan': nieuw.locatieAan,
    });
  }
}

final instellingenProvider =
    NotifierProvider<InstellingenNotifier, Instellingen>(
      InstellingenNotifier.new,
    );
