import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:homemaps/models/plaats.dart';
import 'package:homemaps/providers/instellingen.dart';
import 'package:homemaps/providers/plekken.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

Plaats plek(String naam, double lat) =>
    Plaats(naam: naam, omschrijving: 'ergens', punt: LatLng(lat, 5.0));

void main() {
  test(
    'recent: nieuwste voorop, geen dubbele, hooguit acht, niet "Mijn locatie"',
    () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final plekken = c.read(plekkenProvider.notifier);
      for (var i = 0; i < 10; i++) {
        plekken.onthoud(plek('P$i', 52 + i * 0.01));
      }
      plekken.onthoud(plek('P3 opnieuw', 52.03));
      plekken.onthoud(Plaats.hier(const LatLng(52.5, 5)));
      final recent = c.read(plekkenProvider).recent;
      expect(recent, hasLength(maxRecent));
      expect(recent.first.naam, 'P3 opnieuw');
      expect(recent.where((p) => p.naam.startsWith('P3')), hasLength(1));
      expect(recent.any((p) => p.mijnLocatie), isFalse);
    },
  );

  test('thuis, werk en recent blijven bewaard over een herstart', () async {
    final map = await Directory.systemTemp.createTemp('plekken');
    addTearDown(() => map.delete(recursive: true));
    Hive.init(map.path);
    final doos = await Hive.openBox<dynamic>('instellingen');
    addTearDown(doos.close);

    ProviderContainer nieuw() {
      final c = ProviderContainer(
        overrides: [instellingenDoosProvider.overrideWithValue(doos)],
      );
      addTearDown(c.dispose);
      return c;
    }

    final eerst = nieuw();
    eerst.read(plekkenProvider.notifier)
      ..zetThuis(plek('Thuis-adres', 52.1))
      ..zetWerk(plek('Werk-adres', 52.2))
      ..onthoud(plek('Bakker', 52.3));

    final daarna = nieuw().read(plekkenProvider);
    expect(daarna.thuis?.naam, 'Thuis-adres');
    expect(daarna.werk?.punt, const LatLng(52.2, 5.0));
    expect(daarna.recent.single.omschrijving, 'ergens');

    nieuw().read(plekkenProvider.notifier)
      ..zetThuis(null)
      ..wisRecent();
    final weg = nieuw().read(plekkenProvider);
    expect(weg.thuis, isNull);
    expect(weg.werk?.naam, 'Werk-adres');
    expect(weg.recent, isEmpty);
  });
}
