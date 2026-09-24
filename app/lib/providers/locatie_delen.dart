import 'dart:async';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/locatie_delen.dart';
import '../models/profiel.dart';
import '../services/locatie_deler.dart';
import '../utils/afstand.dart';
import 'diensten.dart';
import 'instellingen.dart';
import 'locatie.dart';

/// Het wachtwoord of de token voor de server; niet in de gewone opslag.
abstract class GeheimOpslag {
  Future<String?> lees();
  Future<void> schrijf(String geheim);
}

class VeiligeGeheimOpslag implements GeheimOpslag {
  const VeiligeGeheimOpslag([this._sleutel = 'locatieDelenGeheim']);

  final String _sleutel;
  static const _opslag = FlutterSecureStorage();

  @override
  Future<String?> lees() => _opslag.read(key: _sleutel);

  @override
  Future<void> schrijf(String geheim) => geheim.isEmpty
      ? _opslag.delete(key: _sleutel)
      : _opslag.write(key: _sleutel, value: geheim);
}

/// In het geheugen: voor tests, en als er geen veilige opslag is.
class GeheugenGeheimOpslag implements GeheimOpslag {
  String? geheim;

  @override
  Future<String?> lees() async => geheim;

  @override
  Future<void> schrijf(String geheim) async => this.geheim = geheim;
}

final geheimOpslagProvider = Provider<GeheimOpslag>(
  (ref) => const VeiligeGeheimOpslag(),
);

class DeelInstellingenNotifier extends Notifier<DeelInstellingen> {
  static const _sleutel = 'locatieDelen';

  /// Klaar als het geheim uit de veilige opslag gelezen is.
  late Future<void> geladen;

  @override
  DeelInstellingen build() {
    final doos = ref.watch(instellingenDoosProvider);
    final opgeslagen = DeelInstellingen.vanMap(doos?.get(_sleutel));
    geladen = _laadGeheim();
    return opgeslagen;
  }

  Future<void> _laadGeheim() async {
    try {
      final geheim = await ref.read(geheimOpslagProvider).lees();
      if (geheim != null && geheim.isNotEmpty) {
        state = state.kopie(geheim: geheim);
      }
    } on Object catch (fout) {
      debugPrint('Geheim voor locatie delen niet te lezen: $fout');
    }
  }

  Future<void> wijzig(DeelInstellingen nieuw) async {
    final oud = state;
    state = nieuw;
    await ref.read(instellingenDoosProvider)?.put(_sleutel, nieuw.naarMap());
    if (nieuw.geheim != oud.geheim) {
      await ref.read(geheimOpslagProvider).schrijf(nieuw.geheim);
    }
  }
}

final deelInstellingenProvider =
    NotifierProvider<DeelInstellingenNotifier, DeelInstellingen>(
      DeelInstellingenNotifier.new,
    );

/// Punten die nog naar de server moeten, oudste eerst. Met een Hive-doos
/// overleven ze een herstart; zonder (tests) staan ze in het geheugen.
class DeelWachtrij {
  DeelWachtrij([this._doos]);

  final Box<dynamic>? _doos;
  final _geheugen = <DeelPunt>[];

  /// Meer bewaren heeft geen zin: dan is er iets structureel mis.
  static const maximum = 5000;

  int get lengte => _doos?.length ?? _geheugen.length;

  Future<void> voegToe(DeelPunt punt) async {
    final doos = _doos;
    if (doos == null) {
      _geheugen.add(punt);
      if (_geheugen.length > maximum) {
        _geheugen.removeRange(0, _geheugen.length - maximum);
      }
      return;
    }
    await doos.add(punt.naarMap());
    if (doos.length > maximum) {
      await doos.deleteAll(doos.keys.take(doos.length - maximum).toList());
    }
  }

  /// De oudste [aantal] punten.
  List<DeelPunt> eerste(int aantal) {
    final doos = _doos;
    if (doos == null) return _geheugen.take(aantal).toList();
    return [
      for (final ruw in doos.values.take(aantal))
        DeelPunt.vanMap(ruw as Map<dynamic, dynamic>),
    ];
  }

  /// De oudste [aantal] punten zijn aangekomen.
  Future<void> haalWeg(int aantal) async {
    final doos = _doos;
    if (doos == null) {
      _geheugen.removeRange(0, min(aantal, _geheugen.length));
      return;
    }
    await doos.deleteAll(doos.keys.take(aantal).toList());
  }

  Future<void> wis() async {
    _geheugen.clear();
    await _doos?.clear();
  }
}

/// Opent de doos van de wachtrij; aanroepen vóór runApp (na [openInstellingen]).
Future<Box<dynamic>> openDeelWachtrij() =>
    Hive.openBox<dynamic>('deelWachtrij');

