# Képek forrása

- `earth_albedo.png`, `earth_data.png`, `earth_night.png`: a `tools/festett_textura.py` állítja elő
  NASA-képekből (Blue Marble nappali kép, Earth at Night városfények, domborzat és víz-maszk; közkincs).
  A képeket a three-globe projekt példái közül töltöttük le:
  https://github.com/vasturiano/three-globe/tree/master/example/img
  A festett pixeles stílus (saját paletta, lépcsős domborzat-árnyalás, mélységi tengerszínek) saját feldolgozás.
- `earth_clouds.png`, `nebula_bg.png`: saját, programmal generált kép (nem valós felhőkép, nem valós csillagtérkép). Az éjszakai eget a `tools/hatter.py` készíti.

# Hangok forrása

- `hang/intro_handpan.wav`: a kezdő animáció lágy, handpan-szerű zenéje. Saját, programmal szintetizált
  hang (nem felvétel, nem minta): a `tools/intro_zene_handpan.py` állítja elő (D kurd hangsor, szinusz-részhangok,
  egyszerű visszhang).
- `hang/intro.wav`: a bevezető másik, handpan hangzású saját zenéje (a `tools/intro_zene.py` állítja elő).
  Jelenleg a játék az `intro_handpan.wav`-ot játssza; a kettő közül Zoltán választ.

- `hang/egyezseg.wav`, `megingas.wav`, `billenes.wav`, `kartya.wav`, `korvaltas.wav`, `kattintas.wav`, `jo_hir.wav`,
  `katasztrofa.wav`, `alapzene.wav`, `alapzene2.wav`: a játék közbeni hangok és a két halk alapzene. Saját, programmal
  szintetizált hangok (nem felvétel, nem minta): a `tools/jatek_hangok.py` állítja elő őket, ugyanabban a hangsorban.

# Képjelek

- A nyolc témakör kis képjele (`scripts/icons.gd`): saját, kódból rajzolt 12×12 képpontos rajz.

# Domborzat (alacsony partok)

