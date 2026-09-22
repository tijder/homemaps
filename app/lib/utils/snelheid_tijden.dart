/// Maximumsnelheden die van het tijdstip afhangen (OSM `maxspeed:conditional`,
/// zoals "130 @ (19:00-06:00)" op de meeste snelwegen). Valhalla leest die tag
/// niet; de importer haalt de regels uit het OSM-bestand, per OSM-way.
class SnelheidTijden {
  const SnelheidTijden(this._ways);

  static const leeg = SnelheidTijden({});

  final Map<int, List<TijdRegel>> _ways;

  bool get isEmpty => _ways.isEmpty;

  /// Uit `/snelheid-tijden`: `{"ways": {"<id>": [[kmu, dagen, [[van, tot]]]]}}`.
  /// Wat er niet uitziet zoals verwacht, wordt overgeslagen.
  factory SnelheidTijden.uitJson(Map<String, dynamic>? json) {
    final uit = <int, List<TijdRegel>>{};
    final ways = json?['ways'];
    if (ways is! Map) return leeg;
    for (final MapEntry(:key, :value) in ways.entries) {
      final id = int.tryParse('$key');
      if (id == null || value is! List) continue;
      final regels = [for (final regel in value) ?TijdRegel.uitJson(regel)];
      if (regels.isNotEmpty) uit[id] = regels;
    }
    return SnelheidTijden(uit);
  }

  /// De limiet op [way] op [tijd]: die van de eerste regel die dan geldt, en
  /// anders [normaal].
  int? limietOp(int? way, int? normaal, DateTime tijd) {
    for (final regel in _ways[way] ?? const <TijdRegel>[]) {
      if (regel.geldt(tijd)) return regel.kmu;
    }
    return normaal;
  }
}

/// Eén regel: [kmu] op [dagen] (bitmasker, maandag = 1, zondag = 64) binnen
/// een van de [vensters] (minuten na middernacht). Een venster met van > tot
/// loopt over middernacht door: het begint op een van de [dagen] en eindigt de
/// ochtend erna.
class TijdRegel {
  const TijdRegel(this.kmu, this.dagen, this.vensters);

  final int kmu;
  final int dagen;
  final List<(int, int)> vensters;

  static TijdRegel? uitJson(Object? json) {
    if (json is! List || json.length != 3) return null;
    final [kmu, dagen, vensters] = json;
    if (kmu is! int || dagen is! int || vensters is! List) return null;
    final gelezen = <(int, int)>[];
    for (final venster in vensters) {
      if (venster case [final int van, final int tot]) gelezen.add((van, tot));
    }
    return gelezen.isEmpty ? null : TijdRegel(kmu, dagen, gelezen);
  }

  bool _op(int dag) => dagen & (1 << ((dag - 1) % 7)) != 0;

  bool geldt(DateTime tijd) {
    final minuut = tijd.hour * 60 + tijd.minute;
    final vandaag = tijd.weekday; // 1 = maandag
    final gisteren = vandaag == 1 ? 7 : vandaag - 1;
    for (final (van, tot) in vensters) {
      if (van <= tot) {
        if (_op(vandaag) && minuut >= van && minuut < tot) return true;
      } else if ((_op(vandaag) && minuut >= van) ||
          (_op(gisteren) && minuut < tot)) {
        return true;
      }
    }
    return false;
  }
}
