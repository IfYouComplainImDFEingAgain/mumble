#!/usr/bin/env bash
#
# Build helper for Mumble.
# Wraps the CMake configure + build steps documented in CLAUDE.md.
#
# Usage:
#   ./build.sh [options]
#
# Options:
#   -b, --build-dir DIR   Build directory (default: build)
#   -t, --type TYPE       CMake build type: Debug, Release, RelWithDebInfo (default: RelWithDebInfo)
#   -j, --jobs N          Parallel build jobs (default: number of CPUs)
#       --tests           Enable building tests (-Dtests=ON)
#       --run-tests       Enable and run tests after building (ctest)
#       --client-only     Build only the client (-Dserver=OFF)
#       --server-only     Build only the server (-Dclient=OFF)
#   -c, --clean           Remove the build directory before configuring
#       --no-werror       Turn off warnings-as-errors (-Dwarnings-as-errors=OFF)
#   -D<opt>=<val>         Pass any extra option straight through to CMake
#   -h, --help            Show this help
#
# Note: on GCC the surgical flag -Wno-error=sfinae-incomplete is auto-added.
# GCC 15+ introduced -Wsfinae-incomplete, which fires on Qt moc/metatype code
# (e.g. class User) and would otherwise break the -Werror build. All other
# warnings remain fatal. Override auto-detection by exporting NO_SFINAE_FIX=1.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BUILD_DIR="build"
BUILD_TYPE="RelWithDebInfo"
JOBS="$(nproc 2>/dev/null || echo 4)"
ENABLE_TESTS=0
RUN_TESTS=0
CLEAN=0
EXTRA_CMAKE_ARGS=()

usage() {
	sed -n '2,/^set -euo/{/^set -euo/d;s/^# \{0,1\}//;p}' "${BASH_SOURCE[0]}"
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		-b|--build-dir) BUILD_DIR="$2"; shift 2 ;;
		-t|--type)      BUILD_TYPE="$2"; shift 2 ;;
		-j|--jobs)      JOBS="$2"; shift 2 ;;
		--tests)        ENABLE_TESTS=1; shift ;;
		--run-tests)    ENABLE_TESTS=1; RUN_TESTS=1; shift ;;
		--client-only)  EXTRA_CMAKE_ARGS+=("-Dserver=OFF"); shift ;;
		--server-only)  EXTRA_CMAKE_ARGS+=("-Dclient=OFF"); shift ;;
		--no-werror)    EXTRA_CMAKE_ARGS+=("-Dwarnings-as-errors=OFF"); shift ;;
		-c|--clean)     CLEAN=1; shift ;;
		-D*)            EXTRA_CMAKE_ARGS+=("$1"); shift ;;
		-h|--help)      usage; exit 0 ;;
		*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
	esac
done

if ! command -v cmake >/dev/null 2>&1; then
	echo "error: cmake not found in PATH" >&2
	exit 1
fi

cd "$SCRIPT_DIR"

if [[ "$CLEAN" -eq 1 && -d "$BUILD_DIR" ]]; then
	echo ">> Removing build directory: $BUILD_DIR"
	rm -rf "$BUILD_DIR"
fi

CONFIGURE_ARGS=("-B" "$BUILD_DIR" "-DCMAKE_BUILD_TYPE=$BUILD_TYPE")
if [[ "$ENABLE_TESTS" -eq 1 ]]; then
	CONFIGURE_ARGS+=("-Dtests=ON")
fi

# GCC 15+ made -Wsfinae-incomplete a warning; under the project's -Werror it
# breaks compiling Qt moc/metatype code. Exempt just that one diagnostic.
CXX_BIN="${CXX:-c++}"
if [[ "${NO_SFINAE_FIX:-0}" != "1" ]] && "$CXX_BIN" --version 2>/dev/null | grep -qi -e '^g++' -e '(GCC)'; then
	if echo 'int main(){}' | "$CXX_BIN" -x c++ -Wno-error=sfinae-incomplete -c - -o /dev/null >/dev/null 2>&1; then
		CONFIGURE_ARGS+=("-DCMAKE_CXX_FLAGS=-Wno-error=sfinae-incomplete")
		echo ">> GCC detected: adding -Wno-error=sfinae-incomplete"
	fi
fi

CONFIGURE_ARGS+=("${EXTRA_CMAKE_ARGS[@]}")

echo ">> Configuring: cmake ${CONFIGURE_ARGS[*]}"
cmake "${CONFIGURE_ARGS[@]}"

echo ">> Building with $JOBS jobs"
cmake --build "$BUILD_DIR" -j "$JOBS"

if [[ "$RUN_TESTS" -eq 1 ]]; then
	echo ">> Running tests"
	ctest --test-dir "$BUILD_DIR" --output-on-failure
fi

echo ">> Done. Artifacts in: $BUILD_DIR"
