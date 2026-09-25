#!/bin/sh
# ---------------------------------------------------------------------------
# Native Windows (MinGW-w64) build driver for OpenRadioss.
#
#   ./build_mingw64.sh <target> [jobs]
#
#     target = starter | engine | both     (default: engine)
#     jobs   = parallel compile jobs       (default: 16)
#
# Third-party static libraries must already be in
#   extlib/build_mingw64/lib/    (see extlib/build_mingw64/README.md)
#
# The build is driven from the repository root CMakeLists.txt, exactly like
# the official build_script.sh / build_windows.bat, so that the executable
# names (starter_win64_gf / engine_win64_gf) are defined.
#
# Ninja is used rather than mingw32-make: GNU make 4.4.1 ships with
# MinGW-w64 15.2 and segfaults in its jobserver as soon as -j > 1 is used.
# ---------------------------------------------------------------------------
set -e

ROOT=$(cd "$(dirname "$0")" && pwd)
MINGW="${MINGW_ROOT:-/g/x86_64-15.2.0-release-win32-seh-ucrt-rt_v13-rev0/mingw64}"
NINJA="$ROOT/extlib/build_mingw64/bin/ninja.exe"
export PATH="$MINGW/bin:$ROOT/extlib/build_mingw64/bin:$PATH"

TARGET="${1:-engine}"
JOBS="${2:-16}"
BUILD="$ROOT/build_mingw64_$TARGET"

case "$TARGET" in
  starter|engine|both) ;;
  *) echo "usage: $0 {starter|engine|both} [jobs]"; exit 1 ;;
esac

[ -x "$NINJA" ] || { echo "ninja not found at $NINJA"; exit 1; }

mkdir -p "$BUILD"
cd "$BUILD"

echo "=== configuring ($TARGET) ==="
cmake -G Ninja \
      -DCMAKE_MAKE_PROGRAM="$NINJA" \
      -DCMAKE_BUILD_TYPE=Release \
      -Darch=win64_gf \
      -Dbuild="$TARGET" \
      -Dstarter=starter_win64_gf \
      -Dengine=engine_win64_gf \
      -Dprecision=dp \
      -Ddebug=0 \
      -DMPI=smp \
      -DPYTHON_EXEC=python \
      -DCMAKE_Fortran_COMPILER="$MINGW/bin/gfortran.exe" \
      -DCMAKE_C_COMPILER="$MINGW/bin/gcc.exe" \
      -DCMAKE_CXX_COMPILER="$MINGW/bin/g++.exe" \
      "$ROOT" > configure.log 2>&1 || {
        echo "CONFIGURE FAILED - see $BUILD/configure.log"; tail -40 configure.log; exit 1
      }
grep -E "Exec name|Loading|Precision|MPI:" configure.log || true

echo "=== building ($TARGET, -j $JOBS) ==="
set +e
"$NINJA" -j "$JOBS" > build.log 2>&1
RC=$?
set -e
tail -3 build.log
if [ $RC -ne 0 ]; then
  echo "BUILD FAILED - see $BUILD/build.log"
  grep -nE "error:|Error|FAILED" build.log | head -25
  exit 1
fi

echo ""
echo "=== executables ==="
ls -la "$ROOT/exec/" 2>/dev/null || echo "(no exec/ directory)"
