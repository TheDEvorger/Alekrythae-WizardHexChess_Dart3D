# ElevenLabs 144 Replikli Profesyonel Karakter Ses Paketi Rehberi

Oyun motoru, **her karakter için 24 adet olmak üzere toplam 144 ses dosyasını** (`voices/` klasöründe) dinamik olarak destekler. Oyunu yeniden başlatmaya veya derlemeye gerek kalmadan dosyaları klasöre attığınız anda algılanır ve peş peşe aynı sesin çalmasını önleyen **anti-tekrar rastgele varyasyon motoru** ile oynatılır.

---

## 📊 Karakter Başına 24 Ses Dağılımı

Her karakter için tam olarak istediğiniz gibi 4 ana oyun olayı ve her olay için 6'şar varyasyon:

| Oyun Olayı | Replik Sayısı | Dosya Adı Deseni | Ne Zaman Çalacak? |
| :--- | :---: | :--- | :--- |
| 🛡️ **Select** | **6** | `[rol]_select_1.mp3` ... `_6.mp3` | Karakter seçildiğinde / dokunulduğunda |
| 👞 **March** | **6** | `[rol]_march_1.mp3` ... `_6.mp3` | Karakter taşındığında / yürüme emrinde |
| ⚔️ **Attack** | **6** | `[rol]_attack_1.mp3` ... `_6.mp3` | Düşman taşı yendiğinde / saldırı narası |
| 👑 **Victory** | **6** | `[rol]_victory_1.mp3` ... `_6.mp3` | Maç kazanıldığında / şah mat anında |
| **Toplam** | **24** | *(6 Karakter x 24 = 144 Ses)* | |

---

## 🪓 1. Barbar Kral (`king`) - Kuzey Hükümdarı
**ElevenLabs Önerilen Ses Profili:** *Antoni / George* (Gürleyen, otoriter, derinden gelen savaş kralı tonu)

* **Select (1-6):**
  1. `king_select_1.mp3`: *"Kuzeyin tahtı korkuyla değil, kan ve çelikle korunur!"*
  2. `king_select_2.mp3`: *"Kralınız konuşuyor! Gözleriniz tahtımda olsun!"*
  3. `king_select_3.mp3`: *"Savaş boruları çalsın, kralın buyruğu kesindir!"*
  4. `king_select_4.mp3`: *"Kılıcım bilenmiş, emrimi bekleyin!"*
  5. `king_select_5.mp3`: *"Buz diyarı titreyecek, kralınız cephede!"*
  6. `king_select_6.mp3`: *"Kralınızın sancağı altında birleşin!"*
* **March (1-6):**
  1. `king_march_1.mp3`: *"Boruları çalın, sancakları kaldırın! Kralınız bizzat yürüyor!"*
  2. `king_march_2.mp3`: *"Adımlarım yeri göğü inletsin, ilerleyin!"*
  3. `king_march_3.mp3`: *"Cepheye doğru! Kralın gazabından kaçış yok!"*
  4. `king_march_4.mp3`: *"Safları açın! Kuzeyin fırtınası geliyor!"*
  5. `king_march_5.mp3`: *"Bu topraklar kralın adımlarıyla mühürlenecek!"*
  6. `king_march_6.mp3`: *"Kralınız önde, zafer arkamızda!"*
* **Attack (1-6):**
  1. `king_attack_1.mp3`: *"KUZEYİN ÖFKESİYLE PARÇALAN! Baltamdan kurtuluş yok!"*
  2. `king_attack_2.mp3`: *"HİLAL BALTAMIN ALTINDA EZİLİN!"*
  3. `king_attack_3.mp3`: *"Kralınıza kafa tutmanın bedeli kandır!"*
  4. `king_attack_4.mp3`: *"DİZ ÇÖKÜN YA DA YOK OLUN!"*
  5. `king_attack_5.mp3`: *"GÜCÜMÜN KARŞISINDA DAĞLAR BİLE DURAMAZ!"*
  6. `king_attack_6.mp3`: *"PARÇALA VE YOK ET! TAHT BENİMDİR!"*
