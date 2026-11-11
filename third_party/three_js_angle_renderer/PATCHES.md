# three_js_angle_renderer 0.0.1 — yamalı kopya

Kaynak: https://pub.dev/packages/three_js_angle_renderer (MIT, bkz. `LICENSE`).
Projeye `pubspec.yaml` içindeki `dependency_overrides` ile bağlanır.
Yamalı satırlar kodda `[WizardHexChess yaması]` diye işaretlidir.

## 1. Her karede shader programı aranması (takılma)

`lib/renderers/renderer.dart` → `setProgram`: orijinal kod
`toneMapping = toneMapping;` yazarak yerel değişkeni kendine atıyordu. Sonuç
hep `NoToneMapping` kaldığı için, ACES ton eşlemesiyle derlenmiş her malzeme
her çizimde "program değişti" sayılıyor ve `getProgram()` (yaklaşık 100 alanlı
parametre nesnesi + uzun önbellek anahtarı) her karede her nesne için yeniden
çalışıyordu. Düzeltme: `toneMapping = this.toneMapping;`

`lib/angle/angle_programs.dart` → `getParameters`: ton eşleme parametresi
three.js'teki gibi yalnızca ekrana (veya ekran yerine geçen hedefe) çizerken
uygulanır; `setProgram` kontrolüyle tutarlı olsun diye.

## 2. Windows'ta yarım karelerin ekrana gelmesi (yırtılma / titreme)

`lib/three_viewer.dart`: `Settings.tearFreeComposite`.

flutter_angle, Windows'ta sahneyi Flutter'ın da okuduğu tek bir paylaşımlı D3D
dokusuna çizer; çift tampon ve senkronizasyon yoktur. Flutter kareyi çizim
ortasında alırsa arka planı temizlenmiş ama saydam katmanları (bulut, yağmur,
sis) henüz çizilmemiş bir kare görünür.

Açıkken sahne önce ekran dışı bir hedefe eksiksiz çizilir, ardından tek bir tam
ekran üçgenle paylaşılan yüzeye kopyalanır; paylaşılan yüzey hiç temizlenmez.
Hedef `isXRRenderTarget` olarak işaretlenir ve dokusunun renk uzayı ekranınkiyle
aynıdır; iç format düz `RGBA8`'dir. Böylece malzemeler ekrana çizer gibi aynı
renk kodlaması ve ton eşlemesiyle çizilir, görüntü birebir aynıdır.

## 3. Pencere büyütülüp küçültülünce bozuk görüntü (pikselli, yakınlaşmış köşe)

`lib/three_viewer.dart` → `_ensureCompositeTarget`: ekran dışı hedef artık
`setSize` ile değil, boyut değişince baştan kurularak yeniden boyutlanır.

three_js_core'da `RenderTarget.setSize`, GPU dokusunu `dispose()` ile serbest
bırakıp yeni boyutta yeniden ayırtır; ancak `RenderTarget.dispose()` yalnızca
İLK çağrıda çalışır (`_didDispose`). İkinci yeniden boyutlandırmadan itibaren
GPU dokusu eski boyutta kalıyor, three.js ise yeni görüş alanıyla çiziyordu:
ekranda sahnenin bir köşesi pikselli ve yakınlaşmış görünüyordu.

`lib/three_viewer.dart` → `_onWindowResize` / `animate`: yeniden boyutlandırma
sürerken (paylaşılan D3D yüzeyi `await angle.resize()` içinde değişirken) kare
çizilmez; yarıda kalan kare beklenir, üst üste gelen istekler sıraya alınır.
Gecikme 300 ms → 150 ms.

## 4. Android ilk karede (0, 0) görünüm alanı nedeniyle `no texture width` hatası

`lib/three_viewer.dart` → `initSize` / `_onWindowResize`: Android soğuk açılışında
ilk `build` sırasında `MediaQuery.of(context).size` geçici olarak `(0, 0)`
gelebiliyordu. Eski kod `screenSize`'ı `(0, 0)` olarak kilitleyip `initPlatformState()`
başlattığı için `flutter_angle.createTexture` sıfır genişlikle çağrılıyor ve
`PlatformException(no texture width)` hatasıyla 3B kurulum yarıda kalıyordu.

Artık `initSize` pozitif bir piksel boyutu gelene kadar GL/doku kurulumunu
başlatmaz ve `_onWindowResize` sıfır boyutlu yeniden boyutlandırmaları yoksayar.

## 5. Android'de dokunup döndürünce görüntünün tek renge düşmesi (`clientHeight == 0`)

`lib/three_viewer.dart` → `build`: Madde 4 kurulumu erteliyordu ama `build()` yine
de ilk `(0, 0)` karede `core.Peripherals(key: globalKey)` widget'ını ağaca
bağlıyordu. `three_js_core`'daki `PeripheralsState`, widget boyutunu yalnızca
`initState()` içindeki tek seferlik `addPostFrameCallback` ile okuyup önbelleğe
alır (`_clientWidth = 0`, `_clientHeight = 0`) ve bir daha güncellemez.

Kullanıcı Android'de ekrana dokunup sürüklediğinde `OrbitControls.handleTouchMoveRotate`
açı farkını `element.clientHeight` (`0.0`) değerine bölerek kamerayı `NaN/Infinity`
konumuna fırlatıyor, tüm 3B sahne kaybolup ekran tek renk arka plana düşüyordu.

Artık `build()`, `_initStarted` ve pozitif `screenSize` oluşana kadar `Peripherals`
widget'ını bağlamaz. Buna ek olarak oyun tarafında `SafeOrbitControls` canlı
`RenderBox` boyutunu okuyup sıfır/NaN koruması uygular.
