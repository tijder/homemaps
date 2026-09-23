import 'dart:math';

/// Een donkere versie van een MapLibre-stijl (gemaakt voor OSM Bright), voor
/// als de telefoon op donker staat. Dezelfde kaart, dezelfde lagen: alleen de
/// kleuren worden omgezet, elk naar wat het is.
///
/// - Vlakken (land, water, bos, gebouwen) worden donker; hun tint blijft, zodat
///   water blauw en bos groen blijft. Hoe lichter overdag, hoe donkerder nu.
/// - Wegen worden lichter dan de ondergrond, in hun eigen kleur: de snelweg
///   blijft oranje, een straat lichtgrijs. De rand eromheen wordt donkerder dan
///   de weg zelf.
/// - Tekst wordt licht, met een donkere rand eromheen (ook waar de stijl er
///   geen had: donkere letters zonder rand lezen overdag goed, 's nachts niet).
/// - Tekst óp een plaatje (het bordje met A12 erop) blijft zoals hij is: het
///   plaatje zelf verandert niet, dus zwart op wit blijft het best leesbaar.
///
/// Wat geen kleur is, of niet te lezen, blijft zoals het is.
Map<String, dynamic> nachtstijl(Map<String, dynamic> stijl) {
  final lagen = [
    for (final laag in (stijl['layers'] as List? ?? const []))
      if (laag is Map) _laag(laag.cast<String, dynamic>()) else laag,
  ];
  return {...stijl, 'layers': lagen, 'name': '${stijl['name'] ?? ''} (nacht)'};
}

Map<String, dynamic> _laag(Map<String, dynamic> laag) {
  final paint = (laag['paint'] as Map?)?.cast<String, dynamic>();
  if (paint == null || _opPlaatje(laag)) return laag;
  final id = '${laag['id']}';
  final nieuw = <String, dynamic>{
    for (final MapEntry(:key, :value) in paint.entries)
      key: switch (key) {
        'background-color' ||
        'fill-color' ||
        'fill-outline-color' ||
        'fill-extrusion-color' => _kleuren(value, _vlak),
        'line-color' when id.startsWith('waterway') => _kleuren(value, _water),
        'line-color' when id.contains('casing') => _kleuren(value, _rand),
        'line-color' => _kleuren(value, _lijn),
        'text-color' || 'icon-color' => _kleuren(value, _tekst),
        'text-halo-color' || 'icon-halo-color' => _kleuren(value, _halo),
        _ => value,
      },
  };
  if (laag['type'] == 'symbol' && !paint.containsKey('text-halo-color')) {
    nieuw['text-halo-color'] = 'hsla(0, 0%, 5%, 0.8)';
    nieuw.putIfAbsent('text-halo-width', () => 1.2);
  }
  return {...laag, 'paint': nieuw};
}

/// Een symboollaag waarvan de tekst op het plaatje staat, zoals een
/// wegnummerbordje. Staat de tekst ernaast (een POI met zijn naam eronder),
/// dan heeft de laag een `text-offset`.
bool _opPlaatje(Map<String, dynamic> laag) {
  final layout = laag['layout'];
  return laag['type'] == 'symbol' &&
      layout is Map &&
      layout.containsKey('icon-image') &&
      layout.containsKey('text-field') &&
      !layout.containsKey('text-offset');
}

typedef Hsla = ({double h, double s, double l, double a});

// Elke omzetting kiest een nieuwe lichtheid, en houdt de kleurkracht (chroma)
// van overdag, maal [kracht]. Niet de verzadiging: een bleke kleur heeft in HSL
// vaak 100% verzadiging (#fea, het bleekgeel van een provinciale weg), en die
// zou bij een lagere lichtheid knalgeel worden.
Hsla _om(Hsla k, double l, double kracht) {
  final chroma = (1 - (2 * k.l - 1).abs()) * k.s * kracht;
  final ruimte = 1 - (2 * l - 1).abs();
  return (
    h: k.h,
    s: ruimte <= 0 ? 0 : (chroma / ruimte).clamp(0, 1),
    l: l,
    a: k.a,
  );
}

