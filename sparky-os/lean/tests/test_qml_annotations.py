"""QML annotations (queue row 825, found by row 77): a .qml file is read as QML, not as plain ECMAScript.

Qt's lexer reads `@` as a token of its own (qqmljslexer.cpp: `case u'@': return T_AT;`) and its grammar puts an
annotation list before the root object (`UiRootMember: UiAnnotatedObject`, `UiAnnotatedObject: UiAnnotationList
UiObjectDefinition`) and before any object member (`UiAnnotatedObjectMember: UiAnnotationList UiObjectMember`), where
`UiAnnotation: T_AT UiAnnotationObjectDefinition` and `UiAnnotationObjectDefinition: UiSimpleQualifiedId
UiObjectInitializer` (an initializer may be empty). Annotations are valid QML since Qt 5.15.
Up to lean 0.1.31 the QML check handed QML to acorn as ECMAScript, which has no `@`, so every QML file with an
annotation failed its check ("acorn could not tokenize the authored file") and a package build stopped on it
(Kirigami 6.32's ListSectionHeader.qml). A JavaScript file keeps ECMA-262's lexical grammar.

Debian's own file is read from LEAN_TEST_KIRIGAMI_LISTSECTIONHEADER (src/controls/ListSectionHeader.qml of
kirigami 6.32.0, which carries its author's address and so is not copied into this tree); without it that case is skipped.
"""

import os
import shutil
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))
from lean import lang_js, project  # noqa: E402

QML_PATH = '/usr/lib/x86_64-linux-gnu/qt6/qml/org/example/Annotated.qml'


def P(path, text):
    r = project.project(path, text.encode(), 'pkg', pointer=False)
    return r, (r.lean.decode() if r.lean else None)


# An annotation before the root object, before a child object, before properties with and without arguments, over
# several lines with a comment inside, and the character @ inside comments, a string and a template literal.
FIXTURE = '''// An example for the QML check: annotations before objects and members
import QtQuick

@Annotation { name: "root" } // before the root object
Item {
    id: root
    // before a child object
    @Annotation {}
    Rectangle { color: "red" }

    /* with an argument, as Kirigami writes it */
    @Deprecated { reason: "Use base type's AbstractButton::text property directly" }
    property alias label: root.objectName

    @Experimental {} // without arguments
    property int count: 2 /* two */ * 3

    @Deprecated {
        // why it goes
        reason: "old" /* the reason */
    }
    @Experimental {}
    function f(x) { return `@${x}` } // a template literal with @ in it

    // mail the maintainer @ home: an @ in a line comment
    /* @Deprecated { reason: "only text" } in a block comment */
    property string s: "@Deprecated { reason: \\"text\\" }"
}
'''


@unittest.skipUnless(shutil.which('node') or shutil.which('nodejs'), 'needs node with acorn')
class QmlAnnotations(unittest.TestCase):
    def setUp(self):
        if lang_js.tokens('1') is None:
            self.skipTest('no node with acorn')

    def test_fixture_is_projected(self):
        r, mr = P(QML_PATH, FIXTURE)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(r.check, 'acorn gives the same tokens and line breaks')
        for stays in ('@Annotation { name: "root" }\nItem {', '    @Annotation {}\n    Rectangle { color: "red" }',
                      '    @Deprecated { reason: "Use base type\'s AbstractButton::text property directly" }\n'
                      '    property alias label: root.objectName',
                      '    @Experimental {}\n    property int count: 2  * 3',
                      '    @Deprecated {\n        reason: "old"\n    }\n    @Experimental {}\n    function f(x)',
                      'return `@${x}`', 'property string s: "@Deprecated { reason: \\"text\\" }"'):
            self.assertIn(stays, mr)
        for gone in ('before the root object', 'before a child object', 'as Kirigami writes it', 'without arguments',
                     'why it goes', 'the reason', '/* two */', 'mail the maintainer', 'only text', 'a template literal'):
            self.assertNotIn(gone, mr)

    def test_at_is_a_token_of_its_own(self):
        a, b = lang_js.tokens('@Deprecated {}\nproperty int a', '@Deprecated {}\nproperty int a', qml=True)
        self.assertEqual(a, b)
        self.assertEqual(a[0], ['@', None, 1])
        self.assertEqual(a[1], ['name', 'Deprecated', 0])

    def test_a_changed_annotation_is_refused(self):
        lean = FIXTURE.replace('@Experimental {} // without arguments', '@Deprecated {} // without arguments')
        self.assertNotEqual(lean, FIXTURE)
        ok, detail = lang_js.verify(FIXTURE, lean, 'qml')
        self.assertFalse(ok)
        self.assertIn('tokens differ', detail)

    def test_a_moved_line_break_is_refused(self):
        lean = FIXTURE.replace('    @Experimental {} // without arguments\n    property', '    @Experimental {} property')
        self.assertNotEqual(lean, FIXTURE)
        ok, detail = lang_js.verify(FIXTURE, lean, 'qml')
        self.assertFalse(ok)
        self.assertIn('tokens differ', detail)

    def test_an_at_dropped_from_code_is_refused(self):
        lean = FIXTURE.replace('    @Annotation {}\n', '    Annotation {}\n')
        self.assertNotEqual(lean, FIXTURE)
        ok, _ = lang_js.verify(FIXTURE, lean, 'qml')
        self.assertFalse(ok)

    def test_javascript_keeps_ecma262(self):
        # '@' is no ECMAScript token: a .js file with one in its code still fails its check, as before
        r, _ = P('/usr/share/example/a.js', 'var a = 1; // one\n@Deprecated {}\n')
        self.assertEqual(r.status, 'left')
        self.assertEqual(r.reason, 'check failed: acorn could not tokenize the authored file')
        self.assertEqual(lang_js.verify('@x', '@x')[0], False)
        self.assertEqual(lang_js.verify('@x', '@x', 'qml')[0], True)

    def test_qml_without_annotations_unchanged(self):
        src = 'import QtQuick\nItem { // an item\n    property int x: 1 /* one */\n}\n'
        r, mr = P(QML_PATH, src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertEqual(mr, 'import QtQuick\nItem {\n    property int x: 1\n}\n')

    def test_debian_kirigami_listsectionheader(self):
        path = os.environ.get('LEAN_TEST_KIRIGAMI_LISTSECTIONHEADER')
        if not path:
            self.skipTest('LEAN_TEST_KIRIGAMI_LISTSECTIONHEADER names no file')
        with open(path, encoding='utf-8') as f:
            src = f.read()
        self.assertIn('    @Deprecated { reason: "Use base type\'s AbstractButton::text property directly" }\n'
                      '    property alias label: listSection.text\n', src)
        r, mr = P('/usr/lib/x86_64-linux-gnu/qt6/qml/org/kde/kirigami/controls/ListSectionHeader.qml', src)
        self.assertEqual(r.status, 'projected', r.reason)
        self.assertIn('    @Deprecated { reason: "Use base type\'s AbstractButton::text property directly" }\n'
                      '    property alias label: listSection.text\n', mr)
        self.assertIn('\\qmltype ListSectionHeader', mr)       # a /*! block: qdoc reads it, so it stays
        self.assertNotIn('we do not need a background', mr)
        self.assertNotIn("we override the Primary type's font weight", mr)


if __name__ == '__main__':
    unittest.main()
