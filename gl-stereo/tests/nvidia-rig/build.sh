#!/bin/sh
cd /rig && gcc -O2 -Wall -o sdl2_stereo sdl_stereo.c $(sdl2-config --cflags --libs) -lGL && gcc -O2 -Wall -DSDL3 -o sdl3_stereo sdl_stereo.c $(pkg-config --cflags --libs sdl3) -lGL && echo built
