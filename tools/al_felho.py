"""Ál-kiszolgáló a felhős saját AI próbájához (Claude, ChatGPT, Gemini kérésformái), valódi kulcs és internet nélkül.
Indítás: python tools/al_felho.py szamlalo.json   (a 127.0.0.1:11500 címen figyel, csak a "proba-kulcs" kulcsot fogadja el)
Próba:   godot -- --gepjatek --gep=sajat --orszagok --ai=claude|chatgpt|gemini --aicim=http://127.0.0.1:11500
A válaszai próbamondatok; azt ellenőrzi, hogy a játék jó címre, jó fejlécekkel és jó formában kérdez-e."""
import json, re, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
C = {"claude": 0, "chatgpt": 0, "gemini": 0, "401": 0}
def answer(sysm, user):
    if sysm.startswith("You speak for"):
        opts = re.findall(r"^([A-F])\. ", user, re.M)
        return "Here you go: " + json.dumps({"real_record": "x", "choice": opts[1] if "YOUR OWN MOVE" in user else opts[0], "statement": "Felhős próbamondat."})
    moves = re.findall(r"^(\d+)\. (.*)$", user, re.M)
    good = [m for m in moves if m[1].startswith(("Ask", "Reassure", "Refute", "Climate summit: show the card"))]
    pick = good[0] if good else ([m for m in moves if m[1].startswith("Research")] or moves)[0]
    return json.dumps({"move": int(pick[0]), "why": "Felhős próbamondat."})
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _send(self, d, code=200):
        b = json.dumps(d).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
        open(sys.argv[1], "w").write(json.dumps(C))
    def who(self):
        h = self.headers
        if h.get("x-api-key") == "proba-kulcs" and h.get("anthropic-version") == "2026-10-21": return "claude"
        if h.get("Authorization") == "Bearer proba-kulcs": return "chatgpt"
        if h.get("x-goog-api-key") == "proba-kulcs": return "gemini"
        C["401"] += 1; return ""          # rossz kulcs: 401 (a játék ezt külön kiírja)
    def do_GET(self):
        w = self.who()
        if not w: return self._send({}, 401)
        if w == "claude" and self.path.startswith("/v1/models"): return self._send({"data": [{"id": "claude-haiku-5-5"}, {"id": "claude-opus-5-5"}]})
        if w == "chatgpt" and self.path == "/v1/models": return self._send({"data": [{"id": "text-embedding-x"}, {"id": "proba-gpt"}]})
        if w == "gemini" and self.path.startswith("/v1beta/models"): return self._send({"models": [{"name": "models/proba-embed", "supportedGenerationMethods": ["embedContent"]}, {"name": "models/proba-gemini", "supportedGenerationMethods": ["generateContent"]}]})
        self._send({}, 404)
    def do_POST(self):
        w = self.who()
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        if not w: return self._send({}, 401)
        if w == "claude" and self.path == "/v1/messages" and body["model"] == "claude-opus-5-5" and "temperature" not in body:
            C[w] += 1
            return self._send({"content": [{"type": "thinking", "thinking": "{no}"}, {"type": "text", "text": answer(body["system"], body["messages"][0]["content"])}], "stop_reason": "end_turn"})
        if w == "chatgpt" and self.path == "/v1/chat/completions" and body["model"] == "proba-gpt":
            C[w] += 1
            return self._send({"choices": [{"message": {"role": "assistant", "content": answer(body["messages"][0]["content"], body["messages"][1]["content"])}}]})
        if w == "gemini" and self.path == "/v1beta/models/proba-gemini:generateContent":
            C[w] += 1
            return self._send({"candidates": [{"content": {"parts": [{"text": answer(body["systemInstruction"]["parts"][0]["text"], body["contents"][0]["parts"][0]["text"])}]}}]})
        self._send({}, 400)
HTTPServer(("127.0.0.1", 11500), H).serve_forever()
