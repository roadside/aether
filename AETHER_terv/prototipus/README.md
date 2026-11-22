# AETHER Lab – kutatási prototípus

Részletes leírás: `../02_AI_es_kutatasi_motor.md`.

```
python -m unittest discover -s tests       # offline tesztek
python -m aether_lab demo                  # beépített forgatókönyvek (nem kell internet)
python -m aether_lab kutat "kérdés" --ai claude|ollama|none
python -m aether_lab modell forgatokonyv_pelda.json
```

Környezeti változók (mind opcionális): `ANTHROPIC_API_KEY`, `AETHER_MAILTO`, `OPENALEX_API_KEY`, `S2_API_KEY`, `AETHER_OLLAMA_MODEL`, `OLLAMA_HOST`.

Az alapmodul csak a Python standard könyvtárát használja; a Claude-módhoz: `pip install -r requirements.txt`.