/// In main() overschreven met de geopende doos.
final deelWachtrijDoosProvider = Provider<Box<dynamic>?>((ref) => null);

final deelWachtrijProvider = Provider<DeelWachtrij>(
  (ref) => DeelWachtrij(ref.watch(deelWachtrijDoosProvider)),
);

/// De batterij op het moment van een punt.
typedef Batterij = ({int? procent, String? staat});

abstract class BatterijBron {
  Future<Batterij> lees();
}

/// Via battery_plus; hooguit eens per minuut gevraagd, zo snel verandert hij
/// niet. Kan het niet (een browser zonder Battery API), dan onbekend.
class ToestelBatterij implements BatterijBron {
  final _batterij = Battery();
  Batterij? _laatst;
  DateTime? _gelezen;

  @override
  Future<Batterij> lees() async {
    final nu = DateTime.now();
    final laatst = _laatst;
    if (laatst != null && nu.difference(_gelezen!).inSeconds < 60) {
      return laatst;
    }
    Batterij waarde;
    try {
      final procent = await _batterij.batteryLevel;
      final staat = await _batterij.batteryState;
      waarde = (
        procent: procent >= 0 && procent <= 100 ? procent : null,
        staat: switch (staat) {
          BatteryState.discharging => 'unplugged',
          BatteryState.charging ||
          BatteryState.connectedNotCharging => 'charging',
          BatteryState.full => 'full',
          BatteryState.unknown => null,
        },
      );
    } on Object {
      waarde = (procent: null, staat: null);
    }
    _laatst = waarde;
    _gelezen = nu;
    return waarde;
  }
}

final batterijBronProvider = Provider<BatterijBron>((ref) => ToestelBatterij());

/// Hoe Overland en Dawarich de vervoerswijze noemen.
String vervoerVan(Profiel profiel) => switch (profiel) {
  Profiel.auto => 'driving',
  Profiel.fiets => 'cycling',
  Profiel.lopen => 'walking',
};

final deelVerzenderProvider = Provider<DeelVerzender>(
  (ref) => DioVerzender(ref.watch(dioProvider)),
);

/// Hoe het delen ervoor staat, voor het scherm.
@immutable
class DeelStatus {
  const DeelStatus({
    this.inWachtrij = 0,
    this.laatstVerstuurd,
    this.fout,
    this.gestopt = false,
  });

  final int inWachtrij;
  final DateTime? laatstVerstuurd;

  /// De laatste fout ("HTTP 401", of dat de server niet te bereiken is).
  final String? fout;

  /// Na een fout in de instellingen (4xx): pas weer na een wijziging.
  final bool gestopt;
}

/// Stuurt tijdens het navigeren de positie naar de server van de gebruiker,
/// zoals Colota: alleen als het aan staat en je onderweg bent. Wat niet
/// aankomt blijft in de [DeelWachtrij] en gaat later, in volgorde.
class LocatieDeler extends Notifier<DeelStatus> {
  DeelPunt? _vorige;
  bool _bezig = false;
  int _pogingen = 0;
  Timer? _opnieuw;

  /// Wachttijden na een mislukte poging: 30 s, 1 min, 2 min, dan 5 min.
  static const _wachttijden = [30, 60, 120, 300];

  @override
  DeelStatus build() {
    ref.onDispose(() => _opnieuw?.cancel());
    ref.listen(locatieProvider.select((t) => t.fix), (_, fix) {
      if (fix != null) _bijFix(fix);
    });
    // Klaar met navigeren: nog één keer proberen.
    ref.listen(onderwegProvider, (_, onderweg) {
      if (!onderweg) {
        _vorige = null;
        leeg();
      }
    });
    // Andere instellingen: een eerdere fout geldt niet meer.
    ref.listen(deelInstellingenProvider, (_, _) {
      _pogingen = 0;
      _opnieuw?.cancel();
      state = DeelStatus(
        inWachtrij: ref.read(deelWachtrijProvider).lengte,
        laatstVerstuurd: state.laatstVerstuurd,
      );
      leeg();
    });
    final wachtrij = ref.read(deelWachtrijProvider);
    // Van een vorige keer blijven staan: nu alsnog.
    if (wachtrij.lengte > 0) Future.microtask(leeg);
    return DeelStatus(inWachtrij: wachtrij.lengte);
  }

