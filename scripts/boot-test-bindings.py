#!/usr/bin/env python3
"""boot-test-bindings.py: check that every program a keybinding runs is on the session's PATH,
for rootfs-boot-test.sh's desktop checks.

Anatomy: the boot test starts this script through Hyprland (hyprctl dispatch with
hl.dsp.exec_cmd), so it runs in the environment a key press gives a binding's command. It reads
the lines boot-test-bindings.lua printed (keys, description, command) and, for each command,
finds the programs it runs: the first word, the first word after each ||, &&, ; or |, the
program after "uwsm-app --", and the same inside a quoted argument that is itself a command
line, one starting with "uwsm-app " or a path (omarchy-launch-or-focus 'thunderbird'
'uwsm-app -- /snap/bin/thunderbird'; a web app's name, 'Google Maps', is not one). Each
program must be an executable on PATH, or an executable file when it is a path. The report goes
to the output file:
  binding programs: <n> checked, <m> missing
  binding missing: <keys>: <program>      (one line per missing program)

Usage: boot-test-bindings.py <bindings.tsv> <report>
"""
import os
import re
import shlex
import shutil
import sys


def programs(words):
    found, start = [], True
    for i, w in enumerate(words):
        if w in ("||", "&&", ";", "|"):
            start = True
            continue
        if start:
            if re.match(r"^\w+=", w):
                continue
            found.append(w)
            start = False
        if w == "--" and i > 0 and words[i - 1] == "uwsm-app" and i + 1 < len(words):
            found.append(words[i + 1])
    return found


def main(bindings_path, report_path):
    checked, missing = 0, []
    for line in open(bindings_path, encoding="utf-8"):
        keys, _description, command = (line.rstrip("\n").split("\t") + ["", ""])[:3]
        if not command:
            continue
        try:
            words = shlex.split(command)
        except ValueError:
            missing.append(f"{keys}: cannot parse {command}")
            continue
        lines = [words]
        for w in words:
            if " " in w and w.startswith(("uwsm-app ", "/")):
                try:
                    lines.append(shlex.split(w))
                except ValueError:
                    pass
        for words_ in lines:
            for program in programs(words_):
                checked += 1
                if "/" in program:
                    ok = os.path.isfile(program) and os.access(program, os.X_OK)
                else:
                    ok = shutil.which(program) is not None
                if not ok:
                    missing.append(f"{keys}: {program}")
    with open(report_path, "w", encoding="utf-8") as out:
        out.write(f"binding programs: {checked} checked, {len(missing)} missing\n")
        for m in missing:
            out.write(f"binding missing: {m}\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
