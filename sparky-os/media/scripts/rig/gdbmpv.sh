#!/bin/sh
exec gdb -batch -ex "set pagination off" -ex "set debuginfod enabled off" -ex run -ex "bt 25" --args mpv "$@"
