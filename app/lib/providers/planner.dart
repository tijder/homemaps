import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/plaats.dart';
import '../models/route.dart';
import '../services/valhalla_service.dart';
import 'diensten.dart';
import 'instellingen.dart';

class PlannerState {
  const PlannerState({
    this.punten = const [null, null],
    this.routes = const AsyncData([]),
    this.gekozen = 0,
  });

  /// Van, eventuele tussenpunten, naar. Altijd minstens twee; null = nog leeg.
  final List<Plaats?> punten;
  final AsyncValue<List<RouteOptie>> routes;
  final int gekozen;

  bool get compleet => punten.every((p) => p != null);

  RouteOptie? get gekozenRoute {
    final lijst = routes.value;
    if (lijst == null || lijst.isEmpty) return null;
    return lijst[gekozen.clamp(0, lijst.length - 1)];
  }

  PlannerState kopie({
    List<Plaats?>? punten,
    AsyncValue<List<RouteOptie>>? routes,
    int? gekozen,
  }) => PlannerState(
    punten: punten ?? this.punten,
    routes: routes ?? this.routes,
    gekozen: gekozen ?? this.gekozen,
  );
}

class PlannerNotifier extends Notifier<PlannerState> {
  CancelToken? _lopend;

  /// De taal voor de instructies; het scherm zet hem bij het opbouwen.
  String taal = 'nl-NL';

  @override
  PlannerState build() {
    // Een andere vervoerswijze of optie is een andere route.
    ref.listen(instellingenProvider, (_, _) => _bereken());
    ref.onDispose(() => _lopend?.cancel());
    return const PlannerState();
  }

  void zetPunt(int index, Plaats? plaats) {
    final punten = [...state.punten]..[index] = plaats;
    state = state.kopie(punten: punten);
    _bereken();
  }

  /// Vult het eerste lege vakje, of vervangt de bestemming.
  void zetVolgende(Plaats plaats) {
    final leeg = state.punten.indexWhere((p) => p == null);
    zetPunt(leeg >= 0 ? leeg : state.punten.length - 1, plaats);
  }

  void voegViaToe([Plaats? plaats]) {
    final punten = [...state.punten]..insert(state.punten.length - 1, plaats);
    state = state.kopie(punten: punten);
    if (plaats != null) _bereken();
  }

  void verwijder(int index) {
    final punten = [...state.punten];
    if (punten.length > 2) {
      punten.removeAt(index);
    } else {
      punten[index] = null;
    }
    state = state.kopie(punten: punten);
    _bereken();
  }

  void verplaats(int van, int naar) {
    final punten = [...state.punten];
    punten.insert(naar > van ? naar - 1 : naar, punten.removeAt(van));
    state = state.kopie(punten: punten);
    _bereken();
  }

  void draaiOm() {
    state = state.kopie(punten: state.punten.reversed.toList());
    _bereken();
  }

  void wis() {
    _lopend?.cancel();
    state = const PlannerState();
  }

  void kies(int index) => state = state.kopie(gekozen: index);

  Future<void> _bereken() async {
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
        [for (final plaats in state.punten) plaats!.punt],
        instellingen.profiel,
        taal: taal,
        liveVerkeer: instellingen.liveVerkeer,
        vermijdSnelwegen: instellingen.vermijdSnelwegen,
        vermijdTol: instellingen.vermijdTol,
        vermijdVeren: instellingen.vermijdVeren,
        annuleer: annuleer,
      );
      if (!annuleer.isCancelled) state = state.kopie(routes: AsyncData(routes));
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
