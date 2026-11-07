#!/usr/bin/env python3
"""Convert the tt++ map (aardwolf-tintin/map/map-all.tt) to Rune's map file.

Usage:  convert_ttmap.py <map-all.tt> <out.map>

Reads the tt++ map only - never writes it. The output is plain text, one
record per line, fields separated by TAB:

  R  vnum  area  terrain  data  note  name
  X  from  to    exit     flags cmds

R - a room. data is the tt++ roomdata (1 = no portal, 2 = no recall,
    3 = both, empty = nothing known); note is the tt++ roomnote (the rmsg
    room message).
X - an exit from room `from` to room `to`, named `exit` (n, e, ..., or a
    special one like "enter portal"). flags is the tt++ exit flag (2 =
    avoid). cmds is what to send to take it, game commands joined with ";",
    empty when it is just the exit name.

tt++ syntax in exit commands is translated: "#send {op e}" becomes "op e",
and the spaces around ";" go. Anything else starting with "#" can't be
translated - it is kept as is and listed in the report.
"""
import re
import sys

FIELD = re.compile(r'\{((?:[^{}]|\{[^{}]*\})*)\}')
SEND = re.compile(r'^#send\s*\{(.*)\}$', re.IGNORECASE)


def clean(text):
    """No TABs or newlines inside a field."""
    return text.replace('\t', ' ').replace('\n', ' ').replace('\r', ' ')


def translate(cmd, problems, where):
    parts = []
    for part in cmd.split(';'):
        part = part.strip()
        if not part:
            continue
        m = SEND.match(part)
        if m:
            part = m.group(1).strip()
        elif part.startswith('#'):
            problems.append(f'{where}: {cmd!r}')
        parts.append(part)
    return ';'.join(parts)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    rooms = exits = cmds = 0
    problems = []
    current = None
    with open(src, encoding='utf-8', errors='replace') as f, \
         open(dst, 'w', encoding='utf-8') as out:
        for line in f:
            if line.startswith('R '):
                fl = FIELD.findall(line)
                # vnum flags color name symbol desc area note terrain data weight id
                current = fl[0]
                out.write('\t'.join(['R', fl[0], clean(fl[6]), clean(fl[8]),
                                     clean(fl[9]), clean(fl[7]), clean(fl[3])]) + '\n')
                rooms += 1
            elif line.startswith('E ') and current is not None:
                fl = FIELD.findall(line)
                # to name cmd dir flags data weight color decay
                to, name, cmd, flags = fl[0], fl[1], fl[2], fl[4]
                sends = translate(cmd, problems, f'{current} -> {to} ({name})')
                if sends == name:
                    sends = ''
                else:
                    cmds += 1
                out.write('\t'.join(['X', current, to, clean(name),
                                     flags if flags != '0' else '', clean(sends)]) + '\n')
                exits += 1
    print(f'{rooms} rooms, {exits} exits ({cmds} with their own commands) -> {dst}')
    if problems:
        print(f'{len(problems)} exit command(s) kept untranslated:')
        for p in problems:
            print('  ' + p)
    else:
        print('every exit command translated cleanly')


if __name__ == '__main__':
    main()
