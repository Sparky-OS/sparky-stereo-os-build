# Copying recipe inputs

Run `python3 tools/copy-recipe.py SOURCE DESTINATION` to copy a folder's contents into a disposable staging directory.
In a Git checkout it copies the working bytes of exactly the indexed files, using `git ls-files --stage -z` and `cp -a --parents`.
Local edits to tracked files are kept; untracked files and directories are not copied.
Symlinks are preserved without copying their targets.
Submodules must be exported separately; unresolved index entries and tracked files replaced by directories are errors.

In an export or unpacked source tree without Git metadata it copies files except `.git`, `__pycache__` and `*.pyc`.
Both routes announce the rule they use.
Git is required to distinguish an export from a failed checkout lookup.
Unreadable or missing inputs and failed commands stop the build; they never enable a broader copy.
The destination must be outside the source, with no symlink at any copied destination path.
Use a fresh destination to ensure it contains no files from an earlier build.

Recipes reference this one helper from the build tree, and retain it with their authoring inputs when those inputs are shipped.
The script/data source packages created by `lean.standalone` rebuild through `debian/rules` and `build.py` using their retained `tree/` and `release-toolkit/`.
That rebuild does not need Git, the original checkout, this helper, or a new repository index.
A recipe that runs its original builder from a source package must also include the helper at the relative path that builder calls.

Run `python3 tools/tests/test_copy_recipe.py` as a regular user in a disposable container.
Set TMPDIR to a scratch directory outside any Git checkout.
