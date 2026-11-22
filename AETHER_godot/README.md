# AETHER – Godot projektváz

Ez a játék első, futtatható váza Godot 4.7-hez. Egy főképernyőt tartalmaz:
forgó, festett pixeles földgömb (shader), kutatóállomások és szövetségi
vonalak, riasztások, kutatók listája, és egy **Kutatás** gomb, amely a Python
AETHER Lab klímamodelljét futtatja.

## Megnyitás

1. Indítsd el: `D:\Godot\Godot_v4.7.2-stable_win64.exe`
2. Projektkezelő → **Importálás** → válaszd ki: `D:\AETHER_C\AETHER_godot\project.godot`
3. Az első megnyitáskor a Godot beolvassa a képeket és betűket (pár másodperc).
4. **F5** (vagy a jobb felső ▶ gomb) elindítja a játékot.

## Mit tud most (1. mérföldkő)

Egy teljes kutatási kör, lépésről lépésre, a jobb oldali „Első küldetés” vezetésével:

1. **A mai Föld, valós adatokkal.** Induláskor a játék letölti a friss jelentéseket
   (GDACS katasztrófariasztások, NASA EONET események, NOAA CO2-mérés, NSIDC
   tengeri jég, levegőminőség és UV-index 30 nagyvárosban a Copernicus CAMS
   modellből, ezt modellbecslésként jelöljük). Minden tétel mellett dátum, hely, forrás és link van; a pöttyök a
   földgömbön kattinthatók. Ha egy forrás nem érhető el, a játék ezt kiírja, és
   nem pótolja kitalált adattal. Az adat a gépen mentésre kerül, offline is megmarad.
2. **Kutatás.** Kész kérdés-gombok (bioszén, kőzetmállasztás, erdősítés,
   aszálytűrő kukorica), utána AI választása: Claude (saját API-kulcs), helyi
   Ollama, vagy AI nélkül (csak cikklista). Futás közben látszik, hol tart.
3. **Eredmény hétköznapi nyelven.** Minden szám mellett egy mondat arról, mit
   jelent, és mennyire erős a bizonyíték. A „Részletek” gomb mögött a szó szerinti
   idézet és a cikk linkje.
4. **Jóváhagyás és terv.** Csak ellenőrzött szám kerülhet a modellbe. Csúszkák:
   CO2 nullára csökkentésének éve, metán, és a kikutatott karok.
5. **Mi lesz a Földdel?** Hőmérséklet-görbe 2100-ig bizonytalansági sávval, az
   alapesettel összevetve, és egy év-csúszka, amellyel a földgömb színe is változik
   (szemléltetés, nem pontos regionális előrejelzés).

### Önteszt

`Godot_v4.7.2-stable_win64_console.exe --path D:\AETHER_C\AETHER_godot -- --onteszt`
végigjátssza a kört (AI nélküli kutatással), és képernyőképeket ment ide:
`%APPDATA%\Godot\app_userdata\AETHER\aether_onteszt\`.

### Beállítások (környezeti változók)

- `ANTHROPIC_API_KEY`: Claude-kulcs (a játékban is megadható, nem mentjük el). Kell hozzá: `pip install anthropic`.
- `AETHER_RELIEFWEB_APPNAME`: a ReliefWeb (ENSZ) jelentésekhez jóváhagyott alkalmazásnév,
  igénylés: https://apidoc.reliefweb.int/parameters#appname
- `AETHER_OLLAMA_MODEL`: a helyi modell neve (alap: qwen3:14b).

## Felépítés

| Fájl | Szerep |
|---|---|
| `scenes/main.tscn` | fő jelenet (csak a gyökér; a felületet a kód építi) |
| `scripts/main.gd` | főképernyő, küldetés, valós események, év-csúszka, önteszt |
| `scripts/research_flow.gd` | kutatás lépésről lépésre |
| `scripts/plan_panel.gd` | a játékos terve (csúszkák) és a modell futtatása |
| `scripts/chart.gd` | hőmérséklet-görbe |
| `scripts/lab_bridge.gd` | Python-hívások háttérszálon |
| `scripts/ui.gd` | közös színek, betűk, kártyák |
| `scripts/globe.gd` | gömb, forgatás, állomások és vonalak rajzolása |
| `shaders/globe.gdshader` | pixeles földgömb: fény, felhők, napcsillogás, éjszakai városfények, Bayer-dither |
| `assets/earth_*.png` | előre „sütött” térképek (Natural Earth alapú szárazföld) |
| `assets/fonts/` | Atkinson Hyperlegible (szöveg), Pixelify Sans (címek) – mindkettő SIL Open Font License |

## Őszintén

A projekt ezen a gépen fut (Godot 4.7.2), az önteszt hiba nélkül végigmegy.
Az élő AI-kutatást (Claude vagy Ollama) még nem próbáltuk ki; AI nélkül a
kutatás valódi cikkeket listáz, de számot nem emel ki.

A kezdőképernyő eseményei és mérései valódiak és linkkel ellenőrizhetők.
A vízminőség és az országonkénti élelmiszerhiány még hiányzik (a ReliefWeb-engedély után jön).
