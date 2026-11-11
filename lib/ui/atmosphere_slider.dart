import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Atmosfer ayarının arayüzde gösterim birimi.
enum AtmosphereUnit {
  /// Değer × 100, "%150" biçiminde.
  percent,

  /// Saniye, "1,2 sn" biçiminde.
  seconds,

  /// Tam sayı adet (tur), "4 tur" biçiminde.
  rounds,

  /// Tam sayı seviye, "Sv. 2" biçiminde.
  level,
}

/// Tüm atmosfer ayarlarında kullanılan, birbirine hizalı ayar satırı:
///
/// * Üst satır: simge, başlık, (sınır üstündeyse) "SINIR ÜSTÜ" rozeti ve değer.
/// * Alt satır: kaydırıcı + elle giriş kutusu + onay düğmesi.
///
/// Kaydırıcı yalnızca [sliderMax]'a kadar gider. Daha yüksek bir değer için
/// kutuya sayı yazılır ve onay düğmesine (ya da Enter'a) basılınca uygulanır.
/// [hardMax] verilmezse ÜST SINIR YOKTUR. Kutu ve düğmenin genişliği sabittir;
/// böylece bütün satırların kaydırıcıları ve kutuları aynı hizada durur.
class AtmosphereSlider extends StatefulWidget {
  const AtmosphereSlider({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.sliderMax,
    this.hardMax,
    required this.onChanged,
    this.min = 0.0,
    this.divisions,
    this.unit = AtmosphereUnit.percent,
    this.describe,
    this.offLabel = 'Kapalı',
  });

  final IconData icon;
  final Color color;
  final String title;
  final double value;
  final double min;
  final double sliderMax;

  /// Elle girişin üst sınırı; null = sınırsız.
  final double? hardMax;
  final int? divisions;
  final AtmosphereUnit unit;

  /// Değerin yanına eklenecek kısa ad (ör. "Kasırga"); null dönerse eklenmez.
  final String? Function(double value)? describe;

  /// Değer sıfırken gösterilen metin (null → sayı gösterilir).
  final String? offLabel;

  final ValueChanged<double> onChanged;

  @override
  State<AtmosphereSlider> createState() => _AtmosphereSliderState();
}

class _AtmosphereSliderState extends State<AtmosphereSlider> {
  static const double _fieldWidth = 82;
  static const double _controlHeight = 36;

