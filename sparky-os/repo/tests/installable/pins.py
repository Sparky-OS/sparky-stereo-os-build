"""Exercise the installability checker's static pin selectors and record order."""
import importlib.util
import unittest
from pathlib import Path

checker = Path(__file__).resolve().parents[2] / "check-installable.py"
spec = importlib.util.spec_from_file_location("check_installable", checker)
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)


class StaticPins(unittest.TestCase):
    def setUp(self):
        self.package = {"Package": "libexample", "Source": "example (1)", "Architecture": "i386",
                        "Version": "1", "_origin": "Debian", "_host": "deb.debian.org"}

    def pins(self, package, priority=-1, pin="release o=Debian"):
        return f"Package: {package}\nPin: {pin}\nPin-Priority: {priority}\n"

    def blocked(self, rules, **entry):
        return ci.Pins({"test": (rules, "fixture")}, "amd64").blocked(self.package | entry)

    def test_literal_architectures_and_source(self):
        for selector in ("libexample:i386", "libexample:any", "src:example:i386", "src:example:any"):
            with self.subTest(selector=selector):
                self.assertTrue(self.blocked(self.pins(selector)))
        for selector in ("libexample", "libexample:native", "libexample:amd64", "src:example", "example:any"):
            with self.subTest(selector=selector):
                self.assertFalse(self.blocked(self.pins(selector)))
        self.assertTrue(self.blocked(self.pins("libexample:native"), Architecture="all"))
        self.assertFalse(self.blocked(self.pins("src:native"), Package="src", Architecture="amd64"))
        self.assertTrue(self.blocked(self.pins("src:native"), Source="native", Architecture="amd64"))

    def test_patterns_share_literal_records(self):
        self.assertTrue(self.blocked(self.pins("other:i386 libex*:/nonmatching/ /^libexample$/:i386")))
        self.assertTrue(self.blocked(self.pins("other:i386 src:exam?le:any")))
        self.assertFalse(self.blocked(self.pins("other:i386 src:exam?le:native")))

    def test_first_matching_specific_record_wins(self):
        rules = "\n".join((self.pins("*"), self.pins("libexample:i386", 995, "version 2"),
                           self.pins("libexample:any", 990), self.pins("src:example:i386")))
        self.assertFalse(self.blocked(rules))
        self.assertTrue(self.blocked(rules, Package="unrelated", Source="unrelated"))
        self.assertFalse(self.blocked(self.pins("libexample:i386"), _origin="Other"))


if __name__ == "__main__":
    unittest.main()
