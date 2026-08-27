"""Find a damaged global root in a core, and name what registered it.

    gdb -q -batch -x audit_roots.py --core=<core> <executable>

Needs a debug runtime: the stamp each cell is checked against and the table
mapping a root to its registrant are both kept only there.
"""

import gdb

def stamp():
    """The runtime exports what it stamps cells with, so it is read from the
    image rather than kept as a second copy here."""
    try:
        return int(gdb.parse_and_eval("caml_skipcell_stamp"))
    except gdb.error:
        raise gdb.GdbError(
            "no caml_skipcell_stamp: this needs a runtime built with the "
            "cell stamp, reached through -runtime-variant d")


def cells(name):
    """Walk one skiplist, yielding its cells."""
    try:
        sk = gdb.parse_and_eval(name)
    except gdb.error:
        return
    node = sk["forward"][0]
    seen = 0
    while int(node) != 0 and seen < 1_000_000:
        yield node.dereference()
        try:
            node = node.dereference()["forward"][0]
        except gdb.MemoryError:
            print(f"  {name}: list truncated, a forward pointer is unreadable")
            return
        seen += 1


def origin_of(root):
    """The pc recorded for this root, if the debug runtime kept one."""
    for c in cells("roots_origin"):
        try:
            if int(c["key"]) == root:
                return int(c["data"])
        except gdb.MemoryError:
            pass
    return None


def describe(pc):
    """Name the call site. The recorded pc is a return address, so the lookup
    is one byte back, inside the call rather than after it."""
    if pc is None:
        return "no origin recorded"
    site = pc - 1
    try:
        block = gdb.block_for_pc(site)
    except gdb.error:
        block = None
    while block is not None and block.function is None:
        block = block.superblock
    where = block.function.name if block is not None else "unknown"

    try:
        sal = gdb.find_pc_line(site)
    except gdb.error:
        sal = None
    if sal is not None and sal.symtab is not None and sal.line != 0:
        return f"{where} at {sal.symtab.filename}:{sal.line} ({pc:#x})"
    return f"{where} ({pc:#x}), no line info"


def name_of(addr):
    """A root that lives in a static has a name; one inside a malloc'd table
    does not."""
    try:
        line = gdb.execute(f"info symbol {addr:#x}", to_string=True).strip()
    except gdb.error:
        return None
    if not line or line.startswith("No symbol"):
        return None
    return line.split(" in section")[0].strip()


class AuditRoots(gdb.Command):
    def __init__(self):
        super().__init__("audit-roots", gdb.COMMAND_USER)

    def invoke(self, arg, from_tty):
        st = stamp()
        bad = 0
        total = 0
        for name in ("caml_global_roots",
                     "caml_global_roots_young",
                     "caml_global_roots_old"):
            for c in cells(name):
                try:
                    key, check = int(c["key"]), int(c["check"])
                except (gdb.MemoryError, gdb.error):
                    print(f"{name}: unreadable cell")
                    bad += 1
                    continue
                total += 1
                if check == (key ^ st):
                    continue
                bad += 1
                was = check ^ st
                who = name_of(was)
                where = f"{was:#x}" + (f" ({who})" if who else "")
                print(f"{name}: cell filed under {key:#x}")
                print(f"  inserted under      {where}")
                print(f"  registered by       {describe(origin_of(was))}")
        print(f"\n{total} roots checked, {bad} damaged")


AuditRoots()
gdb.execute("audit-roots")
