import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'instellingen.dart';

/// Eén plaatsbepaling van het apparaat.
@immutable
class LocatieFix {
  const LocatieFix({
    required this.punt,
    required this.tijd,
    this.nauwkeurigheid = 0,
    this.koers,
    this.snelheid,
  });

  final LatLng punt;
  final DateTime tijd;

  /// Straal van de onzekerheid, in meters.
  final double nauwkeurigheid;

  /// Rijrichting in graden (0 = noord), of null als het apparaat stilstaat of het
  /// niet weet.
  final double? koers;

  /// In m/s, of null als onbekend.
  final double? snelheid;
}

enum LocatieStand {
  /// Niet gevraagd, of door de gebruiker uitgezet.
  uit,

  /// Toestemming wordt gevraagd, of de eerste plaatsbepaling loopt.
  zoekt,
  aan,
  geweigerd,

  /// Geweigerd met "niet meer vragen": alleen via de instellingen terug te draaien.
  permanentGeweigerd,

  /// Locatievoorzieningen van het apparaat staan uit.
  dienstUit,

  /// Toestemming is er, maar het apparaat komt niet tot een plaatsbepaling
  /// (binnen, of een computer zonder locatiedienst). Er wordt doorgezocht.
  nietGevonden,
}

@immutable
class LocatieToestand {
  const LocatieToestand([this.stand = LocatieStand.uit, this.fix]);

  final LocatieStand stand;

  /// De laatste plaatsbepaling; alleen als [stand] `aan` is.
  final LocatieFix? fix;
}

enum Toestemming { ja, nee, nooit, dienstUit }

/// Waar de fixes vandaan komen. Los van de notifier zodat tests en de
/// navigatiesimulatie een eigen bron kunnen geven.
abstract class LocatieBron {
  /// Zonder te vragen: is er al toestemming?
  Future<Toestemming> controleer();

  /// Vraagt het de gebruiker als dat nog kan.
  Future<Toestemming> vraag();

  /// [melding]: houd het ophalen op Android levend met een blijvende melding
  /// (voorgronddienst), ook met het scherm uit. Null = alleen op de voorgrond.
  Stream<LocatieFix> volg({
    required bool nauwkeurig,
    ({String titel, String tekst})? melding,
  });
}

class GeolocatorBron implements LocatieBron {
  const GeolocatorBron();

  static Toestemming _vertaal(LocationPermission toestemming) =>
      switch (toestemming) {
        LocationPermission.always ||
        LocationPermission.whileInUse => Toestemming.ja,
        LocationPermission.deniedForever => Toestemming.nooit,
        _ => Toestemming.nee,
      };

  @override
  Future<Toestemming> controleer() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return Toestemming.dienstUit;
    }
    return _vertaal(await Geolocator.checkPermission());
  }

  @override
  Future<Toestemming> vraag() async {
    final nu = await controleer();
    if (nu != Toestemming.nee) return nu;
    return _vertaal(await Geolocator.requestPermission());
  }

  @override
  Stream<LocatieFix> volg({
    required bool nauwkeurig,
    ({String titel, String tekst})? melding,
  }) {
    final instellingen = kIsWeb
        ? WebSettings(
            accuracy: LocationAccuracy.high,
            maximumAge: Duration.zero,
          )
        : defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: nauwkeurig ? 2 : 5,
            intervalDuration: const Duration(seconds: 1),
            foregroundNotificationConfig: melding == null
                ? null
                : ForegroundNotificationConfig(
                    notificationTitle: melding.titel,
                    notificationText: melding.tekst,
                    enableWakeLock: true,
                    setOngoing: true,
                  ),
          )
        : LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: nauwkeurig ? 2 : 5,
          );
    return Geolocator.getPositionStream(locationSettings: instellingen).map(
      (p) => LocatieFix(
        punt: LatLng(p.latitude, p.longitude),
        tijd: p.timestamp,
        nauwkeurigheid: p.accuracy,
        // Stilstaand is een koers ruis; op het web is hij vaak NaN.
        koers: p.speed > 1 && p.heading.isFinite && p.heading >= 0
            ? p.heading
            : null,
        snelheid: p.speed.isFinite && p.speed >= 0 ? p.speed : null,
      ),
    );
  }
}

final locatieBronProvider = Provider<LocatieBron>(
  (ref) => const GeolocatorBron(),
);

/// Je eigen plek. Pas aan na een tik van de gebruiker, nooit uit zichzelf bij het
/// opstarten -- behalve als je hem de vorige keer aan had en de toestemming er
/// nog is: dan zonder opnieuw te vragen.
class LocatieNotifier extends Notifier<LocatieToestand> {
  StreamSubscription<LocatieFix>? _stroom;
  AppLifecycleListener? _levensloop;

  /// Tijdens navigatie: nauwkeuriger, en op Android ook op de achtergrond.
  ({String titel, String tekst})? _navigatie;
  bool _navigeert = false;

