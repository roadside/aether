"""A játékos saját AI-ja: egységes felület több szolgáltatóhoz.

Szolgáltatók:
  - "claude": Anthropic Claude API, a játékos saját előfizetésével / API-kulcsával
               (ANTHROPIC_API_KEY környezeti változó vagy `ant auth login`).
  - "openai": OpenAI (ChatGPT) API, OPENAI_API_KEY. (A ChatGPT Plus előfizetés
               NEM tartalmaz API-hozzáférést: a kulcs külön, használat szerint fizetendő.)
  - "gemini": Google Gemini API, GEMINI_API_KEY (Google AI Studio; van ingyenes keret).
  - "ollama": helyi modell a játékos gépén (offline mód), https://ollama.com
               pl. `ollama pull qwen3:8b` vagy bármely más letöltött modell.
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

    # Ha a játékos nem ad meg modellt, a letöltöttek közül ezeket keressük ebben a
    # sorrendben (a 8B-s modellek kb. 6 GB videómemóriában is elférnek).
    PREFERRED = ["qwen3:8b", "qwen3:14b", "qwen3:4b", "llama3.1:8b", "gemma3:12b", "gemma3:4b", "mistral"]

    # Kisebb gépen (pl. 6 GB videómemória) kevesebb, rövidebb absztrakttal dolgozunk,
    # hogy a modell + kontextus elférjen a GPU-n (különben a CPU-n lassú).
    max_papers = 8
    max_abstract_chars = 1500

    def __init__(self, model: str = None, host: str = None, num_ctx: int = None):
        self.host = (host or os.environ.get("OLLAMA_HOST", "http://localhost:11434")).rstrip("/")
        self.model = model or os.environ.get("AETHER_OLLAMA_MODEL") or self._pick_model()
        # Az alapértelmezett 2–4 ezer tokenes kontextusba nem férne bele 8 absztrakt:
        # csendben levágná őket. 8k elég, és 6 GB-on is a GPU-n marad.
        self.num_ctx = num_ctx or int(os.environ.get("AETHER_OLLAMA_CTX", "8192"))
        self._think_ok = True

    def _pick_model(self) -> str:
        try:
            with urllib.request.urlopen(self.host + "/api/tags", timeout=3) as r:
                names = [m.get("name", "") for m in json.loads(r.read()).get("models", [])]
        except Exception:
            return "qwen3:8b"
        # a gépre ajánlott modell (ami teljesen elfér a videómemóriában) kerül előre
        try:
            from .hardware import detect
            rec = [detect()["ajanlas"]["modell"]]
        except Exception:
            rec = []
        return pick_model(names, rec + self.PREFERRED) or "qwen3:8b"

    def json_call(self, system, user, schema, max_tokens=8000):
        import urllib.error
        body = {
            "model": self.model,
            "stream": False,
            "format": schema,  # Ollama >= 0.5: JSON-séma szerinti kimenet
            "options": {"num_predict": min(max_tokens, self.num_ctx // 2), "num_ctx": self.num_ctx},
            "messages": [{"role": "system", "content": system},
                         {"role": "user", "content": user + ("\n/no_think" if "qwen3" in self.model else "")}],
        }
        if self._think_ok:
            body["think"] = False  # gondolkodó modellnél (qwen3) sokkal gyorsabb, a JSON-hoz nem kell
        data = None
        for _ in range(2):
            req = urllib.request.Request(self.host + "/api/chat", data=json.dumps(body).encode(),
                                         headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=900) as r:
                    data = json.loads(r.read())
                break
            except urllib.error.HTTPError as e:
                msg = e.read().decode("utf-8", "replace")
                if "think" in msg.lower() and "think" in body:
                    body.pop("think")          # a modell nem ismeri a think kapcsolót
                    self._think_ok = False
                    continue
                raise LLMError(f"Ollama-hiba ({e.code}): {msg[:300]}") from e
            except Exception as e:
                raise LLMError(f"Nem érem el a helyi Ollama szervert ({self.host}): {e}") from e
        try:
            return json.loads(data["message"]["content"])
        except (KeyError, json.JSONDecodeError) as e:
            raise LLMError("A helyi modell érvénytelen JSON-t adott.") from e


def _post_json(url: str, body: Dict, headers: Dict[str, str], timeout: int = 600) -> Dict:
    """Egyszerű JSON POST; a HTTP-hibát érthető LLMError-rá alakítja."""
    import urllib.error
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", **headers})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = json.loads(e.read()).get("error", {}).get("message", "")
        except Exception:
            pass
        if e.code in (401, 403):
            raise LLMError(f"Érvénytelen vagy hiányzó API-kulcs ({e.code}). {detail}".strip()) from e
        if e.code == 429:
            raise LLMError("Az AI-fiók kerete elfogyott, vagy túl sok a kérés (429). Próbáld később. " + detail) from e
        raise LLMError(f"API-hiba ({e.code}): {detail}") from e
    except Exception as e:
        raise LLMError(f"Nincs kapcsolat az AI-szolgáltatóval: {e}") from e


def _parse(text: str) -> Dict:
    t = (text or "").strip()
    # gondolkodó modellek (qwen3) a think=False ellenére is írhatnak <think>…</think> blokkot
    while "<think>" in t and "</think>" in t:
        t = (t[:t.index("<think>")] + t[t.index("</think>") + len("</think>"):]).strip()
    if t.startswith("```"):  # néhány modell kódblokkba teszi a JSON-t
        t = t.strip("`")
        t = t[t.find("{"):]
    if not t.startswith("{") and "{" in t and "}" in t:
        t = t[t.find("{"):t.rfind("}") + 1]
    try:
        return json.loads(t)
    except json.JSONDecodeError as e:
        raise LLMError("Az AI érvénytelen JSON-t adott.") from e


class OpenAIProvider(Provider):
    """OpenAI (ChatGPT) Chat Completions API, szigorú JSON-séma szerinti kimenettel."""
    name = "openai"

    def __init__(self, model: str = None):
        self.key = os.environ.get("OPENAI_API_KEY", "")
        if not self.key:
            raise LLMError("Hiányzik az OpenAI API-kulcs (OPENAI_API_KEY).")
        self.model = model or os.environ.get("AETHER_OPENAI_MODEL", "gpt-5-mini")
        self.base = os.environ.get("OPENAI_BASE_URL", "https://api.openai.com/v1").rstrip("/")

    def json_call(self, system, user, schema, max_tokens=8000):
        body = {
            "model": self.model,
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
            "max_completion_tokens": max_tokens,
            "response_format": {"type": "json_schema",
                                "json_schema": {"name": "aether", "schema": schema, "strict": True}},
        }
        data = _post_json(self.base + "/chat/completions", body, {"Authorization": f"Bearer {self.key}"})
        try:
            choice = data["choices"][0]
            msg = choice["message"]
        except (KeyError, IndexError) as e:
            raise LLMError("Váratlan válasz az OpenAI-tól.") from e
        if msg.get("refusal"):
            raise LLMError("Az AI elutasította a kérést.")
        if choice.get("finish_reason") == "length":
            raise LLMError("Az AI válasza túl hosszú lett (max_tokens).")
        return _parse(msg.get("content", ""))


class GeminiProvider(Provider):
    """Google Gemini API (generateContent), JSON-kimenettel."""
    name = "gemini"

    def __init__(self, model: str = None):
        self.key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY", "")
        if not self.key:
            raise LLMError("Hiányzik a Gemini API-kulcs (GEMINI_API_KEY).")
        self.model = model or os.environ.get("AETHER_GEMINI_MODEL", "gemini-2.5-flash")
        self.base = "https://generativelanguage.googleapis.com/v1beta"

    def _call(self, system, user, schema, max_tokens):
        cfg = {"responseMimeType": "application/json", "maxOutputTokens": max_tokens}
        if schema is not None:
            cfg["responseJsonSchema"] = schema
        body = {"systemInstruction": {"parts": [{"text": system}]},
                "contents": [{"role": "user", "parts": [{"text": user}]}],
                "generationConfig": cfg}
        return _post_json(f"{self.base}/models/{self.model}:generateContent", body, {"x-goog-api-key": self.key})

    def json_call(self, system, user, schema, max_tokens=8000):
        try:
            data = self._call(system, user, schema, max_tokens)
        except LLMError as e:
            if "(400)" not in str(e):
                raise
            # régebbi modell: nem fogadja el a JSON-sémát; a sémát a kérésbe írjuk
            data = self._call(system, user + "\n\nVálaszolj PONTOSAN ennek a JSON-sémának megfelelően:\n"
                              + json.dumps(schema, ensure_ascii=False), None, max_tokens)
        try:
            cand = data["candidates"][0]
        except (KeyError, IndexError) as e:
            reason = (data.get("promptFeedback") or {}).get("blockReason", "")
            raise LLMError("Az AI nem adott választ" + (f" ({reason})." if reason else ".")) from e
        if cand.get("finishReason") == "MAX_TOKENS":
            raise LLMError("Az AI válasza túl hosszú lett (max_tokens).")
        text = "".join(p.get("text", "") for p in (cand.get("content") or {}).get("parts", []))
        return _parse(text)


PROVIDERS = ["claude", "openai", "gemini", "ollama", "none"]


def pick_model(available, preferred):
    """Az első előnyben részesített modell, ami le van töltve; különben az első letöltött."""
    for want in preferred:
        for name in available:
            if name == want or name.split(":")[0] == want or name.startswith(want + "-"):
                return name
    return available[0] if available else ""


def get_provider(name: str, **kw) -> Provider | None:
    name = (name or "none").lower()
    if name == "claude":
        return ClaudeProvider(**kw)
    if name == "openai":
        return OpenAIProvider(**kw)
    if name == "gemini":
        return GeminiProvider(**kw)
    if name == "ollama":
        return OllamaProvider(**kw)
    if name == "none":
        return None
    raise LLMError(f"Ismeretlen szolgáltató: {name}")
