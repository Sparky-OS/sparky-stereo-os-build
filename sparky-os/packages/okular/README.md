# okular (the edition's build)

Okular as Debian testing ships it (4:26.08.2-1), with one change: on a stereo output the desk around the pages lies one step of depth behind the window and the paper at the window's plane (queue row 121).

- **What the patch does:** `0001-pageview-paper-depth.patch` adds `PageView::updateStereoPaperDepth()`, which declares the page view's rectangles to the toolkit as the viewport's dynamic property `_q_stereo_depth_rects`: the whole view at -1 (the desk), each visible page with its outline at 0 (the paper). The page's text, pictures, annotations, forms and selection ride with the paper; its shadow lies on the desk. The rectangles are said again before the pages are painted whenever they move: after a relayout, a scroll and a resize.
- **Who draws it:** the edition's Qt Widgets (qt6-base +stereo3d25, patch o121-0002), per eye, in steps of the person's element limit, which Stereo KWin hands out (+stereo3d69, version 7 of `kde_stereo_content_v1`). Okular gives no pixels of its own. The `okular` package depends on that Qt.
- **What stays as it was:** a 2D screen, a window behind the active one, an element limit of 0, presentation mode (its own window at its window's level), and every view mode, trim, zoom, desk colour and page shadow.

## Build

`build-1.sh WORK SOURCE_DIR REPO_DIR ARCHIVE_DIR EXTRA_DIR PREVIOUS_SIBLINGS_FILE SIBLINGS_FILE` with the lane's `DOCKER_HOST`, `SPARKY_BUILD_IMAGE` and `BUILD_NAME_PREFIX`.
`SOURCE_DIR` holds Debian's source as `source.sha256` names it (`apt-get source --download-only okular=4:26.08.2-1`).
The script runs `build-in-container-1.sh`: the patch in a series of its own, the dependency on the edition's Qt, the changelog entry dated by this folder's last commit, `lean.debian_prepare`, `dpkg-buildpackage -sa` with the link and start gate, and `lean.release check-debs`.

## Credits

- Okular's page view, which this change touches: Enrico Ros, Albert Astals Cid, Wilco Greven, Christophe Devriese, Laurent Montel, Dirk Mueller and Klarälvdalens Datakonsult AB (KDAB), as `part/pageview.cpp` names them, and every Okular contributor since.
- Debian's packaging, which this build keeps: the Debian Qt/KDE Maintainers, with Aurélien Couderc and Patrick Franz as uploaders.
- The design (the desk one step down, the paper at the window's plane, nothing popped) is Daniel Campos Ramos's.
