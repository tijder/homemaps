import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/plaats.dart';
import '../models/route.dart';
import '../providers/locatie.dart';
import '../utils/afstand.dart';

/// De kaart met de routes en de punten erop. Weet niets van de planner: krijgt
/// wat hij moet tekenen en meldt wat er wordt aangetikt.
class Kaart extends StatefulWidget {
  const Kaart({
    super.key,
    required this.stijlUrl,
    required this.start,
    required this.punten,
    required this.gevonden,
    required this.beeldVersie,
    required this.onPuntVersleept,
    required this.routes,
    required this.gekozen,
    required this.onRouteGekozen,
    required this.onLangIngedrukt,
    required this.rand,
    this.locatie,
    this.volg,
    this.gereden,
    this.navigeert = false,
    this.onZelfBewogen,
    this.verkeer,
    this.toonVertraging = true,
    this.onVerkeerGetikt,
    this.onController,
  });

  final String stijlUrl;
  final CameraPosition start;

  /// De punten van de route (van, via's, naar); op de kaart te verslepen.
  final List<Plaats?> punten;

  /// De plaats uit het zoekscherm: een vaste, blauwe stip.
  final Plaats? gevonden;

  /// Loopt op als het resultaat in beeld gebracht moet worden (zie PlannerState).
  final int beeldVersie;
  final void Function(int index, LatLng punt) onPuntVersleept;
  final List<RouteOptie> routes;
  final int gekozen;
  final ValueChanged<int> onRouteGekozen;
  final void Function(Point<double> scherm, LatLng punt) onLangIngedrukt;

  /// De ruimte die het paneel over de kaart legt; de route wordt daarbuiten
  /// in beeld gebracht.
  final EdgeInsets rand;

  /// Je eigen plek (het blauwe puntje), of null als de locatie uit staat.
  final LocatieFix? locatie;

  /// Tijdens navigatie: de camera rijdt mee, gekanteld en in de rijrichting,
  /// met je plek in het onderste deel van het beeld. Null = de kaart is vrij.
  final ({LatLng punt, double koers, double snelheid})? volg;

  /// Tijdens navigatie: het stuk van de route dat al achter je ligt, grijs over
  /// de blauwe lijn heen.
  final List<LatLng>? gereden;

  /// Tijdens navigatie ligt het midden van de kaart lager (zie [volg]), ook
  /// als je even zelf rondkijkt; daarna gaat de kaart weer plat en noord-boven.
  final bool navigeert;

  /// De gebruiker raakt de kaart zelf aan (schuiven, knijpen, scrollen): dan
  /// moet het meerijden even stoppen.
  final VoidCallback? onZelfBewogen;

  /// De verkeerslaag (GeoJSON van `/verkeer`), of null als hij uit staat.
  final Map<String, dynamic>? verkeer;

  /// Files en langzaam verkeer tonen; afsluitingen en werk staan er altijd op.
  final bool toonVertraging;

  /// Een tik op een stuk verkeer, met de eigenschappen uit de GeoJSON.
  final void Function(Point<double> scherm, Map<String, dynamic> eigenschappen)?
  onVerkeerGetikt;
  final ValueChanged<MapLibreMapController>? onController;

  @override
  State<Kaart> createState() => _KaartState();
}

class _KaartState extends State<Kaart> {
  static const _routeBron = 'routes';
  static const _aansluitBron = 'aansluiting';
  static const _verkeerBron = 'verkeer';
  static const _geredenBron = 'gereden';

  /// Kleiner dan dit is het gat tussen een punt en de weg niet het tonen waard.
  static const _minAansluiting = 15.0;
  static const _lagen = ['route-alt', 'route-rand', 'route'];

  MapLibreMapController? _controller;
  bool _stijlKlaar = false;

  /// Feature-id -> eigenschappen, om bij een tik te laten zien wat er is.
  var _verkeerInfo = <String, Map<String, dynamic>>{};

  /// Cirkel-id -> index in [Kaart.punten]; de gevonden plaats zit er niet in.
  final _cirkelIndex = <String, int>{};
  int _ingepast = 0;
  int _tekenVolgnummer = 0;

