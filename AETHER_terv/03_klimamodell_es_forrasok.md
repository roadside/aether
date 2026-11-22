# AETHER-mini klímamodell és forrásai

> **Figyelmeztetés:** az AETHER-mini oktatási és játékmodell. Arra jó, hogy egy beavatkozás *irányát és nagyságrendjét* bizonytalansági sávval megmutassa. Nem kutatási minőségű előrejelzés, és nem szakpolitikai javaslat. Kód: `prototipus/aether_lab/climate.py`.

## 1. Felépítés

Évenkénti lépés 2025-től 2100-ig.

**1. CO2 (hosszú élettartamú):** a melegedés arányos a kumulatív nettó CO2-kibocsátással (TCRE):

  T_CO2(t) = T_2025 + TCRE × Σ (kibocsátás − eltávolítás)

Feltevés: nettó nulla után a hőmérséklet nagyjából stagnál (nulla-kibocsátási elköteleződés, ZEC ≈ 0; IPCC AR6 és MacDougall et al. 2020 szerint ez a legjobb becslés, ±0,3 °C bizonytalansággal).

**2. Rövid élettartamú hatások** (metán, aeroszolok, sztratoszférikus aeroszol) a *mai szinthez képesti* sugárzási kényszer-eltérésként (ΔF, W/m²) egy kétrétegű energiamérleg-modellt hajtanak (Held et al. 2010; Geoffroy et al. 2013):

  C · dT/dt = ΔF − λ·T − γ·(T − T_mély)
  C_mély · dT_mély/dt = γ·(T − T_mély)

**3. Metán:** a kibocsátás-csökkentés (Tg/év) koncentráció-eltérést okoz (1 ppb ≈ 2,78 Tg; perturbációs élettartam 11,8 év), a kényszer a Myhre et al. (1998) képlet deriváltjával, ×1,5 közvetett hatással (ózon, sztratoszférikus vízgőz – FELTEVÉS).

**4. Aeroszolok:** néhány napos élettartam, azonnali hatás. Szulfát ERF −0,9 W/m², korom +0,1 W/m² (IPCC AR6 WG1, 1750–2019). A légszennyezés-csökkentés a szulfát hűtő hatását is megszünteti.

**5. Sztratoszférikus aeroszol (SAI):** −0,15 W/m² / (Tg SO2/év), sáv 0,08–0,25. **Nagy bizonytalanság**, a játékban mindig így jelölve.

**6. Termés:** hozamváltozás %/°C (a 2025-ös szinthez képesti további melegedésre), Zhao et al. (2017): búza −6,0, rizs −3,2, kukorica −7,4, szója −3,1. Az alkalmazkodás ennek egy részét ellensúlyozza. Korlát: a CO2-trágyázást, a csapadékot és SAI esetén a csökkent napfényt (Proctor et al. 2018) nem veszi figyelembe.

**7. Bizonytalanság:** minden futás három készlettel megy:

| Készlet | TCRE (°C / 1000 GtCO2) | ECS (°C) |
|---|---|---|
| alacsony | 0,27 | 2,5 |
| közép | 0,45 | 3,0 |
| magas | 0,63 | 4,0 |

(IPCC AR6 WG1 valószínű tartományok.)

## 2. Kiinduló értékek