  late final TextEditingController _ctrl;
  final FocusNode _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _format(widget.value));
    _ctrl.addListener(_onTextChanged);
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AtmosphereSlider old) {
    super.didUpdateWidget(old);
    // Değer dışarıdan (kaydırıcı ile) değiştiyse ve kutuda bekleyen bir elle
    // giriş yoksa kutuyu güncel değerle eşitle.
    if (old.value != widget.value && (!_focus.hasFocus || _ctrl.text == _format(old.value))) {
      _setText(_format(widget.value));
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ biçimleme
  double _toDisplay(double v) => widget.unit == AtmosphereUnit.percent ? v * 100.0 : v;
  double _fromDisplay(double d) => switch (widget.unit) {
        AtmosphereUnit.percent => d / 100.0,
        AtmosphereUnit.rounds || AtmosphereUnit.level => d.roundToDouble(),
        AtmosphereUnit.seconds => d,
      };
  String get _unitSuffix => switch (widget.unit) {
        AtmosphereUnit.percent => '%',
        AtmosphereUnit.seconds => 'sn',
        AtmosphereUnit.rounds => 'tur',
        AtmosphereUnit.level => 'sv',
      };

  String _format(double v) {
    final d = _toDisplay(v);
    if (widget.unit != AtmosphereUnit.seconds) return d.round().toString();
    return d.toStringAsFixed(1).replaceAll('.', ',');
  }

  String _withUnit(double v) => switch (widget.unit) {
        AtmosphereUnit.percent => '%${_format(v)}',
        AtmosphereUnit.seconds => '${_format(v)} sn',
        AtmosphereUnit.rounds => '${_format(v)} tur',
        AtmosphereUnit.level => 'Sv. ${_format(v)}',
      };

  String _valueText(double v) {
    if (widget.offLabel != null && v <= 0.001) return widget.offLabel!;
    final number = _withUnit(v);
    final name = widget.describe?.call(v);
    return name == null ? number : '$number · $name';
  }

  double? _parse(String raw) {
    final cleaned =
        raw.trim().replaceAll('%', '').replaceAll('sn', '').replaceAll('tur', '').replaceAll('sv', '').replaceAll(',', '.').trim();
    if (cleaned.isEmpty) return null;
    final d = double.tryParse(cleaned);
    if (d == null || d.isNaN || d.isInfinite) return null;
    return _fromDisplay(d);
  }

  void _setText(String text) {
    _ctrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  // ------------------------------------------------------------ olaylar
  bool get _pending {
    final parsed = _parse(_ctrl.text);
    if (parsed == null) return _ctrl.text.trim().isNotEmpty;
    return _format(parsed) != _format(widget.value);
  }

  void _onTextChanged() {
    if (_error != null) _error = null;
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _apply() {
    final parsed = _parse(_ctrl.text);
    if (parsed == null) {
      setState(() => _error = 'Geçerli bir sayı yaz');
      return;
    }
    final hard = widget.hardMax;
    final clamped = hard == null ? (parsed < widget.min ? widget.min : parsed) : parsed.clamp(widget.min, hard);
    final limited = clamped != parsed;
    widget.onChanged(clamped);
    _setText(_format(clamped));
    setState(() {
      _error = !limited
          ? null
          : hard == null
              ? 'En az ${_limitText(widget.min)}; ${_limitText(clamped)} uygulandı.'
              : 'Güvenli aralık ${_limitText(widget.min)} – ${_limitText(hard)}; '
                  '${_limitText(clamped)} uygulandı.';
    });
    if (!limited) _focus.unfocus();
  }

  // ------------------------------------------------------------ arayüz
  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final over = v > widget.sliderMax + 1e-6;
    final color = widget.color;
    final pending = _pending;
    final showHint = _focus.hasFocus || _error != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(widget.icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, letterSpacing: 1.1, color: Color(0xFFC8A464)),
                ),
              ),
              if (over) ...[
                _OverLimitBadge(color: color),
                const SizedBox(width: 6),
              ],
              Text(
                _valueText(v),
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: color),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: _controlHeight + 8,
            child: Row(
              children: [
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      activeTrackColor: color,
                      inactiveTrackColor: color.withValues(alpha: 0.18),
                      thumbColor: over ? Colors.white : color,
                      overlayColor: color.withValues(alpha: 0.14),
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
                      showValueIndicator: ShowValueIndicator.never,
                    ),
                    child: Slider(
                      value: v.clamp(widget.min, widget.sliderMax),
                      min: widget.min,
                      max: widget.sliderMax,
                      divisions: widget.divisions,
                      onChanged: (nv) {
                        _focus.unfocus();
                        if (_error != null) setState(() => _error = null);
                        widget.onChanged(nv);
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: _fieldWidth,
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    textAlign: TextAlign.right,
                    textAlignVertical: TextAlignVertical.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      // Üst sınır yok: büyük sayılar da yazılabilsin.
                      LengthLimitingTextInputFormatter(10),
                    ],
                    onSubmitted: (_) => _apply(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                    cursorColor: color,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF0F1B2D),
                      // Kutunun çerçevesi onay düğmesiyle birebir aynı yükseklikte olsun.
                      constraints: const BoxConstraints.tightFor(height: _controlHeight),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      suffixText: _unitSuffix,
                      suffixStyle: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.85)),
                      hintText: _format(widget.value),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide(
                          color: _error != null ? const Color(0xFFFF6B7A) : color.withValues(alpha: 0.35),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide(
                          color: _error != null ? const Color(0xFFFF6B7A) : color,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox.square(
                  dimension: _controlHeight,
                  child: Tooltip(
                    message: 'Elle girilen değeri onayla ve uygula',
                    child: Material(
                      color: pending ? color : const Color(0xFF0F1B2D),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                        side: BorderSide(color: pending ? color : color.withValues(alpha: 0.35)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: _apply,
                        child: Icon(
                          Icons.check_rounded,
                          size: 20,
                          color: pending ? const Color(0xFF0B1220) : color.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.topCenter,
            child: showHint
                ? Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _error ??
                          (widget.hardMax == null
                              ? 'Kaydırıcı ${_limitText(widget.sliderMax)} sınırına kadar; elle '
                                  'istediğin kadar yüksek değer yazıp ✓ ile onayla (üst sınır yok).'
                              : 'Kaydırıcı ${_limitText(widget.sliderMax)} sınırına kadar; elle '
                                  '${_limitText(widget.hardMax!)} değerine kadar yazıp ✓ ile onayla.'),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: _error != null ? const Color(0xFFFF8A96) : const Color(0xFF98A8C2),
                      ),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  String _limitText(double v) => _withUnit(v);
}

class _OverLimitBadge extends StatelessWidget {
  const _OverLimitBadge({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        'SINIR ÜSTÜ',
        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: color),
      ),
    );
  }
}
