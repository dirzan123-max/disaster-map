import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

/// 1つの国・地域。tool/build_countries.py が生成した同梱データから読む。
class Country {
  const Country({
    required this.code,
    required this.nameJa,
    required this.nameEn,
    required this.west,
    required this.south,
    required this.east,
    required this.north,
    required this.rings,
    this.aliases = const [],
  });

  /// ISO 3166-1 alpha-2（一部の係争地域のみ 3 文字）。
  final String code;
  final String nameJa;
  final String nameEn;

  /// 正式名称以外のよくある呼び名（「アメリカ」「韓国」など）。検索でのみ使う。
  final List<String> aliases;

  final double west;
  final double south;
  final double east;
  final double north;

  /// 国境の外周。[経度, 緯度, 経度, 緯度, ...] の平坦な並びで持つ。
  /// 判定にしか使わないため、地図に描ける精度は持たせていない。
  final List<Float64List> rings;

  double get boxArea => (east - west).abs() * (north - south).abs();

  bool containsInBox(double latitude, double longitude, {double padding = 0}) =>
      longitude >= west - padding &&
      longitude <= east + padding &&
      latitude >= south - padding &&
      latitude <= north + padding;

  /// 国境の内側かどうか（交差数判定）。
  bool contains(double latitude, double longitude) {
    if (!containsInBox(latitude, longitude)) return false;
    var inside = false;
    for (final ring in rings) {
      final count = ring.length ~/ 2;
      var j = count - 1;
      for (var i = 0; i < count; i++) {
        final xi = ring[i * 2];
        final yi = ring[i * 2 + 1];
        final xj = ring[j * 2];
        final yj = ring[j * 2 + 1];
        if ((yi > latitude) != (yj > latitude) &&
            longitude < (xj - xi) * (latitude - yi) / (yj - yi) + xi) {
          inside = !inside;
        }
        j = i;
      }
    }
    return inside;
  }

  /// 国境までのおおよその距離（km）。海上のイベントを近い国に寄せるために使う。
  double distanceKm(double latitude, double longitude) {
    final scale = math.cos(latitude * math.pi / 180).abs().clamp(0.05, 1.0);
    var best = double.infinity;
    for (final ring in rings) {
      for (var i = 0; i < ring.length; i += 2) {
        final dx = (ring[i] - longitude) * scale;
        final dy = ring[i + 1] - latitude;
        final squared = dx * dx + dy * dy;
        if (squared < best) best = squared;
      }
    }
    return math.sqrt(best) * 111.0;
  }
}

/// 国での絞り込みと、英語の地名の和訳に使う索引。
class CountryIndex {
  const CountryIndex(this.byCode);

  final Map<String, Country> byCode;

  static const CountryIndex empty = CountryIndex({});

  /// 海上のイベントをどこまで近くの国として扱うか。
  /// 「日本の東方沖」のような震源を日本の絞り込みで拾えるようにする。
  static const double offshoreLimitKm = 300;

  Iterable<Country> get countries => byCode.values;

  Country? operator [](String code) => byCode[code];

  /// 座標がどの国かを判定する。陸上なら国境の内側判定、
  /// 海上なら [offshoreLimitKm] 以内で最も近い国を返す。該当なしは null。
  Country? resolve(double latitude, double longitude) {
    Country? best;
    for (final country in byCode.values) {
      if (!country.contains(latitude, longitude)) continue;
      // 飛び地の重なりでは、範囲の小さい方（より具体的な国）を採る。
      if (best == null || country.boxArea < best.boxArea) best = country;
    }
    if (best != null) return best;

    var nearestKm = offshoreLimitKm;
    for (final country in byCode.values) {
      // 明らかに遠い国の頂点を全部見ないよう、外接矩形で足切りする。
      if (!country.containsInBox(latitude, longitude, padding: 4)) continue;
      final distance = country.distanceKm(latitude, longitude);
      if (distance < nearestKm) {
        nearestKm = distance;
        best = country;
      }
    }
    return best;
  }

  /// 名前・コードでの検索。ひらがなで打っても片仮名の国名に当たるようにする。
  List<Country> search(String query) {
    final keyword = _normalize(query);
    if (keyword.isEmpty) {
      return countries.toList()..sort(_byJapaneseName);
    }
    final hits = countries.where((country) {
      return _normalize(country.nameJa).contains(keyword) ||
          _normalize(country.nameEn).contains(keyword) ||
          country.aliases.any((alias) => _normalize(alias).contains(keyword)) ||
          country.code.toLowerCase() == keyword;
    }).toList();
    // 前方一致を先に出す（「にほん」で日本が先頭に来るように）。
    int rank(Country country) {
      if (country.code.toLowerCase() == keyword) return 0;
      final names = [country.nameJa, country.nameEn, ...country.aliases];
      return names.any((name) => _normalize(name).startsWith(keyword)) ? 1 : 2;
    }

    hits.sort((a, b) {
      final difference = rank(a) - rank(b);
      return difference != 0 ? difference : _byJapaneseName(a, b);
    });
    return hits;
  }

  static int _byJapaneseName(Country a, Country b) =>
      a.nameJa.compareTo(b.nameJa);

  /// 検索語の揺れを吸収する。ひらがなを片仮名に寄せ、英字は小文字に揃える。
  static String _normalize(String value) {
    final buffer = StringBuffer();
    for (final unit in value.trim().toLowerCase().runes) {
      // ひらがな(3041-3096) を同じ並びの片仮名へ 0x60 ずらす。
      buffer.writeCharCode(
        unit >= 0x3041 && unit <= 0x3096 ? unit + 0x60 : unit,
      );
    }
    return buffer.toString();
  }

  /// 英語名 -> 日本語名。世界版の英語テキストを和訳するときに引く。
  Map<String, String> get japaneseNameByEnglish => {
        for (final country in countries) country.nameEn: country.nameJa,
      };

  static CountryIndex parse(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return empty;

    final countries = <String, Country>{};
    decoded.forEach((code, value) {
      if (value is! Map<String, dynamic>) return;
      final box = (value['bbox'] as List?)?.cast<num>();
      if (box == null || box.length < 4) return;
      countries[code] = Country(
        code: code,
        nameJa: value['ja'] as String? ?? code,
        nameEn: value['en'] as String? ?? code,
        west: box[0].toDouble(),
        south: box[1].toDouble(),
        east: box[2].toDouble(),
        north: box[3].toDouble(),
        aliases: [
          for (final alias in (value['alias'] as List? ?? const []))
            alias.toString(),
        ],
        rings: [
          for (final ring in (value['rings'] as List? ?? const []))
            if (ring is List)
              Float64List.fromList(
                [for (final coordinate in ring) (coordinate as num).toDouble()],
              ),
        ],
      );
    });
    return CountryIndex(countries);
  }
}
