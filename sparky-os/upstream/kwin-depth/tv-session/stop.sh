#!/bin/bash
# ends the test session cleanly
DIR=$(cd "$(dirname "$0")" && pwd)
touch "$DIR/stop"
