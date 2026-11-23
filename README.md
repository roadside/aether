# AETHER

Klímajáték 12 éves kortól. Te vagy a világ klímatudósa: kutatsz, a bizonyítékaiddal meggyőzöd a világ hat nagy országcsoportját, és 2100-ban meglátod, milyen lett a Földed.

## Egy játék

- 2026-tól 2100-ig tizenöt kör, egy kör öt év, körönként három lépés.
- **Kutatás:** témakört választasz, három valódi kérdésből egyet kutatsz ki. Ebből bizonyíték-kártya lesz, valódi tudományos forrásokkal.
- **Tárgyalás:** minden országcsoport mástól tart. Olyan kártyával győzheted meg, amely az ő aggodalmára felel.
- **Idő:** a Föld és a görbe megmutatja, mit értél el. Minden játékban más a Föld: az érzékenysége és a billenőpontjai rejtve vannak.
- **Vége:** két Föld egymás mellett. A tiéd, és az, amelyik akkor lett volna, ha semmi sem változik.

## Mi valódi, és mi játékszabály?

Valódi adat:
- A klímamodell (`scripts/model.gd`): a kibocsátott CO2 és a melegedés közti arány (IPCC AR6), a metán rövid élettartama, kétrétegű hőmodell. A Föld érzékenysége a tudományos sávon belül játékonként más.
- Az országcsoportok CO2-kibocsátása: Global Carbon Budget 2026, 2025-ös adat (Our World in Data).
- A metán részesedése: Jones és mtsai 2025 (Our World in Data), 2024-es adat.
- A billenőpontok küszöbsávjai: Armstrong McKay és mtsai 2022, Science.
- A CO2-kivonás lehetséges mértéke: Fuss és mtsai 2018 (a sáv alsó értékével számolunk).
- A tengerszint 2100-ban: IPCC AR6 WG1 9.9 táblázat.
- A kártyák kérdései, magyarázatai és forrásai (`temak/`).

Játékszabály (nem a valóság leírása):
- A tárgyalás menete, az aggodalmak mondatai, hogy hány kártya kell egy vállaláshoz.
- A megingás és a jövő hírei (hőhullám, aszály, áradás, erdőtűz).
- A billenőpontok rejtett küszöbe: a tudományos sávból sorsoljuk, a mai melegedés fölötti részéből. A küszöb átlépése egyelőre nem hat vissza a hőmérsékletre.
- A csoportok részesedése a teljes mai kibocsátásra vonatkozik (a földhasználatét is arányosan osztjuk szét).
- A világ többi része a hat csoport átlagát követi.

## Futtatás

Godot 4.7-tel nyisd meg a `project.godot` fájlt. A nyitány zenéje a `sajat_zene/intro.wav`, ha ott van (nem része a tárolónak); különben a beépített handpan szól.

Ellenőrzés: `godot --path . -- --onteszt --hu` végigjátszik egy játékot, és képeket ment; `godot --headless -s tools/jatek_teszt.gd` a szabályokat, `tools/modell_teszt.gd` a klímamodellt ellenőrzi.
