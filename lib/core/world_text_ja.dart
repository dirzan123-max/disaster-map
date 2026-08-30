/// 世界版の英語テキストを日本語にする。
///
/// USGS や NASA EONET は英語でしか配信していないため、
/// 「M 4.3 - 10 km SSE of Ocotito, Mexico」のような定型部分
/// （方角・単位・国名・米国の州名・災害の種類）を機械的に置き換える。
///
/// 都市名などの固有名詞は原文のまま残す。無理に音訳すると
/// 現地の報道や公式発表と突き合わせられなくなるため。
/// 原文は詳細画面の「原文を見る」から辿れる。
class WorldTextJa {
  const WorldTextJa(this.countryNameJa);

  /// 英語の国名 -> 日本語名。同梱の国データ（Natural Earth）から作る。
  final Map<String, String> countryNameJa;

  static const WorldTextJa withoutCountries = WorldTextJa({});

  /// 16方位の略号。USGS の震源表記で使われる。
  static const Map<String, String> _directions = {
    'N': '北',
    'NNE': '北北東',
    'NE': '北東',
    'ENE': '東北東',
    'E': '東',
    'ESE': '東南東',
    'SE': '南東',
    'SSE': '南南東',
    'S': '南',
    'SSW': '南南西',
    'SW': '南西',
    'WSW': '西南西',
    'W': '西',
    'WNW': '西北西',
    'NW': '北西',
    'NNW': '北北西',
  };

  /// 米国の州・準州の略号。USGS は国内の震源を略号で書く。
  static const Map<String, String> _usStates = {
    'AL': 'アラバマ州', 'AK': 'アラスカ州', 'AZ': 'アリゾナ州',
    'AR': 'アーカンソー州', 'CA': 'カリフォルニア州', 'CO': 'コロラド州',
    'CT': 'コネチカット州', 'DE': 'デラウェア州', 'FL': 'フロリダ州',
    'GA': 'ジョージア州', 'HI': 'ハワイ州', 'ID': 'アイダホ州',
    'IL': 'イリノイ州', 'IN': 'インディアナ州', 'IA': 'アイオワ州',
    'KS': 'カンザス州', 'KY': 'ケンタッキー州', 'LA': 'ルイジアナ州',
    'ME': 'メイン州', 'MD': 'メリーランド州', 'MA': 'マサチューセッツ州',
    'MI': 'ミシガン州', 'MN': 'ミネソタ州', 'MS': 'ミシシッピ州',
    'MO': 'ミズーリ州', 'MT': 'モンタナ州', 'NE': 'ネブラスカ州',
    'NV': 'ネバダ州', 'NH': 'ニューハンプシャー州', 'NJ': 'ニュージャージー州',
    'NM': 'ニューメキシコ州', 'NY': 'ニューヨーク州', 'NC': 'ノースカロライナ州',
    'ND': 'ノースダコタ州', 'OH': 'オハイオ州', 'OK': 'オクラホマ州',
    'OR': 'オレゴン州', 'PA': 'ペンシルベニア州', 'RI': 'ロードアイランド州',
    'SC': 'サウスカロライナ州', 'SD': 'サウスダコタ州', 'TN': 'テネシー州',
    'TX': 'テキサス州', 'UT': 'ユタ州', 'VT': 'バーモント州',
    'VA': 'バージニア州', 'WA': 'ワシントン州', 'WV': 'ウェストバージニア州',
    'WI': 'ウィスコンシン州', 'WY': 'ワイオミング州',
    'DC': 'ワシントンD.C.', 'PR': 'プエルトリコ', 'VI': '米領バージン諸島',
    'GU': 'グアム', 'MX': 'メキシコ',
  };

  /// 略号ではなく州名で書かれる場合（EONET の山火事など）。
  static const Map<String, String> _usStateNames = {
    'Alabama': 'アラバマ州', 'Alaska': 'アラスカ州', 'Arizona': 'アリゾナ州',
    'Arkansas': 'アーカンソー州', 'California': 'カリフォルニア州',
    'Colorado': 'コロラド州', 'Connecticut': 'コネチカット州',
    'Delaware': 'デラウェア州', 'Florida': 'フロリダ州',
    'Georgia': 'ジョージア州', 'Hawaii': 'ハワイ州', 'Idaho': 'アイダホ州',
    'Illinois': 'イリノイ州', 'Indiana': 'インディアナ州',
    'Iowa': 'アイオワ州', 'Kansas': 'カンザス州', 'Kentucky': 'ケンタッキー州',
    'Louisiana': 'ルイジアナ州', 'Maine': 'メイン州',
    'Maryland': 'メリーランド州', 'Massachusetts': 'マサチューセッツ州',
    'Michigan': 'ミシガン州', 'Minnesota': 'ミネソタ州',
    'Mississippi': 'ミシシッピ州', 'Missouri': 'ミズーリ州',
    'Montana': 'モンタナ州', 'Nebraska': 'ネブラスカ州',
    'Nevada': 'ネバダ州', 'New Hampshire': 'ニューハンプシャー州',
    'New Jersey': 'ニュージャージー州', 'New Mexico': 'ニューメキシコ州',
    'New York': 'ニューヨーク州', 'North Carolina': 'ノースカロライナ州',
    'North Dakota': 'ノースダコタ州', 'Ohio': 'オハイオ州',
    'Oklahoma': 'オクラホマ州', 'Oregon': 'オレゴン州',
    'Pennsylvania': 'ペンシルベニア州', 'Rhode Island': 'ロードアイランド州',
    'South Carolina': 'サウスカロライナ州', 'South Dakota': 'サウスダコタ州',
    'Tennessee': 'テネシー州', 'Texas': 'テキサス州', 'Utah': 'ユタ州',
    'Vermont': 'バーモント州', 'Virginia': 'バージニア州',
    'Washington': 'ワシントン州', 'West Virginia': 'ウェストバージニア州',
    'Wisconsin': 'ウィスコンシン州', 'Wyoming': 'ワイオミング州',
  };

