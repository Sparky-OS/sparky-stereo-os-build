#!/bin/bash
# usage: pan.sh <name> <id> [steps...]: play a video, capture, drag the view 40 degrees to the right (36 for VR180), capture again, and again
W=/K3D/temp/partners/queue/plasmatube
name=$1; id=$2; dx=${3:-289}
IMG=${IMG:-pt-run:C} $W/run/rp.sh $name $id '[["wait",12],["fi",760,300],["wait",1],["fi",730,477,"click"],["wait",2],["fi",1000,650],["wait",3],["cap","c1"],["fi",1000,300,"drag",'$((1000-dx))',300],["wait",1.5],["fi",1000,650],["wait",3],["cap","c2"],["fi",1000,300,"drag",'$((1000-dx))',300],["wait",1.5],["fi",1000,650],["wait",3],["cap","c3"]]' >/dev/null 2>&1
