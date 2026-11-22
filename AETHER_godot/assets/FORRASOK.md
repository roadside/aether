# Képek forrása

- `earth_albedo.png`, `earth_data.png`, `earth_night.png`: a `tools/festett_textura.py` állítja elő
  NASA-képekből (Blue Marble nappali kép, Earth at Night városfények, domborzat és víz-maszk; közkincs).
  A képeket a three-globe projekt példái közül töltöttük le:
  https://github.com/vasturiano/three-globe/tree/master/example/img
  A festett pixeles stílus (saját paletta, lépcsős domborzat-árnyalás, mélységi tengerszínek) saját feldolgozás.
- `earth_clouds.png`, `nebula_bg.png`: saját, programmal generált kép (nem valós felhőkép).

# Hangok forrása

- `hang/intro_handpan.wav`: a kezdő animáció lágy, handpan-szerű zenéje. Saját, programmal szintetizált
  hang (nem felvétel, nem minta): a `tools/intro_zene_handpan.py` állítja elő (D kurd hangsor, szinusz-részhangok,
  egyszerű visszhang).
- `hang/intro.wav`: a bevezető másik, handpan hangzású saját zenéje (a `tools/intro_zene.py` állítja elő).
  Jelenleg a játék az `intro_handpan.wav`-ot játssza; a kettő közül Zoltán választ.