* **Victory (1-6):**
  1. `king_victory_1.mp3`: *"Tahtımın ve baltamın önünde herkes diz çökecek!"*
  2. `king_victory_2.mp3`: *"Zafer kuzeyindir! Krallığım ebediyen sürecek!"*
  3. `king_victory_3.mp3`: *"İşte kralın kudreti! Meydan bizimdir!"*
  4. `king_victory_4.mp3`: *"Bu amfi yalnızca gerçek hükümdarı tanır!"*
  5. `king_victory_5.mp3`: *"Kuzeyin tacı bir kez daha kanla parladı!"*
  6. `king_victory_6.mp3`: *"Zafer borularını üfleyin! Düşman dize geldi!"*

---

## 🩸 2. Vampir Kraliçe (`queen`) - Kan Kontesi
**ElevenLabs Önerilen Ses Profili:** *Bella / Freya* (Aristokrat, zarif, hipnotize edici gotik kadın)

* **Select (1-6):**
  1. `queen_select_1.mp3`: *"Tatlı kan kokusu rüzgârda dans ediyor... Kimi kurban seçtik?"*
  2. `queen_select_2.mp3`: *"Karanlığın kraliçesi emrinizi dinliyor... Acele edin."*
  3. `queen_select_3.mp3`: *"Gecenin gölgeleri fısıldıyor... Av vakti yaklaştı."*
  4. `queen_select_4.mp3`: *"Kalp atışlarını duyabiliyorum... Ne kadar da hızlı çarpıyor."*
  5. `queen_select_5.mp3`: *"Benimle dans etmeye cesaretin var mı, ölümlü?"*
  6. `queen_select_6.mp3`: *"Güzellik ve ölüm... İkisi de parmaklarımın ucunda."*
* **March (1-6):**
  1. `queen_march_1.mp3`: *"Kızıl gece benim pelerinimdir; sessizce süzülüyorum."*
  2. `queen_march_2.mp3`: *"Gölgelerin içinden geliyorum, kimse fark edemez."*
  3. `queen_march_3.mp3`: *"Karanlık adımlarımı saklar, rüzgâr nefesimi taşır."*
  4. `queen_march_4.mp3`: *"Kurbanıma doğru zarafetle süzülüyorum."*
  5. `queen_march_5.mp3`: *"Gece benimle yürüyor... Kaçacak yeriniz yok."*
  6. `queen_march_6.mp3`: *"Ay ışığı yolumu aydınlatıyor, ilerliyorum."*
* **Attack (1-6):**
  1. `queen_attack_1.mp3`: *"SON DAMLASINA KADAR! Yarasalarım, ziyafet vakti!"*
  2. `queen_attack_2.mp3`: *"Damarlarındaki o tatlı yaşam özü artık bana ait!"*
  3. `queen_attack_3.mp3`: *"HAYKIR VE KURUSA DÖN! KARANLIĞA BOĞUL!"*
  4. `queen_attack_4.mp3`: *"Ne kadar da narin bir boyun... Tadına doyamayacağım!"*
  5. `queen_attack_5.mp3`: *"KAN VE GÖLGE ADINA! YOK OL!"*
  6. `queen_attack_6.mp3`: *"SON NEFESİN BENİM NEFESİM OLACAK!"*
* **Victory (1-6):**
  1. `queen_victory_1.mp3`: *"Ne zarif bir son... Gücün artık damarlarımda akıyor."*
  2. `queen_victory_2.mp3`: *"Gece kraliçesine boyun eğdi... Ziyafet tamamlandı."*
  3. `queen_victory_3.mp3`: *"Kızıl tahtım bir kurbanla daha taçlandı."*
  4. `queen_victory_4.mp3`: *"Ölümlülerin kaderi hep aynı... Solup gitmek."*
  5. `queen_victory_5.mp3`: *"Bu gecenin kazananı en başından belliydi."*
  6. `queen_victory_6.mp3`: *"Kadehim zafer kanıyla doldu... Kusursuz."*

---

