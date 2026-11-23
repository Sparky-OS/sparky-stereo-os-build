# KIO Frameworks 6.32 successor

Prepare this manifest with `release/prepare-frameworks-successor.py`, then run the ordinary Lean Code source and binary build on amd64.
The descriptor hashes bind Debian 6.32.0-1 and the published edition 6.30.0-1+stereo3d11+lc1, including every source component.
Every published patch is retained; the manifest records each fate and each rebased patch hash.
The additional accepted catalogue completes the seven GPU-launch messages in Spanish.
The published template preservation plan, Graphics resolver minimum and edition changelog remain.

## Rebase audit

Upstream v6.30.0 to v6.32.0 changes were read alongside the current default branch, thumbnail/GPU merge requests and issues.
No edition patch is redundant in the new source.
Debian disabled report_error_removing_dirs during the refactor; this successor retains its behavior.
The error is delivered when deleteNextDir finishes, after the new destination flush and retained-source deletion phases, rather than from the old setNextDirAttribute completion point.
Upstream commits bdfd848ab9cc0ab499387a4d74a337366756a447 and e135cd32bd06b072a1c436b9d002afcc3aeae6fa introduced those phases.
The download guard retains upstream cancellation and local-copy cleanup (ea07e1bd96b0d0af57c8d272c106faa4ddc045c6 and 525140d1cbee11a9f171566bfdb609c106076b22).
All new upstream cache and download tests remain alongside the published edition tests.
The launcher keeps the new knownMimeType parameter while preserving GPU routing, D-Bus activation and painting precedence.
Japanese and Simplified Chinese catalogue anchors moved; their published message bytes do not change.

## Qualification

Commit the recipe before the build and require a clean build record.
Run the published thumbnail and application-launcher tests, including negative controls, against installed successor libraries.
Compare every binary path with both the published edition and Debian before qualifying it.
The round also requires the complete source closure, catalogue, Lean Code, link/start and installed transaction gates.
A real-machine bench must start Dolphin, the file dialog and programs through the application launcher before accepting this common library.
