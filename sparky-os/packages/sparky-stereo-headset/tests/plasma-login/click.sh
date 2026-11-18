#!/bin/bash
# click.sh "m:X,Y s:300 b:272": the steps go to KWin's fake input (logical pixels), through one connected client (see references/input-delivery.md)
. /home/rig/env.sh
/out/fakeinput "$@"