Hsla _vlak(Hsla k) => _om(k, 0.24 - 0.17 * k.l, 0.9);
// Waterlopen als lijn: iets lichter dan het water als vlak, anders verdwijnt
// een sloot in het land.
Hsla _water(Hsla k) => _om(k, 0.30 - 0.14 * k.l, 1.0);
Hsla _lijn(Hsla k) => _om(k, 0.16 + 0.30 * k.l, 1.4);
Hsla _rand(Hsla k) => _om(k, 0.12 + 0.18 * k.l, 1.0);
Hsla _tekst(Hsla k) => _om(k, 0.95 - 0.55 * k.l, 1.0);
Hsla _halo(Hsla k) => _om(k, 0.06, 0.3);

/// Zet elke kleur in [waarde] om: een kleur zelf, of een kleur ergens in
/// `stops` of een expressie.
Object? _kleuren(Object? waarde, Hsla Function(Hsla) om) {
  if (waarde is String) {
    final kleur = leesKleur(waarde);
    return kleur == null ? waarde : schrijfKleur(om(kleur));
  }
  if (waarde is List) return [for (final w in waarde) _kleuren(w, om)];
  if (waarde is Map) {
    return {
      for (final MapEntry(:key, :value) in waarde.entries)
        key: _kleuren(value, om),
    };
  }
  return waarde;
}

final _hsl = RegExp(
  r'^hsla?\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*(?:,\s*([\d.]+)\s*)?\)$',
);
final _rgb = RegExp(
  r'^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$',
);
final _hex = RegExp(r'^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

/// Een CSS-kleur zoals in MapLibre-stijlen (`#rgb`, `#rrggbb`, `rgb[a](...)`,
/// `hsl[a](...)`) als HSLA met alles tussen 0 en 1 (tint in graden). Null voor
/// iets anders, zoals een naam of een veldnaam in een expressie.
Hsla? leesKleur(String tekst) {
  final t = tekst.trim();
  if (_hsl.firstMatch(t) case final m?) {
    return (
      h: double.parse(m[1]!),
      s: double.parse(m[2]!) / 100,
      l: double.parse(m[3]!) / 100,
      a: m[4] == null ? 1.0 : double.parse(m[4]!),
    );
  }
  double r, g, b, a = 1;
  if (_rgb.firstMatch(t) case final m?) {
    r = double.parse(m[1]!) / 255;
    g = double.parse(m[2]!) / 255;
    b = double.parse(m[3]!) / 255;
    if (m[4] != null) a = double.parse(m[4]!);
  } else if (_hex.firstMatch(t) case final m?) {
    var hex = m[1]!;
    if (hex.length <= 4) hex = hex.split('').map((c) => '$c$c').join();
    int deel(int i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    r = deel(0) / 255;
    g = deel(1) / 255;
    b = deel(2) / 255;
    if (hex.length == 8) a = deel(3) / 255;
  } else {
    return null;
  }
  final hoog = max(r, max(g, b)), laag = min(r, min(g, b));
  final l = (hoog + laag) / 2;
  if (hoog == laag) return (h: 0, s: 0, l: l, a: a);
  final d = hoog - laag;
  final s = l > 0.5 ? d / (2 - hoog - laag) : d / (hoog + laag);
  final h = hoog == r
      ? (g - b) / d + (g < b ? 6 : 0)
      : hoog == g
      ? (b - r) / d + 2
      : (r - g) / d + 4;
  return (h: h * 60, s: s, l: l, a: a);
}

String schrijfKleur(Hsla k) {
  String procent(double v) => '${(v.clamp(0, 1) * 100).toStringAsFixed(1)}%';
  return 'hsla(${k.h.toStringAsFixed(1)}, ${procent(k.s)}, ${procent(k.l)}, '
      '${k.a.clamp(0, 1).toStringAsFixed(2)})';
}
