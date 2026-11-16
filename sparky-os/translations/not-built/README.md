# Spanish patches written and not built (ORDER 507b, round 2)

These five patches give Spanish to every stereo string the edition adds that no built Spanish catalogue answers and no other patch in this tree carries. They are drafts: no package was built from them, so nothing here ships until a rebuild names them in a series. They are kept in this folder, apart from the patches above, so that `tests/translations-shipped.py` (which reads the folder above) does not ask for a build of them.

| Patch | Source package | Strings | Where it goes in the series |
|---|---|---|---|
| `kwin-spanish-stereo-depth.po.patch` | kwin 6.7.4 | 11 and the file header | creates `po/es/kcm_kwinstereodepth.po`; directly after `kwin-stereo-depth.po.patch` and before `kwin-wallpaper-cost.po.patch`, whose Spanish hunk appends to that file |
| `kwin-spanish-depth-structures-and-throw-view.po.patch` | kwin 6.7.4 | 21 | appends to `po/es/kwin.po`, after `kwin-throw-view.po.patch` |
| `kdeconnect-spanish-throw.po.patch` | kdeconnect-kde 26.04.3 | 2 | appends to `po/es/kdeconnect-plugins.po`, after `kdeconnect-kde-throw.po.patch` |
| `krdc-spanish-catch.po.patch` | krdc 26.04.0 | 8 and the header | creates `po/es/krdc-catch.po`, after `krdc-catch.po.patch` |
| `krdp-spanish-throw.po.patch` | krdp 6.7.4 | 3 | appends to `po/es/krdpserver.po` (`-p1`), after `krdp-throw.po.patch` |

Checks made: `msgfmt -c --check-format` exit 0 on each resulting catalogue, and `patch -p1 --dry-run` on the unpacked 6.7.4 / 26.04 tarball (or an empty tree for the two new files).

**A term chosen here, with no recorded design:** "Throw" is "lanzar" and "Catch" is "recibir" (the eight other languages translate both: fr "lancer" and "recevoir", pt_BR "arremessar" and "receber", de "werfen" and "empfangen"). The Spanish installer slides still say "Throw y Catch" in English; if Daniel keeps the English names, these five patches change to "Throw" and "Catch".

**A defect found on the way:** `kwin-wallpaper-cost.po.patch` in this folder has a Spanish hunk that appends to `po/es/kcm_kwinstereodepth.po`, a file no patch creates (the published `kwin-stereo-depth.po.patch` has no Spanish): a kwin successor that applies this tree's copy fails on that hunk until `kwin-spanish-stereo-depth.po.patch` is in front of it.