  /// EONET のカテゴリ名。
  static const Map<String, String> _categories = {
    'Wildfires': '山火事',
    'Severe Storms': '暴風雨・熱帯低気圧',
    'Volcanoes': '火山',
    'Sea and Lake Ice': '海氷・湖氷',
    'Floods': '洪水',
    'Earthquakes': '地震',
    'Drought': '干ばつ',
    'Dust and Haze': '砂じん・煙霧',
    'Landslides': '地すべり',
    'Manmade': '人為的な事象',
    'Snow': '大雪',
    'Temperature Extremes': '異常気温',
    'Water Color': '水質の変化',
  };

  /// 現象の呼び名。EONET の見出しの先頭に付く。
  static const Map<String, String> _phenomena = {
    'Wildfire': '山火事',
    'Tropical Storm': '熱帯低気圧',
    'Tropical Depression': '熱帯低気圧',
    'Tropical Cyclone': '熱帯低気圧',
    'Super Typhoon': '猛烈な台風',
    'Hurricane': 'ハリケーン',
    'Typhoon': '台風',
    'Iceberg': '氷山',
    'Flood': '洪水',
    'Landslide': '地すべり',
    'Dust Storm': '砂じん嵐',
  };

  /// 観測値の単位。
  static const Map<String, String> _units = {
    'kts': 'ノット',
    'NM^2': '平方海里',
    'acres': 'エーカー',
  };

  static String category(String english) => _categories[english] ?? english;

  static String unit(String? english) =>
      english == null ? '' : (_units[english] ?? english);

  /// 「M 4.3 - 10 km SSE of Ocotito, Mexico」形式の見出しを訳す。
  String usgsTitle(String english) {
    final separator = english.indexOf(' - ');
    if (!english.startsWith('M ') || separator < 0) return place(english);
    final magnitude = english.substring(2, separator).trim();
    return 'M$magnitude ${place(english.substring(separator + 3))}';
  }

  /// USGS の震源地表記を訳す。
  ///
  /// 例: 「10 km SSE of Ocotito, Mexico」→「メキシコ Ocotito の南南東 10km」
  ///     「8km NW of The Geysers, CA」→「米国カリフォルニア州 The Geysers の北西 8km」
  String place(String english) {
    final text = english.trim();
    if (text.isEmpty) return text;

    final offset = RegExp(r'^(\d+(?:\.\d+)?)\s*km\s+([A-Z]{1,3})\s+of\s+(.+)$')
        .firstMatch(text);
    if (offset != null) {
      final direction = _directions[offset.group(2)!] ?? offset.group(2)!;
      final area = _areaName(offset.group(3)!);
      return '$area の$direction ${offset.group(1)}km';
    }

    final coast = RegExp(r'^off the coast of (.+)$').firstMatch(text);
    if (coast != null) return '${_areaName(coast.group(1)!)} の沖';

    final region = RegExp(r'^(.+) region$').firstMatch(text);
    if (region != null) return '${_areaName(region.group(1)!)} 付近';

    const bearings = {
      'north': '北方',
      'south': '南方',
      'east': '東方',
      'west': '西方',
      'northeast': '北東方',
      'northwest': '北西方',
      'southeast': '南東方',
      'southwest': '南西方',
    };
    final bearing = RegExp(
      r'^(north|south|east|west|northeast|northwest|southeast|southwest)'
      r' of (?:the )?(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (bearing != null) {
      final word = bearings[bearing.group(1)!.toLowerCase()];
      return '${_areaName(bearing.group(2)!)} の$word';
    }

    return _areaName(text);
  }

  /// EONET の見出しを訳す。
  ///
  /// 例: 「Wildfire Calico, Humboldt, Nevada」→「山火事 Calico Humboldt 米国ネバダ州」
  ///     「Telica Volcano, Nicaragua」→「Telica 火山（ニカラグア）」
  String eonetTitle(String english) {
    final text = english.trim();
    if (text.isEmpty) return text;

    final volcano = RegExp(r'^(.+?) Volcano(?:, (.+))?$').firstMatch(text);
    if (volcano != null) {
      final country = volcano.group(2);
      final suffix = country == null ? '' : '（${_areaName(country)}）';
      return '${volcano.group(1)} 火山$suffix';
    }

    for (final entry in _phenomena.entries) {
      if (!text.startsWith('${entry.key} ')) continue;
      final rest = text.substring(entry.key.length + 1);
      return '${entry.value} ${_areaName(rest)}';
    }
    return _areaName(text);
  }

  /// 地名の並び（「Ocotito, Mexico」「Calico, Humboldt, Nevada」）を訳す。
  /// 訳せた部分だけ置き換え、都市名などはそのまま残す。
  String _areaName(String english) {
    final parts = english.split(', ').map((part) => part.trim()).toList();
    final translated = [
      for (final part in parts) _translateArea(part) ?? part,
    ];

    // 「都市, 国」は日本語の語順に合わせて「国 都市」へ入れ替える。
    if (translated.length == 2 && _translateArea(parts.last) != null) {
      return '${translated.last} ${translated.first}';
    }
    return translated.join(' ');
  }

  String? _translateArea(String english) {
    final state = _usStates[english] ?? _usStateNames[english];
    if (state != null) return state.endsWith('州') ? '米国$state' : state;
    return countryNameJa[english];
  }
}
