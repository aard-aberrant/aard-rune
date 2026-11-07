#!/usr/bin/env python3
"""One-time conversion of the tt++ travel data into Lua files for Rune.

Usage:  convert_ttdata.py <aardwolf-tintin dir> <out dir>

Reads (never writes) these tt++ files:
  conf/portals.tin    myportals, g_shortcuts, g_blacklist, g_home_cmds,
                      defaultportal, home_vnum
  conf/equipment.tin  portalbag
  conf/areas.tin      area_info
  conf/rooms.tin      room_labels

Writes into <out dir>:
  portals.lua  portals, g shortcuts, blacklist, home commands (hand-edited)
  areas.lua    zone slug -> name, keyword, level range
  labels.lua   label -> list of vnums (rewritten by Rune's label/unlabel)

After this, the Rune files are the master - tt++ and Rune each keep their own.
Each file is a plain "return { ... }", loaded with dofile.
"""
import os
import re
import sys


# --- tt++ nested-brace values ----------------------------------------------

def brace_end(s, i):
    """s[i] == '{'; index just past its matching '}'."""
    depth = 0
    for j in range(i, len(s)):
        if s[j] == '{':
            depth += 1
        elif s[j] == '}':
            depth -= 1
            if depth == 0:
                return j + 1
    raise ValueError('unbalanced braces')


def groups(s):
    """The top-level {...} groups in s, contents only."""
    out, i = [], 0
    while True:
        i = s.find('{', i)
        if i < 0:
            return out
        j = brace_end(s, i)
        out.append(s[i + 1:j - 1])
        i = j


def table(s):
    """A tt++ table {k}{v}{k}{v}... as a dict; values with braces nest."""
    g = groups(s)
    d = {}
    for k, v in zip(g[0::2], g[1::2]):
        d[k] = table(v) if '{' in v else v
    return d


def variable(text, name):
    """The value of #var / #variable NAME in a .tin file's text."""
    m = re.search(r'^#var(?:iable)?\s+\{?' + re.escape(name) + r'\}?\s+', text,
                  re.MULTILINE | re.IGNORECASE)
    if not m:
        raise KeyError(name)
    i = m.end()
    if text[i] == '{':
        return text[i + 1:brace_end(text, i) - 1]
    return text[i:].split('\n', 1)[0].strip()


# --- Lua output --------------------------------------------------------------

def lua_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def lua_key(k):
    if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', k) and k not in LUA_WORDS:
        return k
    return '[' + lua_str(k) + ']'


LUA_WORDS = set('and break do else elseif end false for function if in local '
                'nil not or repeat return then true until while'.split())


def lua_val(v):
    if isinstance(v, int):
        return str(v)
    if isinstance(v, list):
        return '{ ' + ', '.join(lua_val(x) for x in v) + ' }'
    if isinstance(v, dict):
        return '{ ' + ', '.join(f'{lua_key(k)} = {lua_val(x)}' for k, x in v.items()) + ' }'
    return lua_str(v)


def num(s):
    return int(s) if re.fullmatch(r'-?\d+', s or '') else None


def cmds(s):
    return [c.strip() for c in s.split(';') if c.strip()]


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


def write(path, head, body):
    with open(path, 'w', encoding='utf-8') as f:
        f.write(head.rstrip() + '\n' + body)
    print('wrote', path)


# --- the three files ---------------------------------------------------------

def portals(src, out):
    text = read(os.path.join(src, 'conf/portals.tin'))
    equip = read(os.path.join(src, 'conf/equipment.tin'))
    lines = ['return {',
             f'  home_vnum = {num(variable(text, "home_vnum"))},',
             f'  bag = {lua_str(variable(equip, "portalbag"))},',
             f'  default_portal = {lua_str(variable(text, "defaultportal"))},',
             f'  home_cmds = {lua_val(cmds(variable(text, "g_home_cmds")))},',
             '',
             '  -- name = { obj = item id or keyword, lvl = tier level, vnum = where it lands }',
             '  -- An entry with no vnum is never used in routes, only by "g <name>"',
             '  portals = {']
    for name, p in table(variable(text, 'myportals')).items():
        e = {'obj': p.get('obj', ''), 'lvl': num(p.get('lvl')) or 0}
        if num(p.get('vnum')) is not None:
            e['vnum'] = num(p['vnum'])
        lines.append(f'    {lua_key(name)} = {lua_val(e)},')
    lines += ['  },', '',
              '  -- "g <start of key>" runs these commands, before portals are tried',
              '  shortcuts = {']
    for k, v in table(variable(text, 'g_shortcuts')).items():
        lines.append(f'    {lua_key(k)} = {lua_val(cmds(v))},')
    lines += ['  },', '',
              '  -- "g <start of key>" is refused, with the reason shown',
              '  blacklist = {']
    for k, v in table(variable(text, 'g_blacklist')).items():
        lines.append(f'    {lua_key(k)} = {lua_val(v)},')
    lines += ['  },', '}', '']
    write(os.path.join(out, 'portals.lua'),
          '-- Portals and "g" shortcuts. Hand-edited; converted once from tt++ conf/portals.tin.',
          '\n'.join(lines))


def areas(src, out):
    text = read(os.path.join(src, 'conf/areas.tin'))
    info = table(variable(text, 'area_info'))
    rows = {}
    for name, a in info.items():
        zone = a.get('zone') or a.get('kw')
        if not zone:
            print('  area with no keyword skipped:', name)
            continue
        if zone in rows:
            print('  zone listed twice, second kept:', zone, '/', name)
        name = re.sub(r' \([^)]*\)$', '', name) if name.endswith(f'({a.get("kw")})') else name
        e = {'name': name}
        if a.get('kw') and a['kw'] != zone:
            e['kw'] = a['kw']
        for f in ('from', 'to', 'lock'):
            if num(a.get(f)) is not None:
                e[f] = num(a[f])
        rows[zone] = e
    lines = ['return {']
    for zone in sorted(rows):
        lines.append(f'  {lua_key(zone)} = {lua_val(rows[zone])},')
    lines += ['}', '']
    write(os.path.join(out, 'areas.lua'),
          '-- Areas by GMCP zone slug (what the map stores). kw only where "g" takes a\n'
          '-- different keyword. from/to = level range, lock = entry level.\n'
          '-- Converted once from tt++ conf/areas.tin ("areas keywords" output).',
          '\n'.join(lines))
    return len(rows)


def labels(src, out):
    text = read(os.path.join(src, 'conf/rooms.tin'))
    lab = table(variable(text, 'room_labels'))
    lines = ['return {']
    for name in sorted(lab):
        vnums = sorted(num(v) for v in lab[name] if num(v) is not None)
        lines.append(f'  {lua_key(name)} = {lua_val(vnums)},')
    lines += ['}', '']
    write(os.path.join(out, 'labels.lua'),
          '-- Room labels for hf / find: label -> vnums. Rewritten by label / unlabel.\n'
          '-- Converted once from tt++ conf/rooms.tin.',
          '\n'.join(lines))
    return len(lab)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    portals(src, out)
    print(areas(src, out), 'areas')
    print(labels(src, out), 'labels')


if __name__ == '__main__':
    main()
