# Calligra Words

On a stereo display, the desk in Words lies one element step behind the paper. The canvas declares its visible pages to Qt Widgets when the document scrolls, its layout changes, or the view resizes. Qt draws each eye and retains the canvas shadow.

Edition source version `1:26.08.0+dfsg-1+stereo3d1+lc1` carries Debian testing's source. The Words binary requires Qt +stereo3d26. Use `build-1.sh` with the Debian source closure named by `source.sha256`, the signed edition archive and the staged Qt binary packages.

## Credits

The Calligra Words canvas is by Reginald Stadlbauer, David Faure, Thomas Zander, Inge Wallin and Boudewijn Rempt. The shared canvas paint also credits Marijn Kruisselbrink. Thomas Zander wrote the normal view map used for page placement. Carl Schwan, Pierre Ducroquet and C. Boemann are credited as maintainers in Words' About data. The Debian packaging is maintained by the Debian Qt/KDE Maintainers, with Pino Toscano listed in the source control file. Daniel Ramos designed the edition's paper depth.