  /// Wie op de eerste fix wacht (zie [eersteFix]).
  final _wachtenden = <Completer<LocatieFix?>>[];

  @override
  LocatieToestand build() {
    ref.onDispose(() {
      _stroom?.cancel();
      _levensloop?.dispose();
      _meld(null);
    });
    if (ref.read(instellingenProvider).locatieAan) {
      Future.microtask(_hervat);
    }
    return const LocatieToestand();
  }

  Future<void> _hervat() async {
    final bron = ref.read(locatieBronProvider);
    if (await bron.controleer() == Toestemming.ja) {
      state = const LocatieToestand(LocatieStand.zoekt);
      _start();
    }
  }

  /// Vraagt zo nodig toestemming en wacht op de eerste plaatsbepaling (hooguit
  /// 20 s). Null als het niet lukt; de reden staat dan in de toestand.
  Future<LocatieFix?> zetAan() async {
    if (state.fix case final fix?) return fix;
    // Zoekt hij al (of nog), dan niet opnieuw vragen en starten: wachten.
    if (_stroom != null) {
      state = const LocatieToestand(LocatieStand.zoekt);
      return eersteFix();
    }
    state = const LocatieToestand(LocatieStand.zoekt);
    final antwoord = await ref.read(locatieBronProvider).vraag();
    if (antwoord != Toestemming.ja) {
      state = LocatieToestand(switch (antwoord) {
        Toestemming.nooit => LocatieStand.permanentGeweigerd,
        Toestemming.dienstUit => LocatieStand.dienstUit,
        _ => LocatieStand.geweigerd,
      });
      return null;
    }
    _bewaar(true);
    _start();
    return eersteFix();
  }

  void zetUit() {
    _stop();
    _bewaar(false);
    state = const LocatieToestand();
  }

  /// De huidige fix, of de eerstvolgende als die er nog niet is.
  Future<LocatieFix?> eersteFix() async {
    if (state.fix case final fix?) return fix;
    if (state.stand != LocatieStand.zoekt &&
        state.stand != LocatieStand.nietGevonden) {
      return null;
    }
    final klaar = Completer<LocatieFix?>();
    _wachtenden.add(klaar);
    return klaar.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _wachtenden.remove(klaar);
        // Blijft zoeken, maar zegt nu eerlijk dat het nog niet lukt.
        if (state.stand == LocatieStand.zoekt) {
          state = const LocatieToestand(LocatieStand.nietGevonden);
        }
        return null;
      },
    );
  }

  void _meld(LocatieFix? fix) {
    for (final klaar in _wachtenden) {
      if (!klaar.isCompleted) klaar.complete(fix);
    }
    _wachtenden.clear();
  }

  /// Navigatie aan of uit: de stroom opnieuw, met andere instellingen.
  void navigatie(({String titel, String tekst})? melding) {
    _navigeert = melding != null;
    _navigatie = melding;
    if (_stroom != null) {
      _stop();
      _start();
    }
  }

  void _start() {
    // Niet op de voorgrond: stoppen, behalve tijdens navigatie. Terug: verder.
    _levensloop ??= AppLifecycleListener(
      onHide: () {
        if (!_navigeert) _stop();
      },
      onShow: () {
        final bezig =
            state.stand == LocatieStand.aan ||
            state.stand == LocatieStand.nietGevonden;
        if (bezig && _stroom == null) _start();
      },
    );
    _stroom = ref
        .read(locatieBronProvider)
        .volg(nauwkeurig: _navigeert, melding: _navigatie)
        .listen(
          (fix) {
            state = LocatieToestand(LocatieStand.aan, fix);
            _meld(fix);
          },
          onError: (Object fout) {
            // Geen plaatsbepaling (nog): doorzoeken, de browser of het toestel
            // probeert het zelf opnieuw.
            if (fout is! PermissionDeniedException &&
                fout is! LocationServiceDisabledException) {
              if (state.fix == null) {
                state = const LocatieToestand(LocatieStand.nietGevonden);
                _meld(null);
              }
              return;
            }
            // Toestemming onderweg ingetrokken, of de dienst uitgezet.
            _stop();
            state = LocatieToestand(
              fout is LocationServiceDisabledException
                  ? LocatieStand.dienstUit
                  : LocatieStand.geweigerd,
            );
            _meld(null);
          },
        );
  }

  void _stop() {
    _stroom?.cancel();
    _stroom = null;
  }

  void _bewaar(bool aan) {
    final instellingen = ref.read(instellingenProvider);
    if (instellingen.locatieAan != aan) {
      ref
          .read(instellingenProvider.notifier)
          .wijzig(instellingen.kopie(locatieAan: aan));
    }
  }
}

final locatieProvider = NotifierProvider<LocatieNotifier, LocatieToestand>(
  LocatieNotifier.new,
);
