#!/bin/sh
# Builds ZX81.COM into build/. Needs sjasmplus.
cd "$(dirname "$0")" || exit 1
SJ=${SJASMPLUS:-sjasmplus}
command -v $SJ >/dev/null || SJ=$HOME/.local/bin/sjasmplus
mkdir -p build
$SJ --nologo --msg=war --lst=build/zx81.lst --raw=build/ZX81.COM zx81.asm
