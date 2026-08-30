import 'package:flutter/material.dart';

import '../../data/country_filter.dart';
import '../../data/country_index.dart';
import '../../data/coverage.dart';
import '../../domain/event_kind.dart';
import '../app_state.dart';
import '../event_style.dart';

/// 情報を出す国・地域を選ぶ画面。
///
/// 一覧から検索して登録する形にしている。国は 239 件あり、
/// 一覧を延々とスクロールさせるより、名前で引ける方が早いため。
/// ひらがなで打っても片仮名の国名に当たる（「ちり」→「チリ」）。
///
/// 全種別まとめて指定する使い方と、種別ごとに変える使い方の両方に対応する。
class CountryFilterPage extends StatefulWidget {
  const CountryFilterPage({super.key, required this.state});

  final AppState state;

  @override
  State<CountryFilterPage> createState() => _CountryFilterPageState();
}

class _CountryFilterPageState extends State<CountryFilterPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  /// 「種別ごと」のときに編集している種別。
  late EventKind _editingKind = _selectableKinds.first;

  /// 国で絞る意味がある種別（情報源が全世界を対象にしているもの）。
  static final List<EventKind> _selectableKinds = CountryFilter.selectableKinds;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  AppState get _state => widget.state;
  CountryFilter get _filter => _state.countryFilter;

  /// 今編集している対象の国。
  Set<String> get _selected =>
      _filter.perKind ? _filter.forKind(_editingKind) : _filter.all;

  Future<void> _setSelected(Set<String> codes) => _state.setCountryFilter(
        _filter.perKind
            ? _filter.withKind(_editingKind, codes)
            : _filter.copyWith(all: codes),
      );

  Future<void> _toggle(String code) async {
    final codes = Set<String>.from(_selected);
    if (!codes.remove(code)) codes.add(code);
    await _setSelected(codes);
  }

  /// 今取得できている情報に実際に出てくる国。先に出して選びやすくする。
  List<Country> get _countriesInView {
    final codes = {
      for (final event in _state.snapshot?.events ?? const [])
        if (event.countryCode != null) event.countryCode!,
    };
    return [
      for (final code in codes)
        if (_state.countries[code] != null) _state.countries[code]!,
    ]..sort((a, b) => a.nameJa.compareTo(b.nameJa));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) {
        final selected = _selected;
        final results = _state.countries.search(_query);

        return Scaffold(
          appBar: AppBar(
            title: const Text('対象の国・地域'),
            actions: [
              if (selected.isNotEmpty)
                TextButton(
                  onPressed: () => _setSelected(const {}),
                  child: const Text('この対象を解除'),
                ),
            ],
          ),
          body: Column(
            children: [
              _ModeSwitch(state: _state),
              if (_filter.perKind)
                _KindSwitch(
                  filter: _filter,
                  editing: _editingKind,
                  kinds: _selectableKinds,
                  onChanged: (kind) => setState(() => _editingKind = kind),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: '国名で検索（例: ちり / Chile / CL）',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              _SelectionSummary(
                state: _state,
                selected: selected,
                onRemove: _toggle,
              ),
              const Divider(height: 1),
              Expanded(
                child: _query.isEmpty
                    ? _buildGrouped(results, selected)
                    : _buildFlat(results, selected),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 検索していないときは「今の情報に含まれる国」を先に出す。
  Widget _buildGrouped(List<Country> all, Set<String> selected) {
    final inView = _countriesInView;
    return ListView(
      children: [
        if (inView.isNotEmpty) ...[
          const _SectionHeader(title: '今表示している情報に含まれる国'),
          for (final country in inView) _tile(country, selected),
          const _SectionHeader(title: 'すべての国と地域'),
        ],
        for (final country in all) _tile(country, selected),
      ],
    );
  }

  Widget _buildFlat(List<Country> results, Set<String> selected) {
    if (results.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('見つかりませんでした'),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) => _tile(results[index], selected),
    );
  }

  Widget _tile(Country country, Set<String> selected) => CheckboxListTile(
        key: ValueKey('${_editingKind.name}-${country.code}'),
        dense: true,
        value: selected.contains(country.code),
        onChanged: (_) => _toggle(country.code),
        title: Text(country.nameJa),
        subtitle: Text('${country.nameEn}（${country.code}）'),
      );
}

/// 一括で指定するか、種別ごとに指定するか。
///
/// 切り替えても、もう一方で指定した内容は残したままにしている
/// （`CountryFilter` が両方を持っている）。
/// 消えないことが分からないと切り替えるのが怖いので、その場に書く。
class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = state.countryFilter;

    // 今は使っていない側に、何か指定が残っているか。
    final hiddenCount = filter.perKind
        ? filter.all.length
        : filter.byKind.values.where((codes) => codes.isNotEmpty).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('まとめて指定')),
              ButtonSegment(value: true, label: Text('種別ごとに指定')),
            ],
            selected: {filter.perKind},
            onSelectionChanged: (selection) => state
                .setCountryFilter(filter.copyWith(perKind: selection.first)),
          ),
        ),
        if (hiddenCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    filter.perKind
                        ? 'まとめて指定した$hiddenCountか国は消えていません。'
                            '戻せばそのまま使えます'
                        : '種別ごとに指定した$hiddenCount件は消えていません。'
                            '戻せばそのまま使えます',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 種別ごとに指定するときの、編集対象の切り替え。
class _KindSwitch extends StatelessWidget {
  const _KindSwitch({
    required this.filter,
    required this.editing,
    required this.kinds,
    required this.onChanged,
  });

  final CountryFilter filter;
  final EventKind editing;
  final List<EventKind> kinds;
  final ValueChanged<EventKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final kind in kinds)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 3),
              child: ChoiceChip(
                avatar: Icon(EventStyle.iconOf(kind), size: 18),
                label: Text(
                  filter.forKind(kind).isEmpty
                      ? kind.labelJa
                      : '${kind.labelJa} ${filter.forKind(kind).length}',
                  softWrap: false,
                ),
                selected: editing == kind,
                onSelected: (_) => onChanged(kind),
              ),
            ),
        ],
      ),
    );
  }
}

/// 登録済みの国と、国を判定できない情報の扱い。
class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({
    required this.state,
    required this.selected,
    required this.onRemove,
  });

  final AppState state;
  final Set<String> selected;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = state.countryFilter;

    // 国で絞れない種別があることは、ここで断っておく。
    final excluded = [
      for (final kind in EventKind.values)
        if (!CountryFilter.appliesTo(kind) && !DataCoverage.of(kind).hasNoSource)
          kind.labelJa,
    ];

    if (selected.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Text(
          [
            '登録なし（全世界の情報を表示します）。'
                '登録すると、地図・一覧に加えて通知も登録した国だけになります。',
            if (excluded.isNotEmpty)
              '${excluded.join("・")}は情報源が特定の国に限られているため、'
                  '国では絞りません。',
          ].join('\n'),
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 6,
            children: [
              for (final code in selected)
                InputChip(
                  label: Text(state.countries[code]?.nameJa ?? code),
                  onDeleted: () => onRemove(code),
                ),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          value: filter.includeUnknown,
          onChanged: (value) => state.setCountryFilter(
            filter.copyWith(includeUnknown: value),
          ),
          title: const Text('国を特定できない情報も表示する'),
          subtitle: const Text('外洋の地震など、どの国にも寄せられないもの'),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(title, style: theme.textTheme.labelMedium),
    );
  }
}
