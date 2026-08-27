#!/bin/sh
# A walkthrough: what each step runs, what the code under it does, and what
# came back.
OCAMLRUNPARAM=v=0
export OCAMLRUNPARAM
status=0

say()  { printf '%s\n' "$*"; }
cmd()  { printf '   $ %s\n' "$*"; }
out()  { printf '%s\n' "$1" | sed 's/^/       /'; }
step() { printf '     %s\n' "$*"; }

expect() {
  want_ok=$1; got=$2; rc=$3; shift 3
  if [ "$want_ok" = yes ] && [ "$rc" -ne 0 ]; then
    say "   FAIL: exited $rc"; status=1; return
  fi
  if [ "$want_ok" = no ] && [ "$rc" -eq 0 ]; then
    say "   FAIL: exited 0, expected it to die"; status=1; return
  fi
  for want in "$@"; do
    if ! printf '%s' "$got" | grep -q "$want"; then
      say "   FAIL: nothing matching \"$want\""; status=1; return
    fi
  done
  say "   ok"
}

say ""
say "1. Which binding owns a given root"
say ""
step "decoder_alloc() mallocs a table and registers a root per channel"
step "metadata_open() registers one root for the charset"
step "the runtime kept the return address of each caller"
step "caml_global_root_origin() hands it back, dladdr() names it"
say ""
cmd "./provenance.exe"
o=$(./provenance.exe 2>&1); rc=$?
out "$o"
expect yes "$o" "$rc" "registered by decoder_alloc" "registered by metadata_open"

say ""
say "2. Which step damaged a root, while the program is still running"
say ""
step "the program does three things in turn"
step "Gc.check_roots () after each one walks the lists and checks every cell"
step "  against the key it was inserted with"
step "the first two pass, so the damage belongs to the third"
say ""
cmd "./audit.exe"
o=$(./audit.exe 2>&1); rc=$?
out "$o"
expect no "$o" "$rc" "opened the decoder: roots intact" \
  "read the metadata: roots intact" "skiplist cell at"

say ""
say "3. A damaged root left for the collector to find"
say ""
step "nothing checks, so the damage sits until something walks the roots"
step "a stray write has set a bit in the address a root is filed under,"
step "  which is what an overrun or a use-after-free leaves behind"
step "Gc.full_major () walks them, and the scan refuses the key rather"
step "  than dereferencing it"
say ""
cmd "./crash.exe"
o=$(./crash.exe 2>&1); rc=$?
out "$o"
expect no "$o" "$rc" "global root at" "registered by"

say ""
say "4. The same finding, with only the core left"
say ""
step "crash.exe from the step above is run again, and only its core is used"
step "this is the case worth having: the collector's backtrace names itself,"
step "  and the address in it says nothing about who owns the root"
step "the stamp and the table of registrants are both in the core"
step "the script walks the three root lists, checks each cell against its"
step "  stamp, and looks the survivor up in the table of registrants"
say ""
core=$(mktemp -d)/core
( cd "$(dirname "$core")" && ulimit -c unlimited 2>/dev/null
  "$OLDPWD"/crash.exe >/dev/null 2>&1 ) 2>/dev/null
found=$(find "$(dirname "$core")" -name 'core*' -print -quit 2>/dev/null)
if [ -z "$found" ] && command -v coredumpctl >/dev/null 2>&1; then
  cmd "coredumpctl dump -o core"
  coredumpctl dump -o "$core" >/dev/null 2>&1 && found=$core
fi

if [ -z "$found" ]; then
  say "   skipped: no core available on this system"
else
  cmd "gdb -q -batch -x audit_roots.py --core=core ./crash.exe"
  o=$(gdb -q -batch -iex "set debuginfod enabled off" \
          -x audit_roots.py --core="$found" ./crash.exe 2>&1 \
      | grep -vE "libthread|^\[|warning:|Core was|Program term|^#")
  out "$o"
  expect yes "$o" 0 "registered by  *metadata_open"
fi

say ""
exit $status
