"""python3 cellcmp.py A B: compare two '@@ step label' dumps cell by cell
(character, fg, bg, attributes); spaces ignore fg unless underline/reverse."""
import re, sys

def parse_steps(path):
    steps, cur = [], None
    for line in open(path, encoding="utf-8", errors="replace").read().split("\n"):
        if line.startswith("@@ "):
            cur = [line, []]; steps.append(cur)
        elif cur is not None:
            cur[1].append(line)
    return [(h, "\n".join(b).rstrip("\n")) for h, b in steps]

SGR = re.compile(r"\x1b\[([0-9;]*)m")
def cells(text):
    rows, st = [], {}
    for raw in text.split("\n"):
        row, i = [], 0
        while i < len(raw):
            m = SGR.match(raw, i)
            if m:
                ps = [int(x) if x else 0 for x in m.group(1).split(";")] if m.group(1) else [0]
                k = 0
                while k < len(ps):
                    p = ps[k]
                    if p == 0: st = {}
                    elif p in (38, 48):
                        key = "fg" if p == 38 else "bg"
                        if ps[k+1] == 5: st[key] = ("5", ps[k+2]); k += 2
                        else: st[key] = ("2",) + tuple(ps[k+2:k+5]); k += 4
                    elif 30 <= p <= 37 or 90 <= p <= 97: st["fg"] = p
                    elif 40 <= p <= 47 or 100 <= p <= 107: st["bg"] = p
                    elif p == 39: st.pop("fg", None)
                    elif p == 49: st.pop("bg", None)
                    elif p in (1, 2, 3, 4, 5, 7): st["a%d" % p] = True
                    elif p == 22: st.pop("a1", None); st.pop("a2", None)
                    elif p in (23, 24, 25, 27): st.pop("a%d" % (p - 20), None)
                    k += 1
                i = m.end(); continue
            ch = raw[i]
            s = dict(st)
            if ch == " " and not (s.get("a4") or s.get("a7")):
                for a in ("fg", "a1", "a2", "a3", "a5"): s.pop(a, None)
            row.append((ch, tuple(sorted(s.items()))))
            i += 1
        while row and row[-1][0] == " " and not row[-1][1]: row.pop()
        rows.append(row)
    while rows and not rows[-1]: rows.pop()
    return rows

a, b = parse_steps(sys.argv[1]), parse_steps(sys.argv[2])
bad = 0
if len(a) != len(b): print("step counts differ", len(a), len(b))
for (ha, ta), (hb, tb) in zip(a, b):
    same_bytes = ta == tb
    if cells(ta) != cells(tb):
        bad += 1
        print("DIFF", ha)
        print("  old:", repr(ta)); print("  new:", repr(tb))
    else:
        print("ok  " + ("bytes " if same_bytes else "cells ") + ha)
print("differ:", bad, "of", len(a))