  Future<void> _bijFix(LocatieFix fix) async {
    final instellingen = ref.read(deelInstellingenProvider);
    if (!instellingen.aan ||
        !instellingen.compleet ||
        !ref.read(onderwegProvider)) {
      return;
    }
    // Een fix van meer dan honderd meter breed zegt te weinig.
    if (fix.nauwkeurigheid > 100) return;
    final tst = fix.tijd.millisecondsSinceEpoch ~/ 1000;
    final vorige = _vorige;
    if (vorige != null &&
        tst - vorige.tst < instellingen.interval &&
        meters(fix.punt, _plek(vorige)) < instellingen.minAfstand) {
      return;
    }
    // Meteen, anders komt de volgende fix tijdens het wachten op de batterij
    // er ook nog door.
    _vorige = DeelPunt(
      lat: fix.punt.latitude,
      lon: fix.punt.longitude,
      tst: tst,
    );
    final batterij = await ref.read(batterijBronProvider).lees();
    final punt = DeelPunt(
      lat: fix.punt.latitude,
      lon: fix.punt.longitude,
      tst: tst,
      acc: fix.nauwkeurigheid,
      alt: fix.hoogte,
      vel: fix.snelheid,
      bear: fix.koers,
      vac: fix.hoogteNauwkeurigheid,
      bearAcc: fix.koersNauwkeurigheid,
      batt: batterij.procent,
      bs: batterij.staat,
      vervoer: vervoerVan(ref.read(instellingenProvider).profiel),
    );
    final wachtrij = ref.read(deelWachtrijProvider);
    await wachtrij.voegToe(punt);
    state = DeelStatus(
      inWachtrij: wachtrij.lengte,
      laatstVerstuurd: state.laatstVerstuurd,
      fout: state.fout,
      gestopt: state.gestopt,
    );
    await leeg();
  }

  /// Stuurt de wachtrij, oudste eerst, tot hij leeg is of er iets misgaat.
  Future<void> leeg() async {
    if (_bezig || state.gestopt || (_opnieuw?.isActive ?? false)) return;
    await ref.read(deelInstellingenProvider.notifier).geladen;
    final instellingen = ref.read(deelInstellingenProvider);
    if (!instellingen.compleet) return;
    final wachtrij = ref.read(deelWachtrijProvider);
    final verzender = ref.read(deelVerzenderProvider);
    _bezig = true;
    try {
      while (wachtrij.lengte > 0) {
        final punten = wachtrij.eerste(puntenPerVerzoek(instellingen));
        String? fout;
        var status = 0;
        try {
          status = await verzender.stuur(bouwVerzoek(instellingen, punten));
        } on Object catch (e) {
          fout = _foutTekst(e);
        }
        if (status >= 200 && status < 300) {
          await wachtrij.haalWeg(punten.length);
          _pogingen = 0;
          state = DeelStatus(
            inWachtrij: wachtrij.lengte,
            laatstVerstuurd: DateTime.now(),
          );
          continue;
        }
        fout ??= 'HTTP $status';
        // Een 4xx is de instelling (adres, sleutel, veldnamen): opnieuw
        // proberen helpt niet. Behalve "time-out" en "te veel verzoeken".
        final instelling =
            status >= 400 && status < 500 && status != 408 && status != 429;
        state = DeelStatus(
          inWachtrij: wachtrij.lengte,
          laatstVerstuurd: state.laatstVerstuurd,
          fout: fout,
          gestopt: instelling,
        );
        if (!instelling) {
          final wacht = _wachttijden[min(_pogingen, _wachttijden.length - 1)];
          _pogingen++;
          _opnieuw = Timer(Duration(seconds: wacht), leeg);
        }
        return;
      }
    } finally {
      _bezig = false;
    }
  }

  /// "Verbinding testen": één punt, buiten de wachtrij om. Geeft de fout, of
  /// null als het aankwam.
  Future<String?> test(DeelInstellingen instellingen, DeelPunt punt) async {
    try {
      final status = await ref
          .read(deelVerzenderProvider)
          .stuur(bouwVerzoek(instellingen, [punt]));
      return status >= 200 && status < 300 ? null : 'HTTP $status';
    } on Object catch (e) {
      return _foutTekst(e);
    }
  }

  Future<void> wisWachtrij() async {
    final wachtrij = ref.read(deelWachtrijProvider);
    await wachtrij.wis();
    _opnieuw?.cancel();
    state = DeelStatus(laatstVerstuurd: state.laatstVerstuurd);
  }
}

/// Kort en leesbaar: Dio's eigen tekst is een halve pagina.
String _foutTekst(Object fout) => fout is DioException
    ? (fout.message ?? fout.error?.toString() ?? fout.type.name)
    : '$fout';

LatLng _plek(DeelPunt p) => LatLng(p.lat, p.lon);

final locatieDelerProvider = NotifierProvider<LocatieDeler, DeelStatus>(
  LocatieDeler.new,
);
