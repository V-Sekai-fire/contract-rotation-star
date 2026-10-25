#!/bin/sh
# Build and run the kernels' C++ emission against the Lean oracle (the CPU path).
#
#   tests/kernels/build.sh [--write <dir>]
#
# Each kernel's kernels/cpp/<k>_emit.cpp is compiled in its own unit (kernel_tu.cpp,
# -DRS_KERNEL=<n>) with only its *_run symbol kept global. -ffp-contract=off: no fused
# multiply-add, as the SPIR-V is built -fp-mode precise.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
OUT="$ROOT/build/kernel_test"
CXX=${CXX:-c++}
mkdir -p "$OUT"
n=0
OBJS=""
for k in star_kabsch swing_twist; do
	n=$((n + 1))
	"$CXX" -O2 -std=c++17 -ffp-contract=off -Wno-everything -DRS_KERNEL=$n -I"$ROOT/kernels/cpp" \
		-c "$HERE/kernel_tu.cpp" -o "$OUT/$k.full.o"
	if [ "$(uname)" = Darwin ]; then
		ld -r -exported_symbol "_${k}_run" "$OUT/$k.full.o" -o "$OUT/$k.o"
	else
		objcopy --keep-global-symbol="${k}_run" "$OUT/$k.full.o" "$OUT/$k.o"
	fi
	OBJS="$OBJS $OUT/$k.o"
done
"$CXX" -O2 -std=c++17 -ffp-contract=off "$HERE/test.cpp" $OBJS -o "$OUT/rs_kernel_test"
"$OUT/rs_kernel_test" "$ROOT/tests/oracle/oracle.txt" "$@"
