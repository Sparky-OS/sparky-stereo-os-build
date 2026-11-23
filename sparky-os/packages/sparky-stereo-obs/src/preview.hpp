/* SPDX-License-Identifier: GPL-3.0-or-later */
/* SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack) <Capitain_Jack@yahoo.com> */
#pragma once

namespace SparkyStereo {

// Every OBS display (the preview, studio mode's program view, the projectors) followed from now on: declared as a 3D
// area holding both eyes while the canvas is 3D, the left eye whole and said where it cannot be.
void watchPreviews();
// After the canvas's layout changed.
void updatePreviews();

} // namespace SparkyStereo
