#!/bin/bash
# usage: pitchkeys.sh <prefix> <id>: c1 straight ahead; c2 after dragging down 200 px (look up 27.8 degrees); c3 after 8 presses of Right;
# c4 after 5 presses of Up (52.8 up); c5 after 20 presses of Down (47.2 down)
# Workstation paths come from the local configuration: sparky-os/config/build.conf.example.
W=${SPARKY_WORKSPACES:?}/plasmatube
IMG=${IMG:-pt-run:C} $W/run/rp.sh $1 $2 '[["wait",12],["fi",760,300],["wait",1],["fi",730,477,"click"],["wait",2],["fi",1000,650],["wait",3],["cap","c1"],["fi",900,150,"drag",900,350],["wait",1.5],["fi",1000,650],["wait",3],["cap","c2"],["fk",106,8],["wait",3],["cap","c3"],["fk",103,5],["wait",3],["cap","c4"],["fk",108,20],["wait",3],["cap","c5"]]' >/dev/null 2>&1
