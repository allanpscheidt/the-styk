"""Source boundary checks for Windows, runnable without Win32/WPF on macOS."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[1] / "TheStyk-Windows" / "TheStyk-Windows"


class ObserverLoggingPrivacyTests(unittest.TestCase):
    def test_observer_has_no_durable_logging_sink(self):
        source = (ROOT / "System" / "ExplorerObserver.cs").read_text()
        for forbidden in ("debug.log", "AppendAllText", "WriteAllText", "StreamWriter",
                          "FileStream", "Trace.", "Debug.", "Console."):
            self.assertNotIn(forbidden, source)
        self.assertIsNone(re.search(r"\bLog\s*\(", source))

    def test_no_other_component_can_use_retired_persistent_logger(self):
        for path in ROOT.rglob("*.cs"):
            source = path.read_text()
            self.assertNotIn("ExplorerObserver.Log", source, str(path))
            self.assertNotIn("debug.log", source, str(path))


if __name__ == "__main__":
    unittest.main()
