import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/plaats.dart';
import '../models/route.dart';
import '../services/valhalla_service.dart';
import 'diensten.dart';
import 'instellingen.dart';

/// Eén vakje van de route. Het [id] blijft bij het vakje als de volgorde
/// verandert, zodat slepen in de lijst en op de kaart hetzelfde punt bedoelen.
class Routepunt {
  const Routepunt(this.id, [this.plaats]);

  final int id;
  final Plaats? plaats;
}

class PlannerState {
  const PlannerState({
    this.routeModus = false,
    this.gevonden,
    this.punten = const [Routepunt(0), Routepunt(1)],
    this.routes = const AsyncData([]),
    this.gekozen = 0,
    this.beeldVersie = 0,
  });

  /// Onwaar: het zoekscherm (één zoekbalk, eventueel een gevonden plaats).
  /// Waar: het routescherm met van/via/naar.
  final bool routeModus;

  /// De plaats die in het zoekscherm is gekozen.
  final Plaats? gevonden;

  /// Van, eventuele tussenpunten, naar. Altijd minstens twee.
  final List<Routepunt> punten;
  final AsyncValue<List<RouteOptie>> routes;
  final int gekozen;

  /// Loopt op telkens als de kaart het resultaat in beeld moet brengen: na zoeken
  /// wel, na het verslepen van een punt juist niet.
  final int beeldVersie;

  bool get compleet => punten.every((p) => p.plaats != null);

  RouteOptie? get gekozenRoute {
    final lijst = routes.value;
    if (lijst == null || lijst.isEmpty) return null;
    return lijst[gekozen.clamp(0, lijst.length - 1)];
  }

  PlannerState kopie({
    bool? routeModus,
    Plaats? Function()? gevonden,
    List<Routepunt>? punten,
    AsyncValue<List<RouteOptie>>? routes,
    int? gekozen,
    int? beeldVersie,
  }) => PlannerState(
    routeModus: routeModus ?? this.routeModus,
    gevonden: gevonden != null ? gevonden() : this.gevonden,
    punten: punten ?? this.punten,
    routes: routes ?? this.routes,
    gekozen: gekozen ?? this.gekozen,
    beeldVersie: beeldVersie ?? this.beeldVersie,
  );
}

class PlannerNotifier extends Notifier<PlannerState> {
  CancelToken? _lopend;
  int _volgendId = 2;

  /// De taal voor de instructies; het scherm zet hem bij het opbouwen.
  String taal = 'nl-NL';

  @override
  PlannerState build() {
    // Een andere vervoerswijze of optie is een andere route.
    ref.listen(instellingenProvider, (_, _) => _bereken(volgBeeld: false));
    ref.onDispose(() => _lopend?.cancel());
    return const PlannerState();
  }

  // ---------------------------------------------------------------- zoekscherm

  void toonPlaats(Plaats plaats) => state = state.kopie(
    gevonden: () => plaats,
    beeldVersie: state.beeldVersie + 1,
  );

  void sluitPlaats() => state = state.kopie(gevonden: () => null);

  /// "Route" op de gevonden plaats: die wordt de bestemming.
  void startRoute() {
    final doel = state.gevonden;
    state = PlannerState(
      routeModus: true,
      gevonden: doel,
      punten: [Routepunt(_volgendId++), Routepunt(_volgendId++, doel)],
      beeldVersie: state.beeldVersie,
    );
  }

  /// Terug naar het zoekscherm; de route is weg, de gevonden plaats blijft.
  void naarZoeken() {
    _lopend?.cancel();
    state = PlannerState(
      gevonden: state.gevonden,
      beeldVersie: state.beeldVersie,
    );
  }

  // --------------------------------------------------------------- routescherm

  /// [volgBeeld]: breng het resultaat in beeld. Bij slepen op de kaart niet --
  /// dan springt de kaart onder je hand vandaan.
  void zetPunt(int index, Plaats? plaats, {bool volgBeeld = true}) {
    final punten = [...state.punten];
    punten[index] = Routepunt(punten[index].id, plaats);
    state = state.kopie(
      routeModus: true,
      punten: punten,
      beeldVersie: volgBeeld ? state.beeldVersie + 1 : null,
    );
    _bereken(volgBeeld: volgBeeld);
  }

