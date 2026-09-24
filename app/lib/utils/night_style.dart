import 'dart:math';

/// A dark version of a MapLibre style (made for OSM Bright), for when the phone
/// is in dark mode. The same map, the same layers: only the colors are
/// converted, each according to what it is.
///
/// - Areas (land, water, forest, buildings) become dark; their hue stays, so
///   water stays blue and forest green. The lighter by day, the darker now.
/// - Roads become lighter than the background, in their own color: the
///   motorway stays orange, a street light grey. The casing around it becomes
///   darker than the road itself.
/// - Text becomes light, with a dark halo around it (also where the style had
///   none: dark letters without a halo read well by day, not at night).
/// - Text *on* an image (the shield with A12 on it) stays as it is: the image
///   itself doesn't change, so black on white stays the most legible.
///
/// Anything that isn't a color, or can't be parsed, stays as it is.
Map<String, dynamic> nightStyle(Map<String, dynamic> style) {
  final layers = [
    for (final layer in (style['layers'] as List? ?? const []))
      if (layer is Map) _layer(layer.cast<String, dynamic>()) else layer,
  ];
  return {...style, 'layers': layers, 'name': '${style['name'] ?? ''} (night)'};
}

Map<String, dynamic> _layer(Map<String, dynamic> layer) {
  final paint = (layer['paint'] as Map?)?.cast<String, dynamic>();
  if (paint == null || _isImageLayer(layer)) return layer;
  final id = '${layer['id']}';
  final newValue = <String, dynamic>{
    for (final MapEntry(:key, :value) in paint.entries)
      key: switch (key) {
        'background-color' ||
        'fill-color' ||
        'fill-outline-color' ||
        'fill-extrusion-color' => _colors(value, _area),
        'line-color' when id.startsWith('waterway') => _colors(value, _water),
        'line-color' when id.contains('casing') => _colors(value, _casing),
        'line-color' => _colors(value, _line),
        'text-color' || 'icon-color' => _colors(value, _text),
        'text-halo-color' || 'icon-halo-color' => _colors(value, _halo),
        _ => value,
      },
  };
  if (layer['type'] == 'symbol' && !paint.containsKey('text-halo-color')) {
    newValue['text-halo-color'] = 'hsla(0, 0%, 5%, 0.8)';
    newValue.putIfAbsent('text-halo-width', () => 1.2);
  }
  return {...layer, 'paint': newValue};
}

/// A symbol layer whose text sits on the image, like a road number shield. If
/// the text is next to it (a POI with its name below), the layer has a
/// `text-offset`.
bool _isImageLayer(Map<String, dynamic> layer) {
  final layout = layer['layout'];
  return layer['type'] == 'symbol' &&
      layout is Map &&
      layout.containsKey('icon-image') &&
      layout.containsKey('text-field') &&
      !layout.containsKey('text-offset');
}

typedef Hsla = ({double h, double s, double l, double a});

// Each conversion picks a new lightness, and keeps the daytime chroma, times
// [strength]. Not the saturation: a pale color often has 100% saturation in
// HSL (#fea, the pale yellow of a provincial road), and that would turn bright
// yellow at a lower lightness.
Hsla _shift(Hsla k, double l, double strength) {
  final chroma = (1 - (2 * k.l - 1).abs()) * k.s * strength;
  final space = 1 - (2 * l - 1).abs();
  return (
    h: k.h,
    s: space <= 0 ? 0 : (chroma / space).clamp(0, 1),
    l: l,
    a: k.a,
  );
}

Hsla _area(Hsla k) => _shift(k, 0.24 - 0.17 * k.l, 0.9);
// Waterways as lines: slightly lighter than water as an area, otherwise a
// ditch disappears into the land.
Hsla _water(Hsla k) => _shift(k, 0.30 - 0.14 * k.l, 1.0);
Hsla _line(Hsla k) => _shift(k, 0.16 + 0.30 * k.l, 1.4);
Hsla _casing(Hsla k) => _shift(k, 0.12 + 0.18 * k.l, 1.0);
Hsla _text(Hsla k) => _shift(k, 0.95 - 0.55 * k.l, 1.0);
Hsla _halo(Hsla k) => _shift(k, 0.06, 0.3);

/// Converts every color in [value]: a color itself, or a color somewhere in
/// `stops` or an expression.
Object? _colors(Object? value, Hsla Function(Hsla) convert) {
  if (value is String) {
    final color = parseColor(value);
    return color == null ? value : writeColor(convert(color));
  }
  if (value is List) return [for (final w in value) _colors(w, convert)];
  if (value is Map) {
    return {
      for (final MapEntry(:key, :value) in value.entries)
        key: _colors(value, convert),
    };
  }
  return value;
}

final _hsl = RegExp(
  r'^hsla?\(\s*([\d.]+)\s*,\s*([\d.]+)%\s*,\s*([\d.]+)%\s*(?:,\s*([\d.]+)\s*)?\)$',
);
final _rgb = RegExp(
  r'^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$',
);
final _hex = RegExp(r'^#([0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$');

/// A CSS color as in MapLibre styles (`#rgb`, `#rrggbb`, `rgb[a](...)`,
/// `hsl[a](...)`) as HSLA with everything between 0 and 1 (hue in degrees).
/// Null for anything else, like a name or a field name in an expression.
Hsla? parseColor(String text) {
  final t = text.trim();
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
    int part(int i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    r = part(0) / 255;
    g = part(1) / 255;
    b = part(2) / 255;
    if (hex.length == 8) a = part(3) / 255;
  } else {
    return null;
  }
  final high = max(r, max(g, b)), low = min(r, min(g, b));
  final l = (high + low) / 2;
  if (high == low) return (h: 0, s: 0, l: l, a: a);
  final d = high - low;
  final s = l > 0.5 ? d / (2 - high - low) : d / (high + low);
  final h = high == r
      ? (g - b) / d + (g < b ? 6 : 0)
      : high == g
      ? (b - r) / d + 2
      : (r - g) / d + 4;
  return (h: h * 60, s: s, l: l, a: a);
}

String writeColor(Hsla k) {
  String percent(double v) => '${(v.clamp(0, 1) * 100).toStringAsFixed(1)}%';
  return 'hsla(${k.h.toStringAsFixed(1)}, ${percent(k.s)}, ${percent(k.l)}, '
      '${k.a.clamp(0, 1).toStringAsFixed(2)})';
}
