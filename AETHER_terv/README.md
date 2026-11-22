# AETHER – első tervcsomag

*Artificial Intelligence for Earth's Thermal & Ecological Recovery*

| Fájl | Mi van benne |
|---|---|
| `01_jatekterv.md` | A teljes játékterv: koncepció, játékciklus, erőforrások, korszakok, tudásfa, közös földgömb (megosztás vagy elzárkózás), offline mód, művészeti irány, motorválasztás, ütemterv, nyitott kérdések |
| `02_AI_es_kutatasi_motor.md` | Hogyan kerül valódi AI a játékba, és hogyan keres valódi, publikált cikkekben ellenőrizhető módon |
| `03_klimamodell_es_forrasok.md` | Az AETHER-mini klímamodell, paraméterei forrásokkal, eredmények, korlátok |
| `mockupok/aether_mockupok.html` | 4 animált képernyőterv, böngészőben megnyitható (fülekkel váltható) |
| `mockupok/*.png` | Ugyanez képként: földgömb, kutatólabor, AI-eredmény és publikáció, diplomácia |
| `prototipus/` | Működő Python kutatólabor: irodalomkeresés (OpenAlex, Semantic Scholar, arXiv, Crossref), AI-kivonatolás (Claude vagy helyi Ollama), idézet-ellenőrzés, klímamodell, tesztek |

**Őszintén:** a játék a tudományt modellezi, nem helyettesíti, és önmagában nem menti meg a Földet. Amit tehet: valódi irodalmat olvastat, megmutatja, mi működik és mi nem, és ellenőrizhető, megosztható összefoglalókat hoz létre.

Gyors kipróbálás (Python 3.10+ kell):

```
cd prototipus
python -m aether_lab demo
```

Licencek: a mockupban használt Pixelify Sans betűtípus SIL Open Font License alatt áll; a kontinenshatárok a Natural Earth (közkincs) adataiból készültek.
