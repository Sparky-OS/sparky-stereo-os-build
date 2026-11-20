
## Screenshot replies on the replica successor (+stereo3d62)

`prepare-source-62.sh STAGED_61_DIR OUT TOOLKIT` keeps the complete +61 descriptor source and adds only the accepted screenshot-plugin/test commits from order772-kwin (ScreenShot2 version 7 and stereoOutput). The two upstream context fixes retain their original authors. The existing screenshot suite and the new reply suite remain source tests; no tests are added to the installed package payload. `build-62.sh` follows build-61.sh's seven-argument form with a +61 previous directory and cohort, a clean recipe commit, native Lean Code and the archive link/start gate. Use an owned build image/container prefix and four CPU threads. No compositing, backend, protocol or package relation change is added by this successor.