  @override
  void didUpdateWidget(Kaart oud) {
    super.didUpdateWidget(oud);
    if (oud.stijlUrl != widget.stijlUrl) {
      // Een nieuwe stijl gooit alle bronnen en lagen weg; onStyleLoaded zet ze
      // terug.
      _stijlKlaar = false;
      return;
    }
    if (!_stijlKlaar) return;
    if (oud.locatie != widget.locatie) _toonLocatie();
    if (oud.gereden != widget.gereden) _tekenGereden();
    if (oud.navigeert != widget.navigeert) _zetRand();
    if (widget.volg != null && oud.volg != widget.volg) _volg();
    if (oud.verkeer != widget.verkeer ||
        oud.toonVertraging != widget.toonVertraging) {
      _tekenVerkeer();
    }
    if (oud.routes != widget.routes ||
        oud.gekozen != widget.gekozen ||
        // Het scherm bouwt deze lijst elke keer opnieuw; op inhoud vergelijken,
        // anders worden de cirkels bij elke rebuild vervangen.
        !listEquals(oud.punten, widget.punten) ||
        oud.gevonden != widget.gevonden ||
        oud.beeldVersie != widget.beeldVersie) {
      _teken();
    }
  }

  Future<void> _stijlGeladen() async {
    final c = _controller!;
    // De cirkels van de punten zijn annotaties; hun laag bestaat al. De routelijnen
    // moeten daar ónder, anders verdwijnt een punt achter zijn eigen route.
    final onder = c.circleManager?.layerIds.firstOrNull;
    await c.addGeoJsonSource(_verkeerBron, _leeg);
    await c.addGeoJsonSource(_routeBron, _leeg);
    await c.addGeoJsonSource(_aansluitBron, _leeg);
    await _verkeerLagen(c);
    // Alternatieven grijs en onderop; de gekozen route blauw met een witte rand.
    await c.addLineLayer(
      _routeBron,
      'route-alt',
      const LineLayerProperties(
        lineColor: '#78909c',
        lineWidth: 5,
        lineOpacity: 0.8,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'gekozen'],
        false,
      ],
    );
    await c.addLineLayer(
      _routeBron,
      'route-rand',
      const LineLayerProperties(
        lineColor: '#ffffff',
        lineWidth: 9,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'gekozen'],
        true,
      ],
      enableInteraction: false,
    );
    await c.addLineLayer(
      _routeBron,
      'route',
      const LineLayerProperties(
        lineColor: '#1565c0',
        lineWidth: 6,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: [
        '==',
        ['get', 'gekozen'],
        true,
      ],
    );
    await c.addGeoJsonSource(_geredenBron, _leeg);
    await c.addLineLayer(
      _geredenBron,
      'gereden',
      const LineLayerProperties(
        lineColor: '#9e9e9e',
        lineWidth: 6,
        lineCap: 'round',
        lineJoin: 'round',
      ),
      enableInteraction: false,
    );
    // Van waar je klikte naar waar de route de weg oppakt: Valhalla legt een punt
    // naast de weg op de dichtstbijzijnde weg, en zonder dit lijntje lijkt de
    // route dan zomaar ergens anders te beginnen.
    await c.addLineLayer(
      _aansluitBron,
      'aansluiting',
      const LineLayerProperties(
        lineColor: '#546e7a',
        lineWidth: 3,
        lineDasharray: [0.5, 2],
        lineCap: 'round',
      ),
      enableInteraction: false,
      belowLayerId: onder,
    );
    _stijlKlaar = true;
    _cirkelIndex.clear();
    _ingepast = 0;
    await _tekenVerkeer();
    await _tekenGereden();
    await _toonLocatie();
    await _teken();
  }

  Future<void> _tekenGereden() async {
    final c = _controller;
    if (c == null || !_stijlKlaar) return;
    final lijn = widget.gereden;
    await c.setGeoJsonSource(_geredenBron, {
      'type': 'FeatureCollection',
      'features': [
        if (lijn != null && lijn.length > 1)
          {
            'type': 'Feature',
            'properties': <String, dynamic>{},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final p in lijn) [p.longitude, p.latitude],
              ],
            },
          },
      ],
    });
  }

  /// Meerijden: je plek op ongeveer tweederde van de hoogte, zodat je ziet wat
  /// er vóór je ligt.
  Future<void> _zetRand() async {
    final c = _controller;
    if (c == null) return;
    final hoogte = MediaQuery.sizeOf(context).height;
    await c.updateContentInsets(
      widget.navigeert ? EdgeInsets.only(top: hoogte * 0.35) : EdgeInsets.zero,
      // Niet geanimeerd: de eerstvolgende easeCamera zou die animatie meteen
      // afbreken, en dan blijft de rand op nul hangen.
      false,
    );
    if (!widget.navigeert) {
      final nu = c.cameraPosition;
      if (nu != null) {
        await c.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: nu.target, zoom: nu.zoom),
          ),
        );
      }
    }
  }

  Future<void> _volg() async {
    final volg = widget.volg, c = _controller;
    if (volg == null || c == null) return;
    // Langzaam dichtbij, op de snelweg verder vooruit kijken.
    final zoom = (17.5 - volg.snelheid * 0.1).clamp(14.5, 17.0);
    await c.easeCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: volg.punt,
          zoom: zoom,
          bearing: volg.koers,
          tilt: 50,
        ),
      ),
      // Ongeveer de tijd tot de volgende fix, en lineair: zo glijdt de kaart
      // zonder bij elke fix op te trekken en af te remmen.
      duration: const Duration(milliseconds: 1000),
      interpolation: CameraAnimationInterpolation.linear,
    );
  }

  /// Het puntje komt van onze eigen bron (ManualLocationSource), niet van de
  /// plugin: zo is het op het web en op Android hetzelfde, en kan de navigatie
  /// er later dezelfde fixes voor gebruiken.
  Future<void> _toonLocatie() async {
    final c = _controller, fix = widget.locatie;
    if (c == null || fix == null) return;
    await c.updateManualLocation(
      ManualLocationUpdate(
        target: fix.punt,
        horizontalAccuracy: fix.nauwkeurigheid,
        bearing: fix.koers,
        speed: fix.snelheid,
        timestamp: fix.tijd,
      ),
    );
  }

  /// Onder de routes, zodat een route over een file heen leesbaar blijft. Een
  /// afsluiting is rood met witte streepjes, werk oranje gestreept, files rood en
  /// langzaam verkeer oranje. Pas vanaf een zoom waarop je wegen onderscheidt:
  /// landelijk zijn het er honderden.
  Future<void> _verkeerLagen(MapLibreMapController c) async {
    List<Object> breedte(double laag, double hoog) => [
      'interpolate',
      ['linear'],
      ['zoom'],
      8,
      laag,
      15,
      hoog,
    ];
    List<Object> soort(List<String> soorten) => [
      'in',
      ['get', 'soort'],
      ['literal', soorten],
    ];
    await c.addLineLayer(
      _verkeerBron,
      'verkeer-traag',
      LineLayerProperties(
        lineColor: [
          'match',
          ['get', 'soort'],
          'file',
          '#c62828',
          '#ef6c00',
        ],
        lineWidth: breedte(2.5, 7),
        // Landelijk alleen de files; langzaam verkeer komt er vanaf zoom 9 bij.
        lineOpacity: [
          'interpolate',
          ['linear'],
          ['zoom'],
          8,
          [
            'match',
            ['get', 'soort'],
            'file',
            0.85,
            0,
          ],
          9.5,
          0.85,
        ],
        lineCap: 'round',
        lineJoin: 'round',
      ),
      filter: soort(['traag', 'file']),
      minzoom: 7,
    );
    await c.addLineLayer(
      _verkeerBron,
      'verkeer-werk',
      LineLayerProperties(
        lineColor: '#f9a825',
        lineWidth: breedte(2.5, 7),
        lineDasharray: const [1.5, 1],
      ),
      filter: soort(['werk']),
      minzoom: 9,
    );
    await c.addLineLayer(
      _verkeerBron,
      'verkeer-dicht',
      LineLayerProperties(
        lineColor: '#d32f2f',
        lineWidth: breedte(3, 8),
        lineCap: 'round',
      ),
      filter: soort(['dicht']),
      minzoom: 9,
    );
    await c.addLineLayer(
      _verkeerBron,
      'verkeer-dicht-streep',
      LineLayerProperties(
        lineColor: '#ffffff',
        lineWidth: breedte(1, 3),
        lineDasharray: const [1, 1.5],
      ),
      filter: soort(['dicht']),
      minzoom: 9,
      enableInteraction: false,
    );
    // Een lijn van een paar pixels raak je met een vinger niet: een brede,
    // vrijwel onzichtbare lijn eroverheen vangt de tik. Een fractie zichtbaar
    // in plaats van 0, zodat MapLibre hem zeker meetelt bij een tik.
    await c.addLineLayer(
      _verkeerBron,
      'verkeer-raak',
      const LineLayerProperties(
        lineColor: '#000000',
        lineWidth: 20,
        lineOpacity: 0.01,
      ),
      minzoom: 9,
    );
    // Ongevallen, pechgevallen en voorwerpen op de weg: punten, bovenop de
    // lijnen. Met een ruime, vrijwel onzichtbare cirkel eromheen voor de tik.
    await c.addCircleLayer(
      _verkeerBron,
      'verkeer-melding',
      const CircleLayerProperties(
        circleRadius: [
          'interpolate',
          ['linear'],
          ['zoom'],
          8,
          4,
          14,
          8,
        ],
        circleColor: [
          'match',
          ['get', 'soort'],
          'ongeval',
          '#c62828',
          'pech',
          '#ef6c00',
          '#f9a825',
        ],
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ),
      filter: soort(['ongeval', 'pech', 'obstakel']),
      minzoom: 8,
    );
    await c.addCircleLayer(
      _verkeerBron,
      'verkeer-melding-raak',
      const CircleLayerProperties(
        circleRadius: 18,
        circleColor: '#000000',
        circleOpacity: 0.01,
      ),
      filter: soort(['ongeval', 'pech', 'obstakel']),
      minzoom: 8,
    );
  }

  Future<void> _tekenVerkeer() async {
    final c = _controller;
    if (c == null || !_stijlKlaar) return;
    final features = [
      for (final feature in (widget.verkeer?['features'] as List? ?? const []))
        if (feature is Map<String, dynamic> &&
            (widget.toonVertraging ||
                !const {
                  'traag',
                  'file',
                }.contains((feature['properties'] as Map?)?['soort'])))
          feature,
    ];
    _verkeerInfo = {
      for (final feature in features)
        '${feature['id']}': (feature['properties'] as Map)
            .cast<String, dynamic>(),
    };
    await c.setGeoJsonSource(_verkeerBron, {
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  static const _leeg = {'type': 'FeatureCollection', 'features': <dynamic>[]};

  Future<void> _teken() async {
    final c = _controller;
    if (c == null || !_stijlKlaar) return;
    // Twee updates kort na elkaar: alleen de laatste mag cirkels neerzetten, anders
    // staan ze er dubbel.
    final volgnummer = ++_tekenVolgnummer;
    await c.setGeoJsonSource(_routeBron, {
      'type': 'FeatureCollection',
      'features': [
        for (final (i, route) in widget.routes.indexed)
          {
            'type': 'Feature',
            'id': i,
            'properties': {'gekozen': i == widget.gekozen, 'index': i},
            'geometry': {
              'type': 'LineString',
              'coordinates': [
                for (final p in route.punten) [p.longitude, p.latitude],
              ],
            },
          },
      ],
    });
    final route = widget.routes.isEmpty
        ? null
        : widget.routes[widget.gekozen.clamp(0, widget.routes.length - 1)];
    final begin = widget.punten.first?.punt, eind = widget.punten.last?.punt;
    await c.setGeoJsonSource(_aansluitBron, {
      'type': 'FeatureCollection',
      'features': [
        if (route != null && route.punten.isNotEmpty)
          for (final (klik, weg) in [
            (begin, route.punten.first),
            (eind, route.punten.last),
          ])
            if (klik != null && meters(klik, weg) > _minAansluiting)
              {
                'type': 'Feature',
                'properties': <String, dynamic>{},
                'geometry': {
                  'type': 'LineString',
                  'coordinates': [
                    [klik.longitude, klik.latitude],
                    [weg.longitude, weg.latitude],
                  ],
                },
              },
      ],
    });
    await c.clearCircles();
    _cirkelIndex.clear();
    if (volgnummer != _tekenVolgnummer) return;
    final laatste = widget.punten.length - 1;
    for (final (i, plaats) in widget.punten.indexed) {
      if (plaats == null) continue;
      final cirkel = await c.addCircle(
        CircleOptions(
          geometry: plaats.punt,
          circleRadius: 9,
          circleColor: i == 0
              ? '#2e7d32'
              : (i == laatste ? '#c62828' : '#ef6c00'),
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2.5,
          draggable: true,
        ),
      );
      _cirkelIndex[cirkel.id] = i;
    }
    // In het zoekscherm; in het routescherm is dezelfde plaats al een routepunt.
    final gevonden = widget.gevonden;
    if (gevonden != null && !widget.punten.contains(gevonden)) {
      await c.addCircle(
        CircleOptions(
          geometry: gevonden.punt,
          circleRadius: 9,
          circleColor: '#1565c0',
          circleStrokeColor: '#ffffff',
          circleStrokeWidth: 2.5,
        ),
      );
    }
    if (widget.beeldVersie != _ingepast) {
      _ingepast = widget.beeldVersie;
      await _brengInBeeld();
    }
  }

  void _versleept(
    Point<double> _,
    LatLng _,
    LatLng huidig,
    LatLng _,
    String id,
    Annotation? _,
    DragEventType soort,
  ) {
    // De plugin verschuift de cirkel zelf; pas bij het loslaten is er een nieuw
    // punt om een route voor te rekenen.
    final index = _cirkelIndex[id];
    if (soort == DragEventType.end && index != null) {
      widget.onPuntVersleept(index, huidig);
    }
  }

  Future<void> _brengInBeeld() async {
    final alle = [
      for (final route in widget.routes) ...route.punten,
      for (final plaats in widget.punten) ?plaats?.punt,
      if (widget.routes.isEmpty) ?widget.gevonden?.punt,
    ];
    if (alle.isEmpty) return;
    if (alle.length == 1) {
      await _controller!.animateCamera(
        CameraUpdate.newLatLngZoom(alle.first, 14),
      );
      return;
    }
    var zuid = 90.0, noord = -90.0, west = 180.0, oost = -180.0;
    for (final p in alle) {
      zuid = min(zuid, p.latitude);
      noord = max(noord, p.latitude);
      west = min(west, p.longitude);
      oost = max(oost, p.longitude);
    }
    await _controller!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(zuid, west),
          northeast: LatLng(noord, oost),
        ),
        left: widget.rand.left + 40,
        top: widget.rand.top + 40,
        // Rechts staan de knoppen (laag, kompas, instellingen).
        right: widget.rand.right + 72,
        bottom: widget.rand.bottom + 40,
      ),
    );
  }

  void _featureGetikt(
    Point<double> scherm,
    LatLng _,
    String id,
    String laag,
    Annotation? _,
  ) {
    if (laag.startsWith('verkeer-')) {
      final info = _verkeerInfo[id];
      if (info != null) widget.onVerkeerGetikt?.call(_logisch(scherm), info);
      return;
    }
    if (!_lagen.contains(laag)) return;
    final index = int.tryParse(id);
    if (index != null && index < widget.routes.length) {
      widget.onRouteGekozen(index);
    }
  }

  /// De plugin geeft schermpunten op Android in fysieke pixels
  /// (Projection.toScreenLocation), op het web in CSS-pixels. Flutter rekent in
  /// logische pixels: zonder deze omrekening kwam het puntmenu op een scherm met
  /// dichtheid 3 ver buiten beeld, en werd het naar rechtsonder geduwd.
  Point<double> _logisch(Point<double> scherm) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return scherm;
    }
    final dichtheid = MediaQuery.devicePixelRatioOf(context);
    return Point(scherm.x / dichtheid, scherm.y / dichtheid);
  }

  @override
  Widget build(BuildContext context) => Listener(
    // Op Android komen aanrakingen van de kaart hier langs; op het web gaan ze
    // naar het HTML-element van de kaart, daar vangt muis_web.dart ze.
    onPointerDown: (_) => widget.onZelfBewogen?.call(),
    child: _kaart(),
  );

  Widget _kaart() => MapLibreMap(
    styleString: widget.stijlUrl,
    initialCameraPosition: widget.start,
    trackCameraPosition: true,
    // Het kompas van de plugin staat rechtsboven, precies onder onze eigen knoppen;
    // het scherm heeft er een eigen knop voor.
    compassEnabled: false,
    myLocationEnabled: widget.locatie != null,
    locationSource: const ManualLocationSource(),
    attributionButtonPosition: AttributionButtonPosition.bottomRight,
    onMapCreated: (controller) {
      _controller = controller;
      controller.onFeatureTapped.add(_featureGetikt);
      controller.onFeatureDrag.add(_versleept);
      widget.onController?.call(controller);
    },
    onStyleLoadedCallback: _stijlGeladen,
    onMapLongClick: (scherm, punt) =>
        widget.onLangIngedrukt(_logisch(scherm), punt),
  );
}
