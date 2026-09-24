import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/profiel.dart';
import '../../providers/dawarich.dart';
import '../../providers/instellingen.dart';
import '../../providers/locatie_delen.dart';
import '../../providers/plekken.dart';
import '../../widgets/route_opties.dart';
import 'dawarich.dart';
import 'kaart.dart';
import 'locatie_delen.dart';
import 'over.dart';
import 'plekken.dart';
import 'route.dart';
import 'server.dart';

enum InstellingenGroep {
  kaart,
  delen,
  app;

  String titel(AppLocalizations l) => switch (this) {
    kaart => l.instellingenGroepKaart,
    delen => l.instellingenGroepDelen,
    app => l.instellingenGroepApp,
  };
}

/// De onderdelen van de instellingen, in de volgorde van de lijst.
enum InstellingenCategorie {
  kaart('kaart', Icons.map_outlined, InstellingenGroep.kaart),
  route('route', Icons.alt_route, InstellingenGroep.kaart),
  plekken('plekken', Icons.place_outlined, InstellingenGroep.kaart),
  dawarich('dawarich', Icons.family_restroom, InstellingenGroep.delen),
  locatieDelen('locatie-delen', Icons.share_location, InstellingenGroep.delen),
  server('server', Icons.dns_outlined, InstellingenGroep.app),
  over('over', Icons.info_outline, InstellingenGroep.app);

  const InstellingenCategorie(this.pad, this.pictogram, this.groep);

  /// Het laatste stuk van het adres: `/instellingen/<pad>`.
  final String pad;
  final IconData pictogram;
  final InstellingenGroep groep;

  static InstellingenCategorie? van(String? pad) =>
      zichtbare.where((c) => c.pad == pad).firstOrNull;

  /// Op het web is de server de eigen origin; daar valt niets in te stellen.
  static List<InstellingenCategorie> get zichtbare => [
    for (final c in values)
      if (c != server || !kIsWeb) c,
  ];

  String titel(AppLocalizations l) => switch (this) {
    kaart => l.instellingenKaart,
    route => l.route,
    plekken => l.plekken,
    dawarich => l.dawarich,
    locatieDelen => l.locatieDelen,
    server => l.server,
    over => l.overHomeMaps,
  };

  Widget inhoud() => switch (this) {
    kaart => const KaartInstellingen(),
    route => const RouteInstellingen(),
    plekken => const PlekkenInstellingen(),
    dawarich => const DawarichInstellingen(),
    locatieDelen => const LocatieDelenInstellingen(),
    server => const ServerInstellingen(),
    over => const OverInstellingen(),
  };

  /// Hoe het ervoor staat, in één regel onder de titel in de lijst.
  String samenvatting(WidgetRef ref, AppLocalizations l) {
    switch (this) {
      case kaart:
        final i = ref.watch(instellingenProvider);
        final stijl = KaartStijl.van(i.stijl);
        return [
          stijl.naam(l),
          if (stijl == KaartStijl.kaart) i.thema.naam(l),
          if (i.verkeerOpKaart) l.verkeerOpKaart,
        ].join(' · ');
      case route:
        final i = ref.watch(instellingenProvider);
        final auto = i.profiel == Profiel.auto;
        return [
          i.profiel.naam(l),
          if (auto && i.liveVerkeer) l.liveVerkeer,
          if (auto && i.vermijdSnelwegen) l.vermijdSnelwegen,
          if (auto && i.vermijdTol) l.vermijdTol,
          if (i.vermijdVeren) l.vermijdVeren,
        ].join(' · ');
      case plekken:
        final p = ref.watch(plekkenProvider);
        return [
          if (p.thuis != null) l.thuis,
          if (p.werk != null) l.werk,
          l.aantalPlekken(p.recent.length),
        ].join(' · ');
      case dawarich:
        final account = ref.watch(dawarichProvider);
        if (account == null) return l.dawarichNietIngelogd;
        final deelt = ref.watch(familieProvider).value?.delenAan ?? false;
        return [account.email, if (deelt) l.dawarichFamilieDeelt].join(' · ');
      case locatieDelen:
        final deel = ref.watch(deelInstellingenProvider);
        final status = ref.watch(locatieDelerProvider);
        if (!deel.aan) return l.deelUit;
        return [
          deel.sjabloon.naam ?? l.deelAangepast,
          if (status.fout case final fout?) l.deelFout(fout),
          if (status.inWachtrij > 0) l.deelInWachtrij(status.inWachtrij),
        ].join(' · ');
      case server:
        final adres = ref.watch(instellingenProvider).server;
        return adres.isEmpty
            ? l.nietIngesteld
            : (Uri.tryParse(adres)?.host ?? adres);
      case over:
        return l.overSamenvatting;
    }
  }
}
