#!/usr/bin/env python3
"""Regression checks for the installed Spanish lock-screen plural catalogue."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("validate_po_patches", HERE / "validate-po-patches.py")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)
PATCH = HERE.parent / "translations" / "kscreenlocker-edition-l10n.po.patch"


class LockScreenPluralTest(unittest.TestCase):
    def setUp(self):
        self.messages = VALIDATOR.parse_added_messages(PATCH.read_text(encoding="utf-8"),
                                                       "po/es/kcm_screenlocker.po")
        self.plurals = [key for key in self.messages if key[2] is not None]
        self.assertEqual(len(self.plurals), 2)
        for key in self.plurals:
            self.assertEqual(set(self.messages[key]), {"msgstr[0]", "msgstr[1]"})
        self.assertIn(("@info", "Videos with pop effects are not expected to be comfortable with widgets or other things over it.", None),
                      self.messages)

    def check_catalogue(self, messages):
        def line(key, value):
            return f"{key} {json.dumps(value, ensure_ascii=False)}\n"

        with tempfile.TemporaryDirectory() as temporary:
            lines = []
            for (context, singular, plural), forms in messages.items():
                if context:
                    lines.append(line("msgctxt", context))
                lines.append(line("msgid", singular))
                if plural is not None:
                    lines.append(line("msgid_plural", plural))
                lines.extend(line(field, value) for field, value in forms.items())
                lines.append("\n")
            path = Path(temporary) / "catalogue.po"
            path.write_text("".join(lines), encoding="utf-8")
            return VALIDATOR.po_has_messages(path, self.messages)

    def test_exact_plural_forms_and_following_singular(self):
        self.assertEqual(self.check_catalogue(self.messages), [])

    def test_modified_second_plural_form_is_rejected(self):
        wrong = {key: forms.copy() for key, forms in self.messages.items()}
        wrong[self.plurals[0]]["msgstr[1]"] = wrong[self.plurals[0]]["msgstr[0]"]
        self.assertEqual(len(self.check_catalogue(wrong)), 1)


if __name__ == "__main__":
    unittest.main()
