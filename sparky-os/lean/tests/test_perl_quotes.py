"""Quote boundaries are data boundaries, even for /x pattern comments.

Fixtures are excerpts of the five dpkg 1.23.11 modules retained by ORDER 363;
see fixtures/perl-dpkg.LICENSE for provenance and licensing.
"""

import json
from pathlib import Path
import shutil
import unittest

from lean import lang_perl
from lean.tests.test_handlers import P, run


@unittest.skipUnless(shutil.which('perl'), 'perl required')
class PerlQuotes(unittest.TestCase):
    def check_quote(self, code, literal, runtime=True):
        source = '# outside before\n' + code + '\n# outside after\n'
        self.assertIsNotNone(lang_perl.deparse(source), source)
        result, output = P('/usr/share/test/quote.pl', source)
        self.assertEqual(result.status, 'projected', result.reason)
        self.assertIn(literal, output)
        self.assertNotIn('# outside before', output)
        self.assertNotIn('# outside after', output)
        self.assertIn('B::Deparse prints the same program', result.check)
        if runtime:
            self.assertEqual(run(['perl'], source), run(['perl'], output))
        again, _ = P('/usr/share/test/quote.pl', output)
        self.assertEqual(again.status, 'unchanged', again.reason)

    def test_dpkg_patterns(self):
        fixtures = Path(__file__).with_name('fixtures') / 'perl-dpkg.json'
        for name, code in json.loads(fixtures.read_text()).items():
            with self.subTest(module=name):
                # The package fixture also has a real comment after its string.
                literal = code.split('# Take out comments and newlines.')[0].rstrip()
                self.check_quote(code, literal)

    def test_quote_operators_and_delimiters(self):
        for op in ('q', 'qq', 'qw', 'qx', 'qr', 'm', 's', 'tr', 'y'):
            for opening, closing in (('{', '}'), ('[', ']'), ('(', ')'), ('<', '>'),
                                     ('/', '/'), ('!', '!'), (']', ']'), ('\\', '\\'),
                                     ('X', 'X'), ('1', '1'), ('§', '§')):
                with self.subTest(operator=op, delimiter=opening):
                    body = '\n# literal inside\n\n\nabc\n'
                    # Word delimiters require a gap after the operator.
                    prefix = op + (' ' if opening.isalnum() else '')
                    quoted = prefix + opening + body + closing
                    if op in ('s', 'tr', 'y'):
                        quoted += (opening if opening in '([{<' else '') + body + closing
                    if op in ('qr', 'm', 's'):
                        quoted += 'x'
                    code = 'use utf8;\nmy $value = "abc";\n'
                    code += ('$value =~ ' if op in ('m', 's', 'tr', 'y') else 'my @out = ') + quoted + ';\n'
                    code += 'print $value;'
                    # qx must be compiled but never execute arbitrary fixture text.
                    self.check_quote(code, quoted, runtime=op != 'qx')

    def test_nested_and_escaped_delimiters(self):
        for opening, closing in (('{', '}'), ('[', ']'), ('(', ')'), ('<', '>')):
            with self.subTest(delimiter=opening):
                quote = ('q' + opening + 'outer' + opening + '\n# nested\n' + closing
                         + '\\' + closing + '\n# still inside\n' + closing)
                self.check_quote('print ' + quote + ';', quote)
        quote = 'q!escaped\\!\n# inside\nbackslash\\\\!'
        self.check_quote('print ' + quote + ';', quote)

    def test_hash_delimiter_and_second_section(self):
        for quote in ('q#abc\n#', 'qq#abc\n#', 'qr#abc\n#x',
                      's#abc\n#replacement\n#', 'tr#abc\n#ABC\n#', 'y#abc\n#ABC\n#',
                      's{abc}\n  # gap\n  [\n# replacement\n]',
                      's{abc}#replacement\n#', 'tr[abc]/\n#ABC\n/',
                      'y(abc){\n#ABC\n}'):
            with self.subTest(quote=quote):
                code = 'my $s = "abc";\n'
                code += ('$s =~ ' if quote.startswith(('s', 'tr', 'y')) else 'my $x = ') + quote + ';'
                self.check_quote(code, quote)

    def test_plain_quotes_and_bare_patterns(self):
        for quote in ("'", '"', '`'):
            literal = quote + '\n# not a comment\n\n\n' + quote
            self.check_quote('print ' + literal + ';', literal, runtime=quote != '`')
        for prefix in ('my $re = ', '"abc" =~ ', '"abc" !~ ', 'print ', 'split ',
                       'my @a = grep ', 'if (', '$_ = "abc"; my $x = 1; $x = $x / '):
            quote = '/\n# pattern\nabc\n/x'
            suffix = ') { print "yes"; }' if prefix == 'if (' else ';'
            self.check_quote(prefix + quote + suffix, quote)

    def test_operator_gap_comments(self):
        quote = 'q \n# gap after q\n{\n# inside\n}'
        self.check_quote('print ' + quote + ';', quote)

    def test_literal_lines_override_pod_data_and_comment_syntax(self):
        quote = 'qq{\n=pod\n__END__\n# still literal\n=cut\n}'
        self.check_quote('print ' + quote + ';', quote)
        self.check_quote('my $v = q{one}; my $w = q{\n# second quote\n};',
                         'q{\n# second quote\n}')

    def test_inline_comments_do_not_start_a_quote(self):
        source = 'print "ok"; # q{ <<FAKE\n# outside removable\n'
        result, output = P('/usr/share/test/quote.pl', source)
        self.assertEqual(result.status, 'projected', result.reason)
        self.assertNotIn('# outside removable', output)
        self.assertIn('# q{ <<FAKE', output)

    def test_empty_match_and_defined_or(self):
        code = '$_ = "abc"; /abc/; my $n = //; $n //= 3; print $n;'
        self.check_quote(code, code)

    def test_non_quote_tokens_and_division(self):
        code = '''my $q = 12;
my %h = (q => 2, m => 3);
my $n = $q /
# outside division
2;
$n //= 1;
my $s = $h{q};
# outside hash key
sub q { return 2; }
my $t = main::q();
$n /= 2;
# outside assignment
print $n, $s, $t;
'''
        source = '# outside header\n' + code
        result, output = P('/usr/share/test/quote.pl', source)
        self.assertEqual(result.status, 'projected', result.reason)
        self.assertNotIn('# outside', output)
        self.assertEqual(run(['perl'], source), run(['perl'], output))

    def test_pod_heredoc_and_data_are_not_quote_starters(self):
        literal = "\n# heredoc q{\n\n\n"
        code = '''=pod
q{not code
=cut
my $s = <<'END';
''' + literal + '''END
# outside heredoc
print $s;
my $t = q{<<FAKE
# inside quote
};
# outside fake heredoc
__DATA__
# data stays
q{not code
'''
        result, output = P('/usr/share/test/quote.pl', code)
        self.assertEqual(result.status, 'projected', result.reason)
        self.assertIn(literal, output)
        self.assertIn('# inside quote', output)
        self.assertIn('# data stays', output)
        self.assertNotIn('# outside', output)
        self.assertEqual(run(['perl'], code), run(['perl'], output))

    def test_heredoc_after_filehandle_or_function(self):
        body = '# heredoc literal\n\n\n'
        for statement in ('print STDERR', 'sub consume { print $_[0]; } consume'):
            with self.subTest(statement=statement):
                self.check_quote(statement + " <<'END';\n" + body + 'END\n', body)

    def test_changed_program_is_still_refused(self):
        self.assertEqual(lang_perl.verify('print "one";', 'print "two";'),
                         (False, 'B::Deparse prints a different program'))


if __name__ == '__main__':
    unittest.main()