  /// Alleen de naam van een punt bijwerken (het adres bij een aangeklikt punt);
  /// de plek is dezelfde, dus er hoeft geen nieuwe route te komen.
  void hernoem(int index, Plaats plaats) {
    final punten = [...state.punten];
    punten[index] = Routepunt(punten[index].id, plaats);
    state = state.kopie(punten: punten);
  }

  void zetVan(Plaats plaats, {bool volgBeeld = true}) =>
      zetPunt(0, plaats, volgBeeld: volgBeeld);

  void zetNaar(Plaats plaats, {bool volgBeeld = true}) =>
      zetPunt(state.punten.length - 1, plaats, volgBeeld: volgBeeld);

  void voegViaToe([Plaats? plaats]) {
    final punten = [...state.punten]
      ..insert(state.punten.length - 1, Routepunt(_volgendId++, plaats));
    state = state.kopie(routeModus: true, punten: punten);
    if (plaats != null) _bereken(volgBeeld: false);
  }

  void verwijder(int index) {
    final punten = [...state.punten];
    if (punten.length > 2) {
      punten.removeAt(index);
    } else {
      punten[index] = Routepunt(punten[index].id);
    }
    state = state.kopie(punten: punten);
    _bereken(volgBeeld: false);
  }

  /// [naar] is de plek in de lijst ná het weghalen van [van] (zo levert
  /// ReorderableListView.onReorderItem het aan).
  void verplaats(int van, int naar) {
    final punten = [...state.punten];
    punten.insert(naar, punten.removeAt(van));
    // Een andere volgorde is een heel andere route: die moet weer in beeld.
    state = state.kopie(punten: punten, beeldVersie: state.beeldVersie + 1);
    _bereken(volgBeeld: true);
  }

  void draaiOm() {
    state = state.kopie(
      punten: state.punten.reversed.toList(),
      beeldVersie: state.beeldVersie + 1,
    );
    _bereken(volgBeeld: true);
  }

  void kies(int index) => state = state.kopie(gekozen: index);

  Future<void> _bereken({required bool volgBeeld}) async {
    _lopend?.cancel();
    final valhalla = ref.read(valhallaProvider);
    if (!state.compleet || valhalla == null) {
      state = state.kopie(routes: const AsyncData([]), gekozen: 0);
      return;
    }
    final annuleer = _lopend = CancelToken();
    final instellingen = ref.read(instellingenProvider);
    state = state.kopie(routes: const AsyncLoading(), gekozen: 0);
    try {
      final routes = await valhalla.route(
        [for (final punt in state.punten) punt.plaats!.punt],
        instellingen.profiel,
        taal: taal,
        liveVerkeer: instellingen.liveVerkeer,
        vermijdSnelwegen: instellingen.vermijdSnelwegen,
        vermijdTol: instellingen.vermijdTol,
        vermijdVeren: instellingen.vermijdVeren,
        annuleer: annuleer,
      );
      if (annuleer.isCancelled) return;
      state = state.kopie(
        routes: AsyncData(routes),
        // Nog een keer: nu is er pas een route om in beeld te brengen.
        beeldVersie: volgBeeld ? state.beeldVersie + 1 : null,
      );
    } on DioException catch (fout) {
      // Geannuleerd door een nieuwer verzoek: dat schrijft zelf de uitkomst.
      if (!CancelToken.isCancel(fout)) {
        state = state.kopie(routes: AsyncError(fout, StackTrace.current));
      }
    } on RouteFout catch (fout, spoor) {
      if (!annuleer.isCancelled) {
        state = state.kopie(routes: AsyncError(fout, spoor));
      }
    }
  }
}

final plannerProvider = NotifierProvider<PlannerNotifier, PlannerState>(
  PlannerNotifier.new,
);
