// Flutter create'in varsayılan MyApp testinin bu oyuna eklenmesini önler.
// 3D GPU sahnesi widget testinde değil, Windows/Android çalıştırmasında sınanır.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wizard_hex_chess_dart3d/data/game_models.dart';
import 'package:wizard_hex_chess_dart3d/game/hex_board.dart';
import 'package:wizard_hex_chess_dart3d/ui/launch_screen.dart';

void main() {
  test('Dart 3D sahnesinin tahta modeli 91 hücre üretir', () {
    expect(HexBoard.cells.length, 91);
  });

  testWidgets('Açılış ekranında 3 kişilik masa için tahta boyutu seçilir; 2 kişilik her zaman Klasik',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final started = <(BoardVariant, BoardSize)>[];
    await tester.pumpWidget(MaterialApp(
      home: WizardLaunchScreen(
        bootReady: true,
        bootStatus: '',
        bootProgress: 1,
        profile: const PlayerProfileStats(),
        activeMatch: null,
        diagnostics: null,
        onResumeSavedMatch: () {},
        onStartVariant: (v, s) => started.add((v, s)),
        onOpenArchive: () {},
        onOpenSettings: () {},
        initialBoardSize3P: BoardSize.wide,
      ),
    ));
    await tester.pump();

    // Kayıtlı tercih (Geniş) seçili gelir ve alt başlıkta görünür
    expect(find.textContaining('Geniş Tahta'), findsOneWidget);
    for (final s in BoardSize.values) {
      expect(find.text('${s.label} • ${s.cellCount}'), findsOneWidget);
    }

    await tester.tap(find.text('Dev • 217'));
    await tester.pump();
    expect(find.textContaining('Dev Tahta'), findsOneWidget);
    expect(find.textContaining('217 hücre'), findsOneWidget);

    await tester.tap(find.text('3 KİŞİLİK AMFİ MASASI'));
    await tester.tap(find.text('2 KİŞİLİK AMFİ DÜELLOSU'));
    expect(started, [
      (BoardVariant.threePlayer, BoardSize.giant),
      (BoardVariant.twoPlayer, BoardSize.classic),
    ]);
  });
}