| Mennyiség | Érték | Forrás |
|---|---|---|
| Emberi eredetű melegedés 2024 | 1,36 °C (megfigyelt 1,52 °C) | Forster et al. 2025, *Indicators of Global Climate Change 2024*, ESSD |
| Kiinduló T 2025 elején | 1,39 °C | az előző + ~0,27 °C/évtized (ugyanott) |
| CO2-kibocsátás 2025 | 42,2 GtCO2/év (fosszilis 38,1 + földhasználat 4,1) | Global Carbon Budget 2025 (Friedlingstein et al.) |
| Légköri CO2 2025 | 425,7 ppm | Global Carbon Budget 2025 |
| Maradék szénkeret 1,5 °C-hoz (50%) | 130 GtCO2 2025 elejétől; 170 GtCO2 2026 elejétől a GCB 2025 szerint | Forster et al. 2025; GCB 2025 |
| Antropogén metán | ~370 Tg/év (FELTEVÉS, a Global Methane Budget nagyságrendje) | Saunois et al., Global Methane Budget |
| Kétrétegű modell | C = 7,3; C_mély = 106 W·év·m⁻²·K⁻¹; γ = 0,73 W·m⁻²·K⁻¹ | Geoffroy et al. 2013 (CMIP5-átlag) |
| CO2-duplázás kényszere | 3,93 W/m² | IPCC AR6 WG1 7. fejezet |
| CO2-eltávolítási plafonok 2050-re (GtCO2/év) | erdősítés 0,5–3,6; BECCS 0,5–5; DACCS 0,5–5; kőzetmállasztás 2–4; bioszén 0,5–2; talajszén ≤5 | Fuss et al. 2018 |

## 3. Eredmények (beépített forgatókönyvek)

`python -m aether_lab demo` kimenete (2025-ös kiindulás). Formátum: közép (alacsony–magas).

| Forgatókönyv | T 2050 | T 2100 | Csúcs | 1,5 °C átlépése | 2,0 °C átlépése |
|---|---|---|---|---|---|
| 0. Alapeset (42 GtCO2/év marad) | 1,88 (1,69–2,08) | 2,83 (2,26–3,41) | 2100-ig nő | 2030 | 2057 |
| 1. Szárazságtűrő növény + víztakarékosság | 1,88 | 2,83 | ugyanaz | 2030 | 2057 |
| 2. Légszennyezés −80% (szulfát + korom) | 2,20 (1,97–2,46) | 3,19 | 2100-ig nő | 2029 | 2042 |
| 3. Metán −45% 2030-ig | 1,69 (1,51–1,85) | 2,57 | 2100-ig nő | 2033 | 2069 |
| 4. Nettó zéró CO2 2050 | 1,64 (1,54–1,74) | 1,64 | 1,64 (2049) | 2031 | – |
| 5. Kombinált csomag | 1,74 (1,63–1,85) | 1,59 (1,54–1,66) | 1,75 (2045) | 2029 | – |
| 6. Csak SAI, 2070-ben leáll | 1,30 | 2,79 | – | 2030 | 2072 |

Kukoricahozam 2050-ben (a 2025-ös szinthez képest, közép): alapeset −3,7%, alkalmazkodással −2,6%, nettó zéróval −1,8%.

**Ellenőrzések a kódban (offline tesztek):**
- 45%-os metáncsökkentés 2045-re ~0,17 °C-ot ment egy *állandó* alapeshez képest. A Global Methane Assessment (UNEP/CCAC 2021) ~0,3 °C-ot ad 2045-re egy *növekvő* alapeshez képest; a nagyságrend stimmel, a különbség az alapesetből adódik.
- Nettó zéró után a hőmérséklet stagnál (ZEC ≈ 0 feltevés).
- Az alkalmazkodás nem változtat a hőmérsékleten, csak a termésen.
- A tiszta levegő melegít (aeroszolos „leleplezés”).
- A SAI hirtelen leállítása után a melegedés üteme >0,06 °C/év (a mai ~0,027 sokszorosa).
- A CO2-eltávolítás nem lépheti túl a Fuss et al. 2018 plafont.

## 4. Ismert korlátok

- Az alapeset egyszerűsített (állandó kibocsátás); a valós „jelenlegi szakpolitikák” pályák ennél kicsit melegebbek is lehetnek.
- A nem-CO2 hatások csak a mai szinthez képesti *változásként* szerepelnek; a mai nem-CO2 kényszer lassú további hatása nincs benne.
- Nincs regionális éghajlat, csapadék, tengerszint, billenési pontok, szénkör-visszacsatolások (permafroszt).
- Ezért a 2. fázisban javasolt a **FaIR** (Smith et al. 2018; Leach et al. 2021) bekötése, amely nyílt forrású, Pythonban fut, és az IPCC AR6-ban is használták.

## 5. Hivatkozások

