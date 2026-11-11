import 'dart:math' as math;

import '../game/chess_game.dart';

/// Karakterlerin konuşma ve savaş narası tetikleyicileri.
enum VoiceEvent {
  select,
  march,
  attack,
  victory,
}

/// Prosedürel savaş ve adım ses efektleri.
enum SfxKind {
  stepArmor,
  stepStealth,
  stepStomp,
  wingFlap,
  magicGlide,
  clashSteel,
  slashBlade,
  dragonFire,
  maulSmash,
  bloodDrain,
  axeCleave,
  voicePawn,
  voiceKnight,
  voiceBishop,
  voiceRookFemale,
  voiceQueenFemale,
  voiceKing,
}

/// Tek bir karakter replik / savaş narası kaydı (ElevenLabs ile doğrudan uyumlu).
class VoiceLine {
  const VoiceLine({
    required this.id,
    required this.kind,
    required this.event,
    required this.speaker,
    required this.warCry,
    required this.text,
    required this.elevenVoiceId,
    required this.elevenStyleHint,
    this.variationIndex,
    this.durationMs = 3600,
  });

  /// `voices/<id>.mp3` veya `voices/<id>.wav` dosya adı (uzantısız).
  final String id;
  final PieceType kind;
  final VoiceEvent event;
  final String speaker;
  final String warCry;
  final String text;

  /// ElevenLabs çok dilli (eleven_multilingual_v2) önerilen hazır ses kimliği.
  final String elevenVoiceId;
  final String elevenStyleHint;

  /// 1..6 arasındaki kura torbası varyasyon indeksi (opsiyonel).
  final int? variationIndex;

  /// Ses dosyasının tam milisaniye süresi.
  final int durationMs;
}

/// Kura Torbası (Shuffle Bag / Deck without Replacement):
/// Karakterin 6 ses dosyasını torbaya koyar, kura çeker gibi sırayla dağıtır.
/// Torbadaki 6 ses tükenene kadar hiçbir ses dosyası tekrar etmez (örn: 4, 6, 2, 3, 5, 1).
/// Torba bittiğinde 6 ses yeniden torbaya atılır ve rastgele karıştırılır.
/// Yeni karıştırılan torbanın ilk sesi, önceki torbanın son sesiyle aynıysa takas edilir (peş peşe tekrarı önleme).
class VoiceShuffleBag {
  VoiceShuffleBag({this.size = 6, math.Random? rng}) : _rng = rng ?? math.Random();

  final int size;
  final math.Random _rng;
  final List<int> _deck = [];
  int? _lastDrawn;

  /// Torbadan sıradaki ses indeksini (1..size) çeker.
  int draw() {
    if (_deck.isEmpty) {
      _deck.addAll(List.generate(size, (i) => i + 1));
      _deck.shuffle(_rng);
      // Yeni destenin ilk çekilecek elemanı (_deck.last), bir önceki destenin son çekilen elemanıyla (_lastDrawn) aynıysa takas et!
      if (_lastDrawn != null && _deck.last == _lastDrawn && _deck.length > 1) {
        final swapIdx = _rng.nextInt(_deck.length - 1);
        final tmp = _deck.last;
        _deck.last = _deck[swapIdx];
        _deck[swapIdx] = tmp;
      }
    }
    final drawn = _deck.removeLast();
    _lastDrawn = drawn;
    return drawn;
  }

  void reset() {
    _deck.clear();
    _lastDrawn = null;
  }

  List<int> get remaining => List.unmodifiable(_deck);
  int? get lastDrawn => _lastDrawn;
}

