#!/bin/sh
# ssh into the lane's VM: BatchMode, no askpass, no DISPLAY (the key is used in place by ssh, never read here)
exec env -u DISPLAY -u WAYLAND_DISPLAY SSH_ASKPASS_REQUIRE=never ssh -p 2222 -i /srv/sparky-vm/id_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/K3D/temp/partners/queue/media-on-dmo/work/vm/known_hosts daniel@127.0.0.1 "$@"