- IPCC (2021). *Climate Change 2021: The Physical Science Basis.* WG1 hozzájárulás az AR6-hoz. Summary for Policymakers; 5., 6. és 7. fejezet.
- Forster, P. M. et al. (2025). Indicators of Global Climate Change 2024: annual update of key indicators of the state of the climate system and human influence. *Earth System Science Data.*
- Friedlingstein, P. et al. (2025). Global Carbon Budget 2025. *Earth System Science Data.*
- Geoffroy, O. et al. (2013). Transient climate response in a two-layer energy-balance model. Part I. *Journal of Climate* 26, 1841–1857. doi:10.1175/JCLI-D-12-00195.1
- Held, I. M. et al. (2010). Probing the fast and slow components of global warming by returning abruptly to preindustrial forcing. *Journal of Climate* 23, 2418–2427. doi:10.1175/2009JCLI3466.1
- Myhre, G. et al. (1998). New estimates of radiative forcing due to well mixed greenhouse gases. *Geophysical Research Letters* 25, 2715–2718. doi:10.1029/98GL01908
- MacDougall, A. H. et al. (2020). Is there warming in the pipeline? A multi-model analysis of the Zero Emissions Commitment from CO2. *Biogeosciences* 17, 2987–3016. doi:10.5194/bg-17-2987-2020
- Zhao, C. et al. (2017). Temperature increase reduces global yields of major crops in four independent estimates. *PNAS* 114, 9326–9331. doi:10.1073/pnas.1701762114
- Liu, B. et al. (2016). Similar estimates of temperature impacts on global wheat yield by three independent methods. *Nature Climate Change* 6, 1130–1136. doi:10.1038/nclimate3115
- Fuss, S. et al. (2018). Negative emissions—Part 2: Costs, potentials and side effects. *Environmental Research Letters* 13, 063002. doi:10.1088/1748-9326/aabf9f
- UNEP & Climate and Clean Air Coalition (2021). *Global Methane Assessment: Benefits and Costs of Mitigating Methane Emissions.*
- Saunois, M. et al. Global Methane Budget (2000–2020). *Earth System Science Data.*
- Proctor, J. et al. (2018). Estimating global agricultural effects of geoengineering using volcanic eruptions. *Nature* 560, 480–483. doi:10.1038/s41586-018-0417-3
- Smith, C. J. et al. (2018). FAIR v1.3: a simple emissions-based impulse response and carbon cycle model. *Geoscientific Model Development* 11, 2273–2297. doi:10.5194/gmd-11-2273-2018
- Leach, N. J. et al. (2021). FaIRv2.0.0: a generalized impulse response model for climate uncertainty and future scenario exploration. *Geoscientific Model Development* 14, 3007–3036. doi:10.5194/gmd-14-3007-2021
- Beerling, D. J. et al. (2020). Potential for large-scale CO2 removal via enhanced rock weathering with croplands. *Nature* 583, 242–248. doi:10.1038/s41586-020-2448-9

Saját ellenőrzés: a 2024–2025-ös számokat (melegedés, kibocsátás, szénkeret, metáncél) friss forrásokból néztem meg ([Leedsi Egyetem, IGCC 2024](https://www.leeds.ac.uk/news/article/5801/scientists-find-three-years-left-of-remaining-carbon-budget-for-15-c); [Carbon Brief, GCB 2025](https://www.carbonbrief.org/analysis-fossil-fuel-co2-emissions-to-set-new-record-in-2025-as-land-sink-recovers/); [UNEP, Global Methane Assessment](https://www.unep.org/news-and-stories/press-release/global-assessment-urgent-steps-must-be-taken-reduce-methane); [Carbon Brief, aeroszolok](https://www.carbonbrief.org/?p=57765); [Fuss et al. 2018](https://eprints.whiterose.ac.uk/140963/)). A régebbi, jól ismert cikkek DOI-jait emlékezetből adtam meg; a Zhao 2017 és a Liu 2016 DOI-ját az OpenAlexben ellenőriztem, a többit érdemes egyszer a doi.org-on átkattintani.