/// 6 karanlık-fantezi sınıfının tamamı için 24 Türkçe ses komutu ve savaş narası.
const List<VoiceLine> kVoiceCatalog = [
  // ================= 1. KALKAN MUHAFIZI (Zırhlı Öncü Şövalye - Tok Erkek) =================
  VoiceLine(
    id: 'pawn_select',
    kind: PieceType.pawn,
    event: VoiceEvent.select,
    speaker: 'Kalkan Muhafızı',
    warCry: 'Kalkanlar hazır!',
    text: 'Kalkanlar kenetlensin! Emrinizi bekliyorum komutanım!',
    elevenVoiceId: 'pNInz6obpgDQGcFmaJgB', // Adam
    elevenStyleHint: 'Disiplinli, tok sesli zırhlı şövalye muhafız',
  ),
  VoiceLine(
    id: 'pawn_march',
    kind: PieceType.pawn,
    event: VoiceEvent.march,
    speaker: 'Kalkan Muhafızı',
    warCry: 'İleri marş!',
    text: 'Safları bozmadan ileri! Çelik adımlarımızla cepheyi tutuyoruz!',
    elevenVoiceId: 'pNInz6obpgDQGcFmaJgB',
    elevenStyleHint: 'Kararlı askeri yürüyüş komutu',
  ),
  VoiceLine(
    id: 'pawn_attack',
    kind: PieceType.pawn,
    event: VoiceEvent.attack,
    speaker: 'Kalkan Muhafızı',
    warCry: 'HÜCUUUM! YIKIL!',
    text: 'Demir ve onur adına! Teberimin ucunda yıkıl karşımdan!',
    elevenVoiceId: 'pNInz6obpgDQGcFmaJgB',
    elevenStyleHint: 'Öfkeli şövalye hücum narası',
  ),
  VoiceLine(
    id: 'pawn_victory',
    kind: PieceType.pawn,
    event: VoiceEvent.victory,
    speaker: 'Kalkan Muhafızı',
    warCry: 'Hat temizlendi!',
    text: 'Düşman devrildi! Kalkan hattı sarsılmaz.',
    elevenVoiceId: 'pNInz6obpgDQGcFmaJgB',
    elevenStyleHint: 'Soğukkanlı zafer bildirimi',
  ),

  // ================= 2. SUİKASTÇİ (Gölge Avcısı - Keskin Fısıltılı Erkek) =================
  VoiceLine(
    id: 'knight_select',
    kind: PieceType.knight,
    event: VoiceEvent.select,
    speaker: 'Suikastçi',
    warCry: 'Gölgeler hazır...',
    text: 'Gölgeden hızlı, nefesten sessiz... Hedefi göster.',
    elevenVoiceId: 'TxGEqnHWrfWFTfGW9XjX', // Josh
    elevenStyleHint: 'Karanlık, tehlikeli ve soğukkanlı suikastçi tonu',
  ),
  VoiceLine(
    id: 'knight_march',
    kind: PieceType.knight,
    event: VoiceEvent.march,
    speaker: 'Suikastçi',
    warCry: 'Karanlığa süzül!',
    text: 'Beni fark ettiklerinde bıçaklarım çoktan konuşmuş olacak.',
    elevenVoiceId: 'TxGEqnHWrfWFTfGW9XjX',
    elevenStyleHint: 'Sinsi ve hızlı avcı fısıltısı',
  ),
  VoiceLine(
    id: 'knight_attack',
    kind: PieceType.knight,
    event: VoiceEvent.attack,
    speaker: 'Suikastçi',
    warCry: 'GÖLGELERDEN ÖLÜM!',
    text: 'Arkandayım! İkiz bıçaklarımdan kaçış yok!',
    elevenVoiceId: 'TxGEqnHWrfWFTfGW9XjX',
    elevenStyleHint: 'Ani ve keskin saldırı haykırışı',
  ),
  VoiceLine(
    id: 'knight_victory',
    kind: PieceType.knight,
    event: VoiceEvent.victory,
    speaker: 'Suikastçi',
    warCry: 'İş bitti.',
    text: 'Temiz darbe... Geriye tek bir iz bile kalmadı.',
    elevenVoiceId: 'TxGEqnHWrfWFTfGW9XjX',
    elevenStyleHint: 'Sakin, buz gibi suikastçi kapanışı',
  ),

  // ================= 3. EJDERHA (Antik Sürüngen - Derin Gürleyen Antik Ses) =================
  VoiceLine(
    id: 'bishop_select',
    kind: PieceType.bishop,
    event: VoiceEvent.select,
    speaker: 'Ejderha',
    warCry: 'GRRAAAH!',
    text: 'Kanatlarım göğü karartır, ateşim kayaları eritir!',
    elevenVoiceId: 'VR6AewLTigWG4xSOukaG', // Arnold / deep resonant
    elevenStyleHint: 'Derin, gürleyen, antik ejderha sesi',
  ),
  VoiceLine(
    id: 'bishop_march',
    kind: PieceType.bishop,
    event: VoiceEvent.march,
    speaker: 'Ejderha',
    warCry: 'GÖKLERE YÜKSEL!',
    text: 'Gökyüzü benimdir! Küllerin ve fırtınanın içinden süzülüyorum!',
    elevenVoiceId: 'VR6AewLTigWG4xSOukaG',
    elevenStyleHint: 'Kanat çırpışıyla yükselen heybetli ejderha',
  ),
  VoiceLine(
    id: 'bishop_attack',
    kind: PieceType.bishop,
    event: VoiceEvent.attack,
    speaker: 'Ejderha',
    warCry: 'KAVRUL VE KÜL OL!',
    text: 'KAVRUL VE KÜL OL! Antik ejder ateşinden kurtuluş yok!',
    elevenVoiceId: 'VR6AewLTigWG4xSOukaG',
    elevenStyleHint: 'Kükreyen yıkıcı ateş nefesi narası',
  ),
  VoiceLine(
    id: 'bishop_victory',
    kind: PieceType.bishop,
    event: VoiceEvent.victory,
    speaker: 'Ejderha',
    warCry: 'Küller savrulsun...',
    text: 'Geriye yalnızca kor, duman ve küller kaldı.',
    elevenVoiceId: 'VR6AewLTigWG4xSOukaG',
    elevenStyleHint: 'Karanlık ve ağır zafer hırıltısı',
  ),

  // ================= 4. KADIN SAVAŞ DEVİ (Valkür / Amazon Dev Kadın!) =================
  VoiceLine(
    id: 'rook_select',
    kind: PieceType.rook,
    event: VoiceEvent.select,
    speaker: 'Kadın Savaş Devi',
    warCry: 'Balyozum hazır!',
    text: 'Savaş balyozum elimde! Hangi cepheyi yerle bir etmemi istiyorsun?',
    elevenVoiceId: '21m00Tcm4TlvDq8ikWAM', // Rachel / strong female
    elevenStyleHint: 'Güçlü, heybetli, savaşçı Amazon/Valkür dev kadın sesi',
  ),
  VoiceLine(
    id: 'rook_march',
    kind: PieceType.rook,
    event: VoiceEvent.march,
    speaker: 'Kadın Savaş Devi',
    warCry: 'ÇEKİLİN YOLUMDAN!',
    text: 'Çekilin yolumdan! Yeryüzü her adımımda sarsılacak!',
    elevenVoiceId: '21m00Tcm4TlvDq8ikWAM',
    elevenStyleHint: 'Yeri titreten özgüvenli dev kadın yürüyüş narası',
  ),
  VoiceLine(
    id: 'rook_attack',
    kind: PieceType.rook,
    event: VoiceEvent.attack,
    speaker: 'Kadın Savaş Devi',
    warCry: 'EZİL VE PARÇALAN!',
    text: 'DAĞLARI BİLE UN UFAK EDERİM! Balyozumun altında ezil!',
    elevenVoiceId: '21m00Tcm4TlvDq8ikWAM',
    elevenStyleHint: 'Yıkıcı Valkür savaş çığlığı ve darbe haykırışı',
  ),
  VoiceLine(
    id: 'rook_victory',
    kind: PieceType.rook,
    event: VoiceEvent.victory,
    speaker: 'Kadın Savaş Devi',
    warCry: 'Kimse duramaz!',
    text: 'Bana kafa tutanların sonu hep aynı... Toz ve toprak!',
    elevenVoiceId: '21m00Tcm4TlvDq8ikWAM',
    elevenStyleHint: 'Mağrur savaşçı dev kadın zafer sözü',
  ),

  // ================= 5. VAMPİR KRALİÇE (Kan Kontesi - Büyüleyici Kadın) =================
  VoiceLine(
    id: 'queen_select',
    kind: PieceType.queen,
    event: VoiceEvent.select,
    speaker: 'Vampir Kraliçe',
    warCry: 'Kan çağırıyor...',
    text: 'Tatlı kan kokusu rüzgârda dans ediyor... Kimi kurban seçtik?',
    elevenVoiceId: 'EXAVITQu4vr4xnSDxMaL', // Bella / aristocratic female
    elevenStyleHint: 'Aristokrat, büyüleyici ve ürpertici gotik kraliçe sesi',
  ),
  VoiceLine(
    id: 'queen_march',
    kind: PieceType.queen,
    event: VoiceEvent.march,
    speaker: 'Vampir Kraliçe',
    warCry: 'Gece yükseliyor!',
    text: 'Kızıl gece benim pelerinimdir; karanlığın kraliçesi önünde eğilin.',
    elevenVoiceId: 'EXAVITQu4vr4xnSDxMaL',
    elevenStyleHint: 'Zarif ve hipnotize edici karanlık büyü tonu',
  ),
  VoiceLine(
    id: 'queen_attack',
    kind: PieceType.queen,
    event: VoiceEvent.attack,
    speaker: 'Vampir Kraliçe',
    warCry: 'SON DAMLASINA KADAR!',
    text: 'Yaşam özün artık bana ait! Yarasalarım, ziyafet vakti!',
    elevenVoiceId: 'EXAVITQu4vr4xnSDxMaL',
    elevenStyleHint: 'Vahşi ve büyüleyici vampir saldırı çığlığı',
  ),
  VoiceLine(
    id: 'queen_victory',
    kind: PieceType.queen,
    event: VoiceEvent.victory,
    speaker: 'Vampir Kraliçe',
    warCry: 'Ne tatlı bir son...',
    text: 'Ne zarif bir son... Gücün artık damarlarımda akıyor.',
    elevenVoiceId: 'EXAVITQu4vr4xnSDxMaL',
    elevenStyleHint: 'Tatminkâr karanlık kraliçe fısıltısı',
  ),

  // ================= 6. BARBAR KRAL (Kuzey Hükümdarı - Gürleyen Komutan) =================
  VoiceLine(
    id: 'king_select',
    kind: PieceType.king,
    event: VoiceEvent.select,
    speaker: 'Barbar Kral',
    warCry: 'Kralınız konuşuyor!',
    text: 'Kuzeyin tahtı korkuyla değil, kan ve çelikle korunur!',
    elevenVoiceId: 'ErXwobaYiN019PkySvjV', // Antoni / commanding king
    elevenStyleHint: 'Gürleyen, otoriter kuzey savaş kralı',
  ),
  VoiceLine(
    id: 'king_march',
    kind: PieceType.king,
    event: VoiceEvent.march,
    speaker: 'Barbar Kral',
    warCry: 'SANCAKLAR İLERİ!',
    text: 'Boruları çalın, sancakları kaldırın! Kralınız bizzat cepheye yürüyor!',
    elevenVoiceId: 'ErXwobaYiN019PkySvjV',
    elevenStyleHint: 'Orduyu coşturan hükümdar yürüyüş emri',
  ),
  VoiceLine(
    id: 'king_attack',
    kind: PieceType.king,
    event: VoiceEvent.attack,
    speaker: 'Barbar Kral',
    warCry: 'KUZEYİN ÖFKESİYLE!',
    text: 'KUZEYİN ÖFKESİYLE PARÇALAN! Hilal baltamdan kurtuluş yok!',
    elevenVoiceId: 'ErXwobaYiN019PkySvjV',
    elevenStyleHint: 'Yeri göğü inleten barbar kral savaş narası',
  ),
  VoiceLine(
    id: 'king_victory',
    kind: PieceType.king,
    event: VoiceEvent.victory,
    speaker: 'Barbar Kral',
    warCry: 'DİZ ÇÖKÜN!',
    text: 'Tahtımın ve baltamın önünde herkes diz çökecek!',
    elevenVoiceId: 'ErXwobaYiN019PkySvjV',
    elevenStyleHint: 'Muzaffer kral kükreyişi',
  ),
];

