#!/bin/sh
# usage: multi.sh SESSIONS K PLATFORM PATH PROG
S=$1; shift; K=$1; shift
n=0
while [ $n -lt $S ]; do n=$((n+1)); sh /rig/session_multi.sh "$1" "$2" "$3" $K 2>&1 | grep '^client'; done
