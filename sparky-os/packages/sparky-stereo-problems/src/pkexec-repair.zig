// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later

// Its own executable: the same repair implementation, with fixed stores and a repair-only argument grammar.
pub const polkit_repair_entry = true;
pub const main = @import("main.zig").main;
