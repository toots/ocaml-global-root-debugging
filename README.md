# Naming the owner of a damaged global root

When a C binding damages a global root, the collector is what finds out,
walking the roots some time later. All it can say by then is where it was
standing, which is `caml_darken`. Who registered the root is in neither the
backtrace nor the core.

Three additions to the debug runtime keep enough to name it: each root
remembers the code that registered it, each skiplist cell carries the key it
was inserted with, and `Gc.check_roots ()` walks the lists on demand.

    dune build && dune runtest

Four cases, live to post-mortem: which binding owns a root, which step damaged
one, what the collector says when nothing checks, and the same finding from a
core alone.

    caml_global_roots: cell filed under 0x1000000552890
      inserted under      0x552890 (metadata_charset)
      registered by       metadata_open at stubs.c:76 (0x4995ec)

`runtest` prints each command and what it does. `stubs.c` plays the part of the
binding.

## The three changes to the runtime

All under `DEBUG`, so a release build carries none of them and pays nothing.

**Each root remembers what registered it.** `caml_register_global_root` and
`caml_register_generational_global_root` take `__builtin_return_address(0)` and
file it in a skiplist beside the root's address, which `caml_global_root_origin`
reads back. Moving a generational root between the young and old lists leaves it
alone: the owner has not changed. Removing forgets it.

**Each skiplist cell carries the key it was inserted with.** `struct skipcell`
gains a `check` field holding `key ^ 0x5ADD1E5F`, and `caml_iterate_global_roots`
tests it before dereferencing the key. A cell whose key has been overwritten is
refused and reported with its owner, in place of a fault inside `caml_darken`.
The stamping is done by the skiplist, so `codefrag`, `debugger` and `platform`
carry it too and can be checked the same way, though nothing checks them.

**`Gc.check_roots ()`** walks the three lists on demand and fails the same way,
for finding which step of a program damages a root rather than waiting for the
collection that trips over it.

## audit_roots.py

The other files here are examples. This one is the tool: a gdb script to point
at a core of your own, where there is no process left to ask. It works on an
attached process too.

    gdb -q -batch -x audit_roots.py --core=core ./crash.exe

It reads the runtime's own structures:

- `caml_global_roots`, `caml_global_roots_young` and `caml_global_roots_old`
  are the three skiplists the runtime files roots in. Each is walked along
  `forward[0]`, which chains every cell.
- A cell is `{key, data, check}`. `key` is the root's address and `check` is
  `key ^ 0x5ADD1E5F`, written when the cell was inserted. `data` marks a cell
  retired during an iteration, and is not consulted here.
- A cell is damaged when `check` no longer agrees with `key`. Since the
  obfuscation is its own inverse, the address the cell was inserted under
  comes back as `check ^ 0x5ADD1E5F`, which is what the rest of the report is
  built from.
- `roots_origin` is a fourth skiplist, from a root's address to the return
  address of whoever registered it. It is looked up under the recovered
  address, the damaged one being filed nowhere.
- That return address points after the call, so the symbol lookup is one byte
  back: `block_for_pc` for the function, `find_pc_line` for file and line.
- The root's own address is passed to `info symbol`, which names it when the
  root is a static. A root the binding `malloc`'d was never given a name, so
  that line is left as an address. What registered it still resolves.

The walk is bounded and catches unreadable memory, so a cell whose chaining
pointers were hit reports a truncated list rather than throwing.

## What it needs

A compiler carrying those three, and `-runtime-variant d` in `dune`. Without
them `crash.exe` faults inside the collector and the core says nothing, which
is the situation these exist to get out of.

## What it does not catch

The stamp covers a cell's key, not the pointers that chain it: a write landing
on those leaves the list unwalkable, and the script says so rather than naming
anything. A root inside a malloc'd table has no name, only an address, though
what registered it is still known.

The damage here is done outright, by a line in `stubs.c`. That is what an
overrun or a use-after-free leaves behind, but arriving there through one
depends on what the allocator does with the freed block, which is not something
an example can rest on.
