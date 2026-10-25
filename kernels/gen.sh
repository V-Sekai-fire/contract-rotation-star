#!/usr/bin/env bash
# The rotation-star kernels, from Lean to both targets.
#
#   kernels/gen.sh              # emit from Lean, then slangc cpp + spirv into kernels/
#   kernels/gen.sh --no-emit    # use the committed slang/ (no lake)
#   kernels/gen.sh --check      # regenerate everything in a temp copy; exit 1 if any committed
#                               # file (slang, cpp, spv) differs. The Lean pins need no check
#                               # here: `lake build` proves emit = expected, and this proves
#                               # emit = the committed slang.
#
#   Lean (lean/, `lake exe emit_rotation_star`)  ->  slang/<k>.slang     (committed)
#     slangc -target cpp                          ->  cpp/<k>_emit.cpp    (committed)
#     slangc -target spirv -fp-mode precise       ->  spv/<k>.spv         (committed)
#
# slangc is pinned to 2026.13 (SLANGC overrides the binary): another version emits different
# text, and --check would report it. -fp-mode precise keeps the GPU from fusing a*b+c, so it
# rounds in the order the C++ path does (the tests build the C++ with -ffp-contract=off).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SLANGC="${SLANGC:-slangc}"
KERNELS="star_kabsch swing_twist"
MODE=emit
case "${1:-}" in
	--no-emit) MODE=none ;;
	--check) MODE=check ;;
	"") ;;
	*) echo "unknown option: $1" >&2; exit 2 ;;
esac

# gen <kernels dir>: emit (unless --no-emit) and compile into <dir>/{slang,cpp,spv}.
gen() {
	local out="$1"
	mkdir -p "$out/slang" "$out/cpp" "$out/spv"
	if [ "$MODE" != none ]; then
		( cd "$ROOT/lean" && lake exe emit_rotation_star "$out/slang" >/dev/null )
	fi
	for k in $KERNELS; do
		# Relative paths: slangc writes the input path into a #line directive.
		( cd "$out" && "$SLANGC" -target cpp -stage compute -entry main -o "cpp/${k}_emit.cpp" "slang/$k.slang" )
		"$SLANGC" -target spirv -profile sm_6_5 -stage compute -entry main -fp-mode precise \
			-o "$out/spv/$k.spv" "$out/slang/$k.slang"
	done
}

if [ "$MODE" = check ]; then
	TMP="$(mktemp -d)"
	trap 'rm -rf "$TMP"' EXIT
	gen "$TMP"
	rc=0
	for k in $KERNELS; do
		for f in "slang/$k.slang" "cpp/${k}_emit.cpp" "spv/$k.spv"; do
			if ! cmp -s "$TMP/$f" "$HERE/$f"; then echo "stale: kernels/$f"; rc=1; fi
		done
	done
	[ $rc = 0 ] && echo "kernels current"
	exit $rc
fi
gen "$HERE"
echo "== $(echo $KERNELS | wc -w | tr -d ' ') kernels into kernels/{slang,cpp,spv} =="
