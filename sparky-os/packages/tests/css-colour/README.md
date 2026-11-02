# CSS colour test (ORDER 348)

Checks that Qt SVG and librsvg read every colour of CSS Color 4, CSS Color 5 and CSS Color HDR and store it at the precision CSS sets.

- `ref.py` is the reference: the grammar of the three specifications and the conversions of their own sample code (CSS Color 4 sections 7, 8, 14.2.2, 19 and 20.3; CSS Color HDR section 11; CSS Color 5 sections 3.3 and 6.1).
  `spec_examples.py` checks it against the specifications' worked examples, `wpt_check.py` against the web-platform-tests colour vectors (`wpt_vectors.py` extracts them from a checkout of web-platform-tests' css/css-color/parsing).
- `make_corpus.py` writes the SVGs and the expected value of each one for each target.
- `test.sh RENDERER DEB_DIR RESULTS` installs a build over Debian testing's packages in a container, renders the corpus with both renderers (`qt_render.cpp`, `rsvg_render.c`) and compares (`compare.py`).
  `test.sh qt debian RESULTS` and `test.sh rsvg debian RESULTS` run Debian's own packages, the control.
- `gen_qt_test_rows.py` writes the expected values of Qt SVG's own autotest, tst_qsvgcsscolor, from `ref.py`.

A line says PASS when the stored value is within the precision CSS requires for the colour's space (or within two steps of what the target format holds, where it holds less), LIMIT when the renderer is right and a layer beneath it holds less (QPainter's gradient tables, cairo's [0, 1] colours), and FAIL otherwise.
