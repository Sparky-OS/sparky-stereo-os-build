# Gwenview per-file eye correction

Run `prepare-source.py SOURCE VERSION` on an extracted edition Gwenview source
package with its existing quilt series applied. The source already contains
the standard native Lean Code hooks, which this preparation retains unchanged.
Build one source package, then build its architecture packages from that `.dsc`.

The existing Swap eyes action is stored by encoded file URL in Gwenview's own
`gwenviewstereorc`. Opening another image loads its own choice and updates the
action. Legacy file attributes are read as defaults only; the action writes
Gwenview configuration and never changes image bytes or attributes.
