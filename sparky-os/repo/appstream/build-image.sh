#!/bin/bash
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
exec docker build -t sparky-appstream-generator:1.0.0-1 "$HERE"