VoiceLine voiceLineOf(PieceType kind, VoiceEvent event, {int? variation}) {
  final lines = kVoiceCatalog.where((l) => l.kind == kind && l.event == event).toList();
  if (lines.isEmpty) return kVoiceCatalog.first;
  if (variation != null && variation >= 1 && variation <= lines.length) {
    return lines[variation - 1];
  }
  return lines[DateTime.now().millisecondsSinceEpoch % lines.length];
}

List<VoiceLine> voiceLinesOf(PieceType kind, VoiceEvent event) =>
    kVoiceCatalog.where((l) => l.kind == kind && l.event == event).toList();

/// Karakterin diskteki ses dosyası önekleri (assets/audio/ içindeki isimlendirmelerle tam uyumlu).
List<String> pieceVoicePrefixes(PieceType kind) => switch (kind) {
  PieceType.pawn => const ['guard', 'pawn'],
  PieceType.knight => const ['assassin', 'knight'],
  PieceType.bishop => const ['dragon', 'bishop'],
  PieceType.rook => const ['giant', 'rook'],
  PieceType.queen => const ['queen'],
  PieceType.king => const ['barbarian_king', 'king'],
};

/// 6 karakter sınıfının her biri için 6 repliklik (toplam 36) POV & hamle kura kataloğu.
/// Ses dosyası indeksleri (1..6) ile doğrudan birebir eşleşir.
const Map<PieceType, List<VoiceLine>> kPieceMoveVoiceCatalog = {
  // ================= 1. KALKAN MUHAFIZI (guard_1 ... guard_6) =================
  PieceType.pawn: [
    VoiceLine(
      id: 'guard_1',
      kind: PieceType.pawn,
      event: VoiceEvent.march,
      speaker: 'Kalkan Muhafızı',
      warCry: 'Kalkanlar Kenetlensin!',
      text: 'Kalkanlar kenetlensin! Emrinizi bekliyorum komutanım!',
      elevenVoiceId: 'pNInz6obpgDQGcFmaJgB',
      elevenStyleHint: 'Disiplinli zırhlı öncü şövalye',
      variationIndex: 1,
      durationMs: 3697,
    ),
    VoiceLine(
      id: 'guard_2',
      kind: PieceType.pawn,
      event: VoiceEvent.march,
      speaker: 'Kalkan Muhafızı',
      warCry: 'Safları Bozmadan İleri!',
      text: 'Safları bozmadan ileri! Çelik adımlarımızla cepheyi tutuyoruz!',
      elevenVoiceId: 'pNInz6obpgDQGcFmaJgB',
      elevenStyleHint: 'Sadık ve kararlı muhafız',
      variationIndex: 2,
      durationMs: 4664,
    ),
    VoiceLine(
      id: 'guard_3',
      kind: PieceType.pawn,
      event: VoiceEvent.march,
      speaker: 'Kalkan Muhafızı',
      warCry: 'Hizmetinizde!',
      text: 'Çelik zırhım ve kalkanım hizmetinizde!',
      elevenVoiceId: 'pNInz6obpgDQGcFmaJgB',
      elevenStyleHint: 'Sadakat beyanı',
      variationIndex: 3,
      durationMs: 2757,
    ),
    VoiceLine(
      id: 'guard_4',
      kind: PieceType.pawn,
      event: VoiceEvent.march,
      speaker: 'Kalkan Muhafızı',
      warCry: 'KALKANLARI KALDIRIN!',
      text: 'KALKANLARI KALDIRIN! HATTI KORUYUN!',
      elevenVoiceId: 'pNInz6obpgDQGcFmaJgB',
      elevenStyleHint: 'Hücum komutu',
      variationIndex: 4,
      durationMs: 2757,
    ),
    VoiceLine(
      id: 'guard_5',
      kind: PieceType.pawn,
      event: VoiceEvent.attack,
      speaker: 'Kalkan Muhafızı',
      warCry: 'Demir ve Onur Adına!',
      text: 'Demir ve onur adına! Teberimin ucunda yıkıl karşımdan!',
      elevenVoiceId: 'pNInz6obpgDQGcFmaJgB',
      elevenStyleHint: 'Öfkeli şövalye hücum narası',
      variationIndex: 5,
      durationMs: 4194,
    ),
    VoiceLine(
      id: 'guard_6',
      kind: PieceType.pawn,
      event: VoiceEvent.attack,
      speaker: 'Kalkan Muhafızı',
      warCry: 'Düşman Devrildi!',
      text: 'Düşman devrildi! Kalkan hattı sarsılmaz.',
      elevenVoiceId: 'pNInz6obpgDQGcFmaJgB',
      elevenStyleHint: 'Muzaffer muhafız sesi',
      variationIndex: 6,
      durationMs: 3462,
    ),
  ],

  // ================= 2. SUİKASTÇİ (assassin_1 ... assassin_6) =================
  PieceType.knight: [
    VoiceLine(
      id: 'assassin_1',
      kind: PieceType.knight,
      event: VoiceEvent.march,
      speaker: 'Suikastçi',
      warCry: 'Hedefi Göster...',
      text: 'Gölgeden hızlı, nefesten sessiz... Hedefi göster.',
      elevenVoiceId: 'TxGEqnHWrfWFTfGW9XjX',
      elevenStyleHint: 'Fısıltılı, karanlık avcı tonu',
      variationIndex: 1,
      durationMs: 4742,
    ),
    VoiceLine(
      id: 'assassin_2',
      kind: PieceType.knight,
      event: VoiceEvent.march,
      speaker: 'Suikastçi',
      warCry: 'Bıçaklarım Konuşacak!',
      text: 'Beni fark ettiklerinde bıçaklarım çoktan konuşmuş olacak.',
      elevenVoiceId: 'TxGEqnHWrfWFTfGW9XjX',
      elevenStyleHint: 'Sinsi ve hızlı avcı fısıltısı',
      variationIndex: 2,
      durationMs: 4350,
    ),
    VoiceLine(
      id: 'assassin_3',
      kind: PieceType.knight,
      event: VoiceEvent.march,
      speaker: 'Suikastçi',
      warCry: 'İkiz Bıçaklar Hazır...',
      text: 'İkiz bıçaklarım hazır... Hedefe yaklaşıyorum.',
      elevenVoiceId: 'TxGEqnHWrfWFTfGW9XjX',
      elevenStyleHint: 'Sessiz yaklaşma',
      variationIndex: 3,
      durationMs: 3619,
    ),
    VoiceLine(
      id: 'assassin_4',
      kind: PieceType.knight,
      event: VoiceEvent.attack,
      speaker: 'Suikastçi',
      warCry: 'ARKANDAYIM!',
      text: 'Arkandayım! İkiz bıçaklarımdan kaçış yok!',
      elevenVoiceId: 'TxGEqnHWrfWFTfGW9XjX',
      elevenStyleHint: 'Ani ve keskin suikast çığlığı',
      variationIndex: 4,
      durationMs: 3306,
    ),
    VoiceLine(
      id: 'assassin_5',
      kind: PieceType.knight,
      event: VoiceEvent.march,
      speaker: 'Suikastçi',
      warCry: 'Sessiz Adımlar...',
      text: 'Adımlarımı duymayacaklar bile... Biraz daha yaklaşayım.',
      elevenVoiceId: 'TxGEqnHWrfWFTfGW9XjX',
      elevenStyleHint: 'Soğukkanlı sızma',
      variationIndex: 5,
      durationMs: 4194,
    ),
    VoiceLine(
      id: 'assassin_6',
      kind: PieceType.knight,
      event: VoiceEvent.attack,
      speaker: 'Suikastçi',
      warCry: 'Temiz Darbe.',
      text: 'Temiz darbe... Geriye tek bir iz bile kalmadı.',
      elevenVoiceId: 'TxGEqnHWrfWFTfGW9XjX',
      elevenStyleHint: 'Karanlık bitiriş',
      variationIndex: 6,
      durationMs: 4350,
    ),
  ],

  // ================= 3. EJDERHA (dragon_1 ... dragon_6) =================
  PieceType.bishop: [
    VoiceLine(
      id: 'dragon_1',
      kind: PieceType.bishop,
      event: VoiceEvent.march,
      speaker: 'Ejderha',
      warCry: 'GRRAAAH!',
      text: 'Kanatlarım göğü karartır, ateşim kayaları eritir!',
      elevenVoiceId: 'VR6AewLTigWG4xSOukaG',
      elevenStyleHint: 'Derin antik ejderha kükremesi',
      variationIndex: 1,
      durationMs: 4429,
    ),
    VoiceLine(
      id: 'dragon_2',
      kind: PieceType.bishop,
      event: VoiceEvent.march,
      speaker: 'Ejderha',
      warCry: 'Kükreyiş!',
      text: 'Kükrememi duyduğunuzda kaçmak için çok geç olacak!',
      elevenVoiceId: 'VR6AewLTigWG4xSOukaG',
      elevenStyleHint: 'Kanat çırpan heybetli ejderha',
      variationIndex: 2,
      durationMs: 3959,
    ),
    VoiceLine(
      id: 'dragon_3',
      kind: PieceType.bishop,
      event: VoiceEvent.march,
      speaker: 'Ejderha',
      warCry: 'Kanatların Gölgesi!',
      text: 'Kanatlarımın gölgesinden kaçamayacaksınız!',
      elevenVoiceId: 'VR6AewLTigWG4xSOukaG',
      elevenStyleHint: 'Gökyüzü hâkimiyeti',
      variationIndex: 3,
      durationMs: 3227,
    ),
    VoiceLine(
      id: 'dragon_4',
      kind: PieceType.bishop,
      event: VoiceEvent.attack,
      speaker: 'Ejderha',
      warCry: 'KAVRUL VE KÜL OL!',
      text: 'KAVRUL VE KÜL OL! Ejder ateşimden kaçabilecek misin?',
      elevenVoiceId: 'VR6AewLTigWG4xSOukaG',
      elevenStyleHint: 'Yıkıcı alev nefesi',
      variationIndex: 4,
      durationMs: 4977,
    ),
    VoiceLine(
      id: 'dragon_5',
      kind: PieceType.bishop,
      event: VoiceEvent.march,
      speaker: 'Ejderha',
      warCry: 'Kızıl Pullar!',
      text: 'Kızıl pullarım parlıyor! Alevlerim yükseliyor!',
      elevenVoiceId: 'VR6AewLTigWG4xSOukaG',
      elevenStyleHint: 'Gök gürültüsü tonunda ejder narası',
      variationIndex: 5,
      durationMs: 3959,
    ),
    VoiceLine(
      id: 'dragon_6',
      kind: PieceType.bishop,
      event: VoiceEvent.attack,
      speaker: 'Ejderha',
      warCry: 'Küller Savrulsun...',
      text: 'Geriye yalnızca kor, duman ve küller kaldı.',
      elevenVoiceId: 'VR6AewLTigWG4xSOukaG',
      elevenStyleHint: 'Ağır zafer hırıltısı',
      variationIndex: 6,
      durationMs: 4507,
    ),
  ],

  // ================= 4. KADIN SAVAŞ DEVİ (giant_1 ... giant_6) =================
  PieceType.rook: [
    VoiceLine(
      id: 'giant_1',
      kind: PieceType.rook,
      event: VoiceEvent.march,
      speaker: 'Kadın Savaş Devi',
      warCry: 'Balyozum Hazır!',
      text: 'Savaş balyozum elimde! Hangi cepheyi yerle bir etmemi istiyorsun?',
      elevenVoiceId: '21m00Tcm4TlvDq8ikWAM',
      elevenStyleHint: 'Güçlü Amazon/Valkür savaşçı kadın',
      variationIndex: 1,
      durationMs: 4507,
    ),
    VoiceLine(
      id: 'giant_2',
      kind: PieceType.rook,
      event: VoiceEvent.march,
      speaker: 'Kadın Savaş Devi',
      warCry: 'ÇEKİLİN YOLUMDAN!',
      text: 'Çekilin yolumdan! Yeryüzü her adımımda sarsılacak!',
      elevenVoiceId: '21m00Tcm4TlvDq8ikWAM',
      elevenStyleHint: 'Yeri titreten özgüvenli yürüyüş',
      variationIndex: 2,
      durationMs: 4429,
    ),
    VoiceLine(
      id: 'giant_3',
      kind: PieceType.rook,
      event: VoiceEvent.march,
      speaker: 'Kadın Savaş Devi',
      warCry: 'Küçücük Surlar!',
      text: 'Şu küçücük surlar mı beni durduracak? Hah!',
      elevenVoiceId: '21m00Tcm4TlvDq8ikWAM',
      elevenStyleHint: 'Meydan okuyan alaycı güç',
      variationIndex: 3,
      durationMs: 3306,
    ),
    VoiceLine(
      id: 'giant_4',
      kind: PieceType.rook,
      event: VoiceEvent.attack,
      speaker: 'Kadın Savaş Devi',
      warCry: 'DAĞLARI BİLE UN UFAK EDERİM!',
      text: 'DAĞLARI BİLE UN UFAK EDERİM! EZİLİN!',
      elevenVoiceId: '21m00Tcm4TlvDq8ikWAM',
      elevenStyleHint: 'Yıkıcı savaş çığlığı',
      variationIndex: 4,
      durationMs: 3462,
    ),
    VoiceLine(
      id: 'giant_5',
      kind: PieceType.rook,
      event: VoiceEvent.attack,
      speaker: 'Kadın Savaş Devi',
      warCry: 'Balyozun Altında Ezil!',
      text: 'Balyozumun altında ezil! Karşıma çıkmaya cesaret etme!',
      elevenVoiceId: '21m00Tcm4TlvDq8ikWAM',
      elevenStyleHint: 'Heybetli meydan okuma',
      variationIndex: 5,
      durationMs: 4742,
    ),
    VoiceLine(
      id: 'giant_6',
      kind: PieceType.rook,
      event: VoiceEvent.attack,
      speaker: 'Kadın Savaş Devi',
      warCry: 'Toz ve Toprak!',
      text: 'Bana kafa tutanların sonu hep aynı... Toz ve toprak!',
      elevenVoiceId: '21m00Tcm4TlvDq8ikWAM',
      elevenStyleHint: 'Mağrur zafer darbesi',
      variationIndex: 6,
      durationMs: 4742,
    ),
  ],

  // ================= 5. VAMPİR KRALİÇE (queen_1 ... queen_6) =================
  PieceType.queen: [
    VoiceLine(
      id: 'queen_1',
      kind: PieceType.queen,
      event: VoiceEvent.march,
      speaker: 'Vampir Kraliçe',
      warCry: 'Kan Çağırıyor...',
      text: 'Tatlı kan kokusu rüzgârda dans ediyor... Kimi kurban seçtik?',
      elevenVoiceId: 'EXAVITQu4vr4xnSDxMaL',
      elevenStyleHint: 'Büyüleyici gotik kraliçe',
      variationIndex: 1,
      durationMs: 5317,
    ),
    VoiceLine(
      id: 'queen_2',
      kind: PieceType.queen,
      event: VoiceEvent.march,
      speaker: 'Vampir Kraliçe',
      warCry: 'Av Vakti Yaklaştı...',
      text: 'Gecenin gölgeleri fısıldıyor... Av vakti yaklaştı.',
      elevenVoiceId: 'EXAVITQu4vr4xnSDxMaL',
      elevenStyleHint: 'Hipnotize edici büyücü tonu',
      variationIndex: 2,
      durationMs: 4586,
    ),
    VoiceLine(
      id: 'queen_3',
      kind: PieceType.queen,
      event: VoiceEvent.march,
      speaker: 'Vampir Kraliçe',
      warCry: 'Kalp Atışları...',
      text: 'Kalp atışlarını duyabiliyorum... Ne kadar da hızlı çarpıyor.',
      elevenVoiceId: 'EXAVITQu4vr4xnSDxMaL',
      elevenStyleHint: 'Ürpertici fısıltı',
      variationIndex: 3,
      durationMs: 4429,
    ),
    VoiceLine(
      id: 'queen_4',
      kind: PieceType.queen,
      event: VoiceEvent.march,
      speaker: 'Vampir Kraliçe',
      warCry: 'Kızıl Gece...',
      text: 'Kızıl gece benim pelerinimdir; sessizce süzülüyorum.',
      elevenVoiceId: 'EXAVITQu4vr4xnSDxMaL',
      elevenStyleHint: 'Karanlık kraliçe fısıltısı',
      variationIndex: 4,
      durationMs: 4899,
    ),
    VoiceLine(
      id: 'queen_5',
      kind: PieceType.queen,
      event: VoiceEvent.attack,
      speaker: 'Vampir Kraliçe',
      warCry: 'SON DAMLASINA KADAR!',
      text: 'SON DAMLASINA KADAR! Yarasalarım, ziyafet vakti!',
      elevenVoiceId: 'EXAVITQu4vr4xnSDxMaL',
      elevenStyleHint: 'Vahşi vampir saldırı çığlığı',
      variationIndex: 5,
      durationMs: 4742,
    ),
    VoiceLine(
      id: 'queen_6',
      kind: PieceType.queen,
      event: VoiceEvent.attack,
      speaker: 'Vampir Kraliçe',
      warCry: 'Gecenin Kazananı!',
      text: 'Bu gecenin kazananı en başından belliydi.',
      elevenVoiceId: 'EXAVITQu4vr4xnSDxMaL',
      elevenStyleHint: 'Tatminkâr kraliçe zaferi',
      variationIndex: 6,
      durationMs: 3462,
    ),
  ],

  // ================= 6. BARBAR KRAL (barbarian_king_1 ... barbarian_king_6) =================
  PieceType.king: [
    VoiceLine(
      id: 'barbarian_king_1',
      kind: PieceType.king,
      event: VoiceEvent.march,
      speaker: 'Barbar Kral',
      warCry: 'Kuzeyin Tahtı!',
      text: 'Kuzeyin tahtı korkuyla değil, kan ve çelikle korunur!',
      elevenVoiceId: 'ErXwobaYiN019PkySvjV',
      elevenStyleHint: 'Gürleyen otoriter hükümdar',
      variationIndex: 1,
      durationMs: 4742,
    ),
    VoiceLine(
      id: 'barbarian_king_2',
      kind: PieceType.king,
      event: VoiceEvent.march,
      speaker: 'Barbar Kral',
      warCry: 'Sancaklar İleri!',
      text: 'Boruları çalın, sancakları kaldırın! Kralınız bizzat yürüyor!',
      elevenVoiceId: 'ErXwobaYiN019PkySvjV',
      elevenStyleHint: 'Orduyu coşturan kral yürüyüş emri',
      variationIndex: 2,
      durationMs: 5474,
    ),
    VoiceLine(
      id: 'barbarian_king_3',
      kind: PieceType.king,
      event: VoiceEvent.march,
      speaker: 'Barbar Kral',
      warCry: 'Kuzeyin Fırtınası!',
      text: 'Safları açın! Kuzeyin fırtınası geliyor!',
      elevenVoiceId: 'ErXwobaYiN019PkySvjV',
      elevenStyleHint: 'Savaş fırtınası narası',
      variationIndex: 3,
      durationMs: 3697,
    ),
    VoiceLine(
      id: 'barbarian_king_4',
      kind: PieceType.king,
      event: VoiceEvent.attack,
      speaker: 'Barbar Kral',
      warCry: 'HİLAL BALTAMIN ALTINDA EZİLİN!',
      text: 'HİLAL BALTAMIN ALTINDA EZİLİN!',
      elevenVoiceId: 'ErXwobaYiN019PkySvjV',
      elevenStyleHint: 'Yeri göğü inleten barbar kral narası',
      variationIndex: 4,
      durationMs: 2992,
    ),
    VoiceLine(
      id: 'barbarian_king_5',
      kind: PieceType.king,
      event: VoiceEvent.attack,
      speaker: 'Barbar Kral',
      warCry: 'Bedeli Kandır!',
      text: 'Kralınıza kafa tutmanın bedeli kandır!',
      elevenVoiceId: 'ErXwobaYiN019PkySvjV',
      elevenStyleHint: 'Demir iradeli komutan sesi',
      variationIndex: 5,
      durationMs: 3384,
    ),
    VoiceLine(
      id: 'barbarian_king_6',
      kind: PieceType.king,
      event: VoiceEvent.attack,
      speaker: 'Barbar Kral',
      warCry: 'Zafer Boruları!',
      text: 'Zafer borularını üfleyin! Düşman dize geldi!',
      elevenVoiceId: 'ErXwobaYiN019PkySvjV',
      elevenStyleHint: 'Muzaffer kral kükreyişi',
      variationIndex: 6,
      durationMs: 3776,
    ),
  ],
};

/// Verilen karakter sınıfı ve kura varyasyon indeksi (1..6) için ilgili VoiceLine kaydını döndürür.
VoiceLine moveVoiceLineOf(PieceType kind, int variationIndex, {bool isAttack = false}) {
  final list = kPieceMoveVoiceCatalog[kind];
  if (list == null || list.isEmpty) {
    return voiceLineOf(kind, isAttack ? VoiceEvent.attack : VoiceEvent.march);
  }
  final clampedIdx = (variationIndex - 1).clamp(0, list.length - 1);
  return list[clampedIdx];
}