- `earth_low.png`: a mai tengerszint fölött legfeljebb 10 méteren fekvő partvidékek maszkja a földgömbhöz
  (255 = 0 m vagy alatta, 0 = 10 m vagy magasabb). A `tools/alacsony_partok.py` állítja elő.
  Forrás: NOAA ETOPO1, 1 ívperces globális domborzat („Ice Surface”), Amante & Eakins (2009), NOAA NGDC,
  5 ívperces ritkítással a NOAA ERDDAP szerveréről
  (https://coastwatch.pfeg.noaa.gov/erddap/griddap/etopo180.html). Licenc: szabadon használható és
  továbbadható; nem jogi célra. A játékban a veszélyeztetett alacsony partok figyelmeztető kiemelésére szolgál,
  nem azt mutatja, mi kerül víz alá.

# Fényképek a földgömb pontjaihoz (`kepek/`)

Valódi felvételek, mind közkincs (public domain: NASA, USGS, NOAA), a Wikimedia Commonsról letöltve 2026-11-27-én,
1024 képpont szélesre kicsinyítve. A képeket Zoltán hagyta jóvá. A leírások a Commons-oldalak adataiból származnak.

- `kepek/gronland.jpg`: Olvadékvíz-tavak a grönlandi jégtakarón, Délnyugat-Grönland, 2016. jún. 15. (EO-1 ALI műholdkép). Készítette: NASA Goddard Space Flight Center. https://commons.wikimedia.org/wiki/File:Early_Melt_on_the_Greenland_Ice_Sheet_(33354485670).jpg
- `kepek/nyugat_antarktisz.jpg`: Pine Island-gleccser, Nyugat-Antarktisz, 2024. okt. 10. (Landsat). Készítette: NASA Earth Observatory, Wanmei Liang; Landsat-adatok: USGS. https://commons.wikimedia.org/wiki/File:Streaming_Snow_and_%E2%80%9CSea_Smoke%E2%80%9D_(153509_-_zm_oli_20241010_lrg).jpg
- `kepek/labrador.jpg`: Örvénylő tengeri jég a Labrador-tengeren, 2024. febr. 27. (MODIS). Készítette: MODIS Land Rapid Response Team, NASA GSFC. https://commons.wikimedia.org/wiki/File:Ice_Swirls_in_the_Labrador_Sea_(MODIS_2024-02-29).jpg
- `kepek/amoc.jpg`: A Golf-áramlat meleg vize: tengerfelszín-hőmérséklet, 2005. ápr. 18. (MODIS; hamis színes mérési kép, nem természetes színű fotó). Készítette: NASA, MODIS-adatok. https://commons.wikimedia.org/wiki/File:SST_Gulf_stream.jpeg
- `kepek/amazonas.jpg`: Az Ucayali folyó az Amazonas-medence esőerdejében, Közép-Peru, 2026. ápr. 15. (űrhajósfotó, ISS). Készítette: NASA Johnson Space Center. https://commons.wikimedia.org/wiki/File:The_Ucayali_River_in_the_lowland_Amazon_rainforest_of_central_Peru_(iss074e0492148).jpg
- `kepek/permafroszt_osszeomlas.jpg`: Batagaika-kráter, olvadó fagyott talaj, Jakutföld, 2016. jún. 7. (Landsat). Készítette: NASA Earth Observatory, Jesse Allen; Landsat-adatok: USGS. https://commons.wikimedia.org/wiki/File:Batagaika_crater_NASA.jpg
- `kepek/permafroszt_olvadas.jpg`: Leomlott, jégben gazdag fagyott talajtömb a tengerparton, Drew Point, Alaszka (az év nincs megadva). Készítette: Benjamin Jones, USGS. https://commons.wikimedia.org/wiki/File:Collapsed_permafrost_(9356).jpg
- `kepek/korall.jpg`: Kifehéredett agykorall, Cheeca Rocks, Florida Keys, 2023. júl. 31. (víz alatti fotó). Készítette: NOAA. https://commons.wikimedia.org/wiki/File:World%E2%80%99s_Fourth_Mass_Coral_Bleaching_Event_Likely_Ended_in_2025_(NESDIS_2026-06-02_NOAA_Cheeca-Rocks_07312023_7-e).jpg
- `kepek/barents.jpg`: Olvadó tengeri jég a Barents-tengeren, 2022. máj. 31. (MODIS). Készítette: MODIS Land Rapid Response Team, NASA GSFC. https://commons.wikimedia.org/wiki/File:Sea_Ice_in_the_Barents_Sea_(MODIS_2022-06-02).jpg
- `kepek/sarki_teli_jeg.jpg`: Repedés az északi-sarki tengeri jégben, 2011. márc. 28. (Operation IceBridge légifotó). Készítette: NASA Goddard Space Flight Center. https://commons.wikimedia.org/wiki/File:Arctic_Sea_Ice_Lead_(7873353514).jpg
- `kepek/gleccserek.jpg`: Gleccserek végei és gleccsertavak a bhutáni Himalájában, 2002. jún. 4. (ASTER). Készítette: NASA. https://commons.wikimedia.org/wiki/File:Glacial_lakes,_Bhutan.jpg
- `kepek/europa.jpg`: Európa éjszakai fényei Amszterdamtól Párizson át Londonig, 2021. szept. 15. (ISS). Készítette: NASA. https://commons.wikimedia.org/wiki/File:ISS-65_Soyuz_MS-18_and_Nauka_above_Europe_at_night.jpg
- `kepek/usa.jpg`: Az Egyesült Államok északkeleti partvidéke éjjel, 2018. jan. 1. (ISS). Készítette: NASA. https://commons.wikimedia.org/wiki/File:ISS-54_Northeastern_United_States_at_night.jpg
- `kepek/kina.jpg`: Peking éjjel, 2016. márc. 20. (ISS). Készítette: NASA, Tim Kopra. https://commons.wikimedia.org/wiki/File:ISS-47_Beijing,_China_at_night.jpg
- `kepek/india.jpg`: Delhi éjjel, 2016. márc. 16. (ISS). Készítette: NASA, Tim Kopra. https://commons.wikimedia.org/wiki/File:ISS-47_Delhi,_India_at_night.jpg
- `kepek/afrika.jpg`: A Szahara Líbia és Csád fölött, 2015. febr. 15. (ISS). Készítette: NASA, Terry Virts. https://commons.wikimedia.org/wiki/File:ISS-42_Africa_desert_of_Libya_and_Chad.jpg
- `kepek/olaj.jpg`: A Perzsa-öböl éjszakai városfényei, 2020. aug. 31. (ISS). Készítette: NASA. https://commons.wikimedia.org/wiki/File:ISS-63_Persian_Gulf_at_night.jpg
