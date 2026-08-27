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

## What it needs

A compiler carrying the three changes, and `-runtime-variant d` in `dune`.
Without them `crash.exe` faults inside the collector and the core says nothing,
which is the situation these exist to get out of.

## What it does not catch

The stamp covers a cell's key, not the pointers that chain it: a write landing
on those leaves the list unwalkable, and the script says so rather than naming
anything. A root inside a malloc'd table has no name, only an address, though
what registered it is still known.

The damage here is done outright, by a line in `stubs.c`. That is what an
overrun or a use-after-free leaves behind, but arriving there through one
depends on what the allocator does with the freed block, which is not something
an example can rest on.
