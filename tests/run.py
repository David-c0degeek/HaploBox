"""Run the HaploBox checks outside the game.

Usage: python tests/run.py
Needs Python 3 and lupa (pip install lupa), which embeds a real Lua 5.1, the
dialect WoW clients run. Two stages:
  1. Syntax: every Lua file in the TOC must compile under Lua 5.1, and every
     key binding in Bindings.xml must compile, call an existing function and
     have a name for the keybinding menu.
  2. Behaviour: each test in tests/test_*.lua runs in a fresh Lua state with the
     WoW API stubs from tests/stubs.lua and the addon loaded as the game loads it.
This checks logic only. Drawing, taint and real server behaviour need the game.
"""
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

from lupa import lua51

ROOT = pathlib.Path(__file__).resolve().parent.parent
TESTS = pathlib.Path(__file__).resolve().parent


def addon_files():
    lines = (ROOT / "HaploBox.toc").read_text(encoding="utf-8").splitlines()
    return [ROOT / ln.strip() for ln in lines if ln.strip().endswith(".lua")]


def load(lua, path, *args):
    loader = lua.eval("function(s, n) local f, e = loadstring(s, n) if not f then error(e, 0) end return f end")
    return loader(path.read_text(encoding="utf-8"), "@" + path.name)(*args)


def syntax():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    loader = lua.eval("function(s, n) local _, e = loadstring(s, n) return e end")
    bad = 0
    for path in addon_files():
        err = loader(path.read_text(encoding="utf-8"), "@" + path.name)
        print(("ok   " if err is None else "FAIL ") + path.name + ("" if err is None else ": " + err))
        bad += err is not None
    return bad + bindings()


def bindings():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    load(lua, TESTS / "stubs.lua")
    for path in addon_files():
        load(lua, path, "HaploBox")
    compile_error = lua.eval("function(s) local _, e = loadstring(s) return e end")
    exists = lua.eval("function(name) return type(HaploBox[name]) == 'function' end")
    defined = lua.eval("function(name) return type(_G[name]) == 'string' end")
    bad = 0
    for b in ET.parse(ROOT / "Bindings.xml").getroot().iter("Binding"):
        name, body = b.get("name"), (b.text or "").strip()
        problems = []
        if compile_error(body):
            problems.append("does not compile")
        for fn in re.findall(r"HaploBox\.(\w+)\(", body):
            if not exists(fn):
                problems.append("HaploBox." + fn + " missing")
        if not defined("BINDING_NAME_" + name):
            problems.append("no BINDING_NAME_" + name)
        print(("ok   " if not problems else "FAIL ") + "binding " + name + ("" if not problems else ": " + ", ".join(problems)))
        bad += bool(problems)
    return bad


def fresh(test_file):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    load(lua, TESTS / "stubs.lua")
    for path in addon_files():
        load(lua, path, "HaploBox")
    load(lua, TESTS / "helpers.lua")
    load(lua, test_file)
    return lua


def behaviour():
    failed = total = 0
    for test_file in sorted(TESTS.glob("test_*.lua")):
        names = list(fresh(test_file).eval("TEST_NAMES").values())
        for i, name in enumerate(names, 1):
            total += 1
            lua = fresh(test_file)
            err = lua.eval("function(i) local ok, e = pcall(TEST_FNS[i]) return not ok and tostring(e) or false end")(i)
            ok = err is False
            print(("ok   " if ok else "FAIL ") + test_file.stem + ": " + name + ("" if ok else "\n     " + str(err)))
            failed += not ok
    print("%d of %d behaviour tests passed" % (total - failed, total))
    return failed


if __name__ == "__main__":
    bad = syntax()
    if not bad:
        bad = behaviour()
    sys.exit(1 if bad else 0)
