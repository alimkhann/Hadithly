#!/bin/sh
set -eu
freshclam --stdout >/dev/null 2>&1 || true
freshclam --daemon --stdout >/dev/null 2>&1 &
exec python processor.py
