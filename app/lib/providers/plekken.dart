import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/plaats.dart';
import '../utils/afstand.dart';
import 'instellingen.dart';

/// Thuis, werk en de laatst gekozen bestemmingen.
@immutable
class Plekken {
  const Plekken({this.thuis, this.werk, this.recent = const []});

  final Plaats? thuis;
  final Plaats? werk;

  /// Nieuwste eerst.
  final List<Plaats> recent;
}

/// Hoeveel recente plekken er bewaard blijven.
const maxRecent = 8;

class PlekkenNotifier extends Notifier<Plekken> {
  @override
  Plekken build() {
    final doos = ref.watch(instellingenDoosProvider);
    if (doos == null) return const Plekken();
    return Plekken(
      thuis: _lees(doos.get('thuis')),
      werk: _lees(doos.get('werk')),
      recent: [
        for (final waarde in (doos.get('recent') as List? ?? const []))
          ?_lees(waarde),
      ],
    );
  }

  void zetThuis(Plaats? plaats) {
    state = Plekken(thuis: plaats, werk: state.werk, recent: state.recent);
    _bewaar();
  }

  void zetWerk(Plaats? plaats) {
    state = Plekken(thuis: state.thuis, werk: plaats, recent: state.recent);
    _bewaar();
  }

  void wisRecent() {
    state = Plekken(thuis: state.thuis, werk: state.werk);
    _bewaar();
  }

  /// Een plek die de gebruiker koos: vooraan in de recente, zonder dubbele
  /// (dezelfde plek binnen 30 m telt als dezelfde). "Mijn locatie" niet: die
  /// is elke keer ergens anders.
  void onthoud(Plaats plaats) {
    if (plaats.mijnLocatie) return;
    state = Plekken(
      thuis: state.thuis,
      werk: state.werk,
      recent: [
        plaats,
        for (final oud in state.recent)
          if (meters(oud.punt, plaats.punt) > 30) oud,
      ].take(maxRecent).toList(),
    );
    _bewaar();
  }

  void _bewaar() {
    ref.read(instellingenDoosProvider)?.putAll({
      'thuis': _schrijf(state.thuis),
      'werk': _schrijf(state.werk),
      'recent': [for (final plaats in state.recent) _schrijf(plaats)],
    });
  }

  static Map<String, dynamic>? _schrijf(Plaats? plaats) => plaats == null
      ? null
      : {
          'naam': plaats.naam,
          'omschrijving': plaats.omschrijving,
          'lat': plaats.punt.latitude,
          'lon': plaats.punt.longitude,
        };

  static Plaats? _lees(Object? waarde) {
    if (waarde is! Map) return null;
    final lat = waarde['lat'], lon = waarde['lon'];
    if (lat is! num || lon is! num) return null;
    return Plaats(
      naam: waarde['naam'] as String? ?? '',
      omschrijving: waarde['omschrijving'] as String? ?? '',
      punt: LatLng(lat.toDouble(), lon.toDouble()),
    );
  }
}

final plekkenProvider = NotifierProvider<PlekkenNotifier, Plekken>(
  PlekkenNotifier.new,
);