## ⚡ 3. Kadın Savaş Devi (`rook`) - Valkür Titan
**ElevenLabs Önerilen Ses Profili:** *Rachel / Domi* (Güçlü, tok, heybetli amazon/dev kadın savaşçı)

* **Select (1-6):** `rook_select_1.mp3` ... `_6.mp3` (Balyoz, güç, titan naraları)
* **March (1-6):** `rook_march_1.mp3` ... `_6.mp3` (Yeri sarsan yürüyüş komutları)
* **Attack (1-6):** `rook_attack_1.mp3` ... `_6.mp3` ("DAĞLARI BİLE UN UFAK EDERİM! EZİLİN!")
* **Victory (1-6):** `rook_victory_1.mp3` ... `_6.mp3` ("Bana kafa tutanların sonu hep aynı... Toz ve toprak!")

---

## 🐉 4. Antik Ejderha (`bishop`) - Antik Ejder
**ElevenLabs Önerilen Ses Profili:** *Arnold / Marcus* (Derin gürleyen sürüngen, yankılı antik ejderha)

* **Select (1-6):** `bishop_select_1.mp3` ... `_6.mp3` ("Kanatlarım göğü karartır, ateşim kayaları eritir!")
* **March (1-6):** `bishop_march_1.mp3` ... `_6.mp3` (Göklere yükseliş, fırtınanın içinden süzülüş)
* **Attack (1-6):** `bishop_attack_1.mp3` ... `_6.mp3` ("KAVRUL VE KÜL OL! Antik ejder ateşinden kurtuluş yok!")
* **Victory (1-6):** `bishop_victory_1.mp3` ... `_6.mp3` ("Geriye yalnızca kor, duman ve küller kaldı.")

---

## 🗡️ 5. Suikastçi (`knight`) - Gölge Avcısı
**ElevenLabs Önerilen Ses Profili:** *Josh / Sam* (Karanlık, keskin fısıltılı suikastçi erkek)

* **Select (1-6):** `knight_select_1.mp3` ... `_6.mp3` ("Gölgeden hızlı, nefesten sessiz... Hedefi göster.")
* **March (1-6):** `knight_march_1.mp3` ... `_6.mp3` ("Beni fark ettiklerinde bıçaklarım çoktan konuşmuş olacak.")
* **Attack (1-6):** `knight_attack_1.mp3` ... `_6.mp3` ("Arkandayım! İkiz bıçaklarımdan kaçış yok!")
* **Victory (1-6):** `knight_victory_1.mp3` ... `_6.mp3` ("Temiz darbe... Geriye tek bir iz bile kalmadı.")

---

## 🛡️ 6. Kalkan Muhafızı (`pawn`) - Zırhlı Öncü Şövalye
**ElevenLabs Önerilen Ses Profili:** *Adam / Antony* (Disiplinli, tok sesli zırhlı öncü er)

* **Select (1-6):** `pawn_select_1.mp3` ... `_6.mp3` ("Kalkanlar kenetlensin! Emrinizi bekliyorum komutanım!")
* **March (1-6):** `pawn_march_1.mp3` ... `_6.mp3` ("Safları bozmadan ileri! Çelik adımlarımızla cepheyi tutuyoruz!")
* **Attack (1-6):** `pawn_attack_1.mp3` ... `_6.mp3` ("Demir ve onur adına! Teberimin ucunda yıkıl karşımdan!")
* **Victory (1-6):** `pawn_victory_1.mp3` ... `_6.mp3` ("Düşman devrildi! Kalkan hattı sarsılmaz.")

---

## 💡 Dosya İsimlendirme Kuralı

Dosyalarınızı `voices/` klasörüne şu formatlardan birinde kaydedebilirsiniz (ikisi de otomatik tanınır):
- `king_select_1.mp3` veya `king_select1.mp3`
- `king_march_3.mp3` veya `king_march3.mp3`
- `rook_attack_5.mp3` veya `rook_attack5.mp3`

Klasöre tek bir dosya (`king_select.mp3`) atsanız da, tüm 24 varyasyonu koysanız da oyun motoru anında algılar ve hiçbir konfigürasyon gerektirmeden oynatır!
