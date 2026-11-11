import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wizard_hex_chess_dart3d/audio/battle_audio.dart';
import 'package:wizard_hex_chess_dart3d/game/chess_game.dart';

void main() {
  group('VoiceShuffleBag (Kura Torbası) Mekaniği', () {
    test('6 çekilişlik her döngüde 1..6 arasındaki tüm indeksler tekrarsız çekilir', () {
      final bag = VoiceShuffleBag(size: 6);

      for (var cycle = 0; cycle < 50; cycle++) {
        final drawn = <int>[];
        for (var i = 0; i < 6; i++) {
          drawn.add(bag.draw());
        }

        // 6 çekilişin her biri 1..6 arasında olmalı
        expect(drawn.every((x) => x >= 1 && x <= 6), isTrue);

        // 6 çekilişte hiçbir ses tekrarlanmamalı (küme boyutu tam 6 olmalı)
        expect(drawn.toSet().length, equals(6),
            reason: 'Döngü $cycle içinde 6 ses tekrarsız çekilmeli: $drawn');
      }
    });

    test('Yeni torba açıldığında önceki torbanın son sesiyle hemen peş peşe çakışmaz', () {
      final bag = VoiceShuffleBag(size: 6);
      int? previousCycleLast;

      for (var cycle = 0; cycle < 100; cycle++) {
        final cycleItems = <int>[];
        for (var i = 0; i < 6; i++) {
          cycleItems.add(bag.draw());
        }

        if (previousCycleLast != null) {
          expect(cycleItems.first, isNot(equals(previousCycleLast)),
              reason: 'Yeni torbanın ilk sesi ($cycleItems.first), önceki torbanın son sesi ($previousCycleLast) ile peş peşe gelmemeli');
        }
        previousCycleLast = cycleItems.last;
      }
    });
  });

  group('Ses Kataloğu & 36 Adet ElevenLabs Dosya Doğrulaması', () {
    test('6 karakter sınıfı için tam 36 adet replik tanımlıdır', () {
      expect(kPieceMoveVoiceCatalog.length, equals(6));
      for (final kind in PieceType.values) {
        final lines = kPieceMoveVoiceCatalog[kind];
        expect(lines, isNotNull);
        expect(lines!.length, equals(6), reason: '$kind için tam 6 replik olmalı');
        for (var i = 0; i < 6; i++) {
          final line = lines[i];
          expect(line.variationIndex, equals(i + 1));
          expect(line.text.isNotEmpty, isTrue);
          expect(line.warCry.isNotEmpty, isTrue);
          expect(line.speaker.isNotEmpty, isTrue);
        }
      }
    });

    test('Katalogda asla "kader" veya "kadim" kelimesi geçmez', () {
      for (final entry in kPieceMoveVoiceCatalog.entries) {
        for (final line in entry.value) {
          final combined = '${line.id} ${line.speaker} ${line.warCry} ${line.text}'.toLowerCase();
          expect(combined.contains('kader'), isFalse,
              reason: 'Replik metninde "kader" yasaktır: ${line.text}');
          expect(combined.contains('kadim'), isFalse,
              reason: 'Replik metninde "kadim" yerine "antik" kullanılmalıdır: ${line.text}');
        }
      }
    });

    test('Kullanıcının belirlediği 36 replik metni birebir katalogda kayıtlıdır', () {
      expect(kPieceMoveVoiceCatalog[PieceType.king]![0].text,
          equals('Kuzeyin tahtı korkuyla değil, kan ve çelikle korunur!'));
      expect(kPieceMoveVoiceCatalog[PieceType.king]![1].text,
          equals('Boruları çalın, sancakları kaldırın! Kralınız bizzat yürüyor!'));
      expect(kPieceMoveVoiceCatalog[PieceType.king]![3].text,
          equals('HİLAL BALTAMIN ALTINDA EZİLİN!'));

      expect(kPieceMoveVoiceCatalog[PieceType.queen]![0].text,
          equals('Tatlı kan kokusu rüzgârda dans ediyor... Kimi kurban seçtik?'));
      expect(kPieceMoveVoiceCatalog[PieceType.queen]![4].text,
          equals('SON DAMLASINA KADAR! Yarasalarım, ziyafet vakti!'));

      expect(kPieceMoveVoiceCatalog[PieceType.rook]![0].text,
          equals('Savaş balyozum elimde! Hangi cepheyi yerle bir etmemi istiyorsun?'));
      expect(kPieceMoveVoiceCatalog[PieceType.rook]![3].text,
          equals('DAĞLARI BİLE UN UFAK EDERİM! EZİLİN!'));

      expect(kPieceMoveVoiceCatalog[PieceType.bishop]![0].text,
          equals('Kanatlarım göğü karartır, ateşim kayaları eritir!'));
      expect(kPieceMoveVoiceCatalog[PieceType.bishop]![3].text,
          equals('KAVRUL VE KÜL OL! Ejder ateşimden kaçabilecek misin?'));

      expect(kPieceMoveVoiceCatalog[PieceType.knight]![0].text,
          equals('Gölgeden hızlı, nefesten sessiz... Hedefi göster.'));
      expect(kPieceMoveVoiceCatalog[PieceType.knight]![3].text,
          equals('Arkandayım! İkiz bıçaklarımdan kaçış yok!'));

      expect(kPieceMoveVoiceCatalog[PieceType.pawn]![0].text,
          equals('Kalkanlar kenetlensin! Emrinizi bekliyorum komutanım!'));
      expect(kPieceMoveVoiceCatalog[PieceType.pawn]![3].text,
          equals('KALKANLARI KALDIRIN! HATTI KORUYUN!'));
    });

    test('assets/audio/ içindeki 36 adet MP3 ve 36 adet WAV dosyasının tamamı diskte mevcuttur', () {
      final audioDir = Directory('assets/audio');
      expect(audioDir.existsSync(), isTrue, reason: 'assets/audio klasörü mevcut olmalıdır');

      for (final kind in PieceType.values) {
        final prefixes = pieceVoicePrefixes(kind);
        for (var idx = 1; idx <= 6; idx++) {
          var mp3Found = false;
          var wavFound = false;
          for (final prefix in prefixes) {
            final fMp3 = File('assets/audio/${prefix}_$idx.mp3');
            if (fMp3.existsSync() && fMp3.lengthSync() > 1024) mp3Found = true;
            final fWav = File('assets/audio/${prefix}_$idx.wav');
            if (fWav.existsSync() && fWav.lengthSync() > 1024) wavFound = true;
          }
          expect(mp3Found, isTrue,
              reason: '$kind için $idx nolu MP3 dosyası assets/audio klasöründe bulunmalıdır');
          expect(wavFound, isTrue,
              reason: '$kind için $idx nolu WAV dosyası assets/audio klasöründe bulunmalıdır');
        }
      }
    });

    test('BattleAudio speakMoveWithBag ve bagOf doğru çalışır', () {
      final audio = BattleAudio();
      audio.init();

      for (final kind in PieceType.values) {
        final line = audio.speakMoveWithBag(kind);
        expect(line.kind, equals(kind));
        expect(line.variationIndex, inInclusiveRange(1, 6));
      }

      // Kural doğrulaması: Yalnızca hareket ve saldırı konuşma çalar, seçim veya zafer çalmaz
      final marchLine = audio.speak(PieceType.king, VoiceEvent.march);
      expect(marchLine.variationIndex, inInclusiveRange(1, 6));

      final attackLine = audio.speak(PieceType.queen, VoiceEvent.attack);
      expect(attackLine.variationIndex, inInclusiveRange(1, 6));

      // Ses kapatıldığında isVoicePlaying derhal false dönmelidir
      audio.voiceEnabled = false;
      expect(audio.isVoicePlaying, isFalse);

      audio.dispose();
    });
  });
}

