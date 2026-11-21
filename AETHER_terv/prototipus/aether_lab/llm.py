"""A játékos saját AI-ja: egységes felület több szolgáltatóhoz.

Szolgáltatók:
  - "claude": Anthropic Claude API, a játékos saját előfizetésével / API-kulcsával
               (ANTHROPIC_API_KEY környezeti változó vagy `ant auth login`).
  - "ollama": helyi modell a játékos gépén (offline mód), https://ollama.com
               pl. `ollama pull qwen3:14b` vagy bármely más letöltött modell.
  - "none":   AI nélküli mód: a játék csak a cikkeket listázza, kivonatolás nincs.

ALAPELV: az AI soha nem számol a modell helyett, és nem talál ki számokat.
Csak (1) keresőkifejezéseket javasol, (2) absztraktokból SZÓ SZERINTI idézettel
alátámasztott állításokat emel ki szigorú JSON-sémában. Az ellenőrzést és a
számolást determinisztikus kód végzi (evidence.py, climate.py).
"""
from __future__ import annotations

import json
import os
import urllib.request
from typing import Any, Dict


class LLMError(RuntimeError):
    pass


class Provider:
    name = "base"

    def json_call(self, system: str, user: str, schema: Dict[str, Any], max_tokens: int = 8000) -> Dict[str, Any]:
        raise NotImplementedError


class ClaudeProvider(Provider):
    """Anthropic Claude, strukturált (JSON-séma szerinti) kimenettel."""
    name = "claude"

    def __init__(self, model: str = "claude-opus-5-5", effort: str = "medium"):
        try:
            import anthropic  # pip install anthropic
        except ImportError as e:
            raise LLMError("Telepítsd: pip install anthropic") from e
        self._anthropic = anthropic
        self.client = anthropic.Anthropic()  # kulcs a környezetből, sosem a kódban
        self.model = model
        self.effort = effort

    def json_call(self, system, user, schema, max_tokens=8000):
        a = self._anthropic
        try:
            # Szerveroldali tartalék modell elutasítás (refusal) esetére.
            resp = self.client.beta.messages.create(
                model=self.model,
                max_tokens=max_tokens,
                system=system,
                messages=[{"role": "user", "content": user}],
                output_config={"effort": self.effort,
                               "format": {"type": "json_schema", "schema": schema}},
                betas=["server-side-fallback-2026-07-01"],
                fallbacks="default",
            )
        except a.AuthenticationError as e:
            raise LLMError("Érvénytelen vagy hiányzó Anthropic API-kulcs.") from e
        except a.RateLimitError as e:
            raise LLMError("Az AI-előfizetés kerete elfogyott (rate limit). Próbáld később.") from e
        except a.APIStatusError as e:
            raise LLMError(f"API-hiba ({e.status_code}): {e.message}") from e
        except a.APIConnectionError as e:
            raise LLMError("Nincs kapcsolat az AI-szolgáltatóval. Válts offline (ollama) módra.") from e
        if resp.stop_reason == "refusal":
            raise LLMError("Az AI elutasította a kérést.")
        if resp.stop_reason == "max_tokens":
            raise LLMError("Az AI válasza túl hosszú lett (max_tokens).")
        text = next((b.text for b in resp.content if b.type == "text"), "")
        try:
            return json.loads(text)
        except json.JSONDecodeError as e:
            raise LLMError("Az AI érvénytelen JSON-t adott.") from e


class OllamaProvider(Provider):
    """Helyi modell az Ollama natív REST API-ján (offline működés)."""
    name = "ollama"

    def __init__(self, model: str = None, host: str = None):
        self.model = model or os.environ.get("AETHER_OLLAMA_MODEL", "qwen3:14b")
        self.host = (host or os.environ.get("OLLAMA_HOST", "http://localhost:11434")).rstrip("/")

    def json_call(self, system, user, schema, max_tokens=8000):
        body = {
            "model": self.model,
            "stream": False,
            "format": schema,  # Ollama >= 0.5: JSON-séma szerinti kimenet
            "options": {"num_predict": max_tokens},
            "messages": [{"role": "system", "content": system},
                         {"role": "user", "content": user}],
        }
        req = urllib.request.Request(self.host + "/api/chat", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                data = json.loads(r.read())
        except Exception as e:
            raise LLMError(f"Nem érem el a helyi Ollama szervert ({self.host}): {e}") from e
        try:
            return json.loads(data["message"]["content"])
        except (KeyError, json.JSONDecodeError) as e:
            raise LLMError("A helyi modell érvénytelen JSON-t adott.") from e


def get_provider(name: str, **kw) -> Provider | None:
    name = (name or "none").lower()
    if name == "claude":
        return ClaudeProvider(**kw)
    if name == "ollama":
        return OllamaProvider(**kw)
    if name == "none":
        return None
    raise LLMError(f"Ismeretlen szolgáltató: {name}")
