#!/usr/bin/env bash
# Offline static checks + pure-logic unit tests. Does NOT replace Roblox Studio
# multiplayer tests (docs/TEST_PLAN.md). Requires stylua, selene, lune (rokit.toml);
# rojo is optional (place build check).
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== stylua (format check)"
stylua --check src tests

echo "== selene (lint, std=roblox)"
selene src

echo "== lune unit tests (pure logic)"
lune run tests/run

if command -v rojo >/dev/null 2>&1; then
    echo "== rojo build (place assembles)"
    out="$(mktemp -d)/RoboPushArena.rbxl"
    rojo build default.project.json -o "$out"
    echo "built $out"
else
    echo "== rojo not installed; skipped place build"
fi
