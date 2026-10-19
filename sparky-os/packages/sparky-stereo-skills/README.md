sparky-stereo-skills
The public skills of Sparky Stereo OS for distribution maintainers, usable directly by humans and with local or hosted AI partners. Optional links retain integration with existing assistants.

Copyright (C) 2026 Paweł Pijanowski, Daniel Ramos (Capitain Jack) and others, see copyright file.

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.

The skills, documents and tools in /usr/share/sparky-stereo-os come from https://github.com/Sparky-OS/sparky-stereo-os at the commit named in /usr/share/sparky-stereo-os/SOURCE (documents under CC BY 4.0, tools under the GPL, version 2 or later).

Usage (as yourself, never as root):
-------------
sparky-stereo-skills                 each assistant folder, found or not, and how many skills are linked there
sparky-stereo-skills link [NAME...]  link every skill into the folders of the assistants found, or the folders named
sparky-stereo-skills unlink [NAME...] remove only the links this tool made
sparky-stereo-skills list            the skills and what each is for
sparky-stereo-skills tools           the folder names: agents, claude, cline, gemini, opencode, copilot, cursor
sparky-stereo-skills context native-linux --output /tmp/native-linux-context.txt
                                    selected instructions, identity and file hashes, with a character budget
sparky-stereo-skills context --help  section/reference selection and context limits
sparky-stereo-skills bundle FILE.zip complete public reference tree for offline extraction
sparky-stereo-skills export FILE.zip one archive for Open WebUI (Workspace, Skills, Import)
sparky-stereo-skills --project DIR link   link into a project's .agents/skills and .claude/skills
sparky-stereo-skills --gui           the same choice in a dialog (also in the menu: Development, AI assistant skills)

Where the assistants read skills (their own documentation, read 2026-10-16):
-------------
~/.agents/skills            Codex https://learn.chatgpt.com/docs/build-skills, Gemini CLI https://geminicli.com/docs/cli/skills/, OpenCode https://opencode.ai/docs/skills/, GitHub Copilot https://code.visualstudio.com/docs/copilot/customization/agent-skills, Cursor https://cursor.com/docs/skills, goose https://goose-docs.ai/docs/guides/context-engineering/using-skills
~/.claude/skills            Claude Code https://code.claude.com/docs/en/skills (also OpenCode, GitHub Copilot, goose)
~/.cline/skills             Cline https://docs.cline.bot/customization/skills
~/.gemini/skills, ~/.config/opencode/skills, ~/.copilot/skills, ~/.cursor/skills   each tool's own folder, by choice
Open WebUI                  a ZIP of skill folders, imported in Workspace, Skills https://docs.openwebui.com/features/workspace/skills
Ollama                      ollama launch starts Claude Code, Codex or OpenCode on an Ollama model https://docs.ollama.com/cli; they read the folders above

At login (/etc/xdg/autostart/sparky-stereo-skills.desktop): when the person said yes before, the links follow an upgrade (new skills linked, removed ones unlinked); otherwise, when an assistant is found and nothing was decided, the dialog is offered once (Link, Not now, Never ask again). The package itself never writes into home folders. Run sparky-stereo-skills unlink before removing the package, or the links are left dangling.

Dependencies:
-------------
gawk | mawk
python3
python3-yaml
yad

Build:
-------------
OUT=dir SKILLS_COMMIT=<reviewed-commit> ./build.sh
SKILLS_SRC names the public checkout. The build resolves the commit, validates the instructions, and records SOURCE plus MANIFEST.sha256. The source package includes the snapshot and rebuilds without the checkout.
A local working-tree candidate must instead provide a bundled public/ snapshot with an honest SOURCE (candidate status, base commit, date) and MANIFEST.sha256; it is not a release pin.
The candidate version is UNRELEASED until integration and publication. The task recipe includes this package only in task-sparky-stereo-os-developer; ordinary developers can install it explicitly.

Test:
-------------
tests/helper.sh   (as an ordinary user, with the package installed, in a container)
python3 /usr/share/sparky-stereo-os/tools/check-skills.py
python3 /usr/share/sparky-stereo-os/tools/tests/test-skills-context.py
The context and complete reference bundle require no model, account or network. Skill-import ZIPs may not carry references outside each skill folder; use bundle for the whole tree.

Install:
-------------
sudo OUT=dir ./install.sh

Uninstall:
-------------
sudo ./install.sh uninstall
