"""A gépfelmérés offline tesztjei (szimulált nvidia-smi kimenettel)."""
import unittest

from aether_lab import hardware as hw


class TestHardware(unittest.TestCase):
    def test_nvidia_parse(self):
        run = lambda cmd, timeout=8.0: "TESZT GeForce RTX 4050 Laptop GPU, 6141\n"   # noqa: E731
        g = hw.nvidia_gpus(run)
        self.assertEqual(g[0]["vram_gb"], 6.0)

    def test_recommend_6gb(self):
        r = hw.recommend([{"nev": "TESZT", "vram_gb": 6.0, "ollama_hasznalja": True}], 16.0)
        self.assertEqual((r["modell"], r["hol"]), ("qwen3:4b", "gpu"))

    def test_recommend_12gb_and_cpu(self):
        self.assertEqual(hw.recommend([{"nev": "T", "vram_gb": 12.0, "ollama_hasznalja": True}], 32)["modell"],
                         "qwen3:14b")
        r = hw.recommend([{"nev": "Intel", "ollama_hasznalja": False}], 8.0, lang="en")
        self.assertEqual((r["modell"], r["hol"]), ("qwen3:4b", "cpu"))
        self.assertEqual(hw.recommend([], 4.0)["modell"], "qwen3:1.7b")
        self.assertIn("processor", r["indoklas"])

    def test_apple(self):
        self.assertEqual(hw.recommend([], 16.0, apple_silicon=True)["modell"], "qwen3:8b")


if __name__ == "__main__":
    unittest.main()
