"""PreToolUse-Hook des Agenten qa-reviewer: laesst nur lesende bzw. pruefende Befehle durch.

Bash: erlaubt sind nur die Befehle aus ALLOWED (optional mit Pipe in einen reinen Filter); Verkettung,
Umleitung, Kommandosubstitution und alles, was .env beruehrt, wird blockiert.
mcp__Roblox_Studio__execute_luau: nur im Spieltest (Client/Server), nie im Edit-Datamodel.
Exit 2 = blockiert (Begruendung auf stderr geht an den Agenten), Exit 0 = erlaubt.
Doku: https://code.claude.com/docs/en/hooks
"""

import json
import re
import sys

ALLOWED = [
    r"git (diff|show|log|status|blame|ls-files|rev-parse|cat-file|shortlog)\b(?!.*--output)(?!.*\s-o\s).*",
    r"git apply --check\b.*",
    r"python3? tools/core_boundary\.py\b.*",
    r"python3? tools/spike/check_secrets\.py\b.*",
    r'python3? -m unittest discover -s tools/spike -p "?test_\*\.py"?',
    r"stylua --check\b.*",
    r"selene\b.*",
    r"(ls|wc|pwd)\b.*",
]
FILTERS = r"(head|tail|grep|wc|sort|uniq)\b.*"
FORBIDDEN = re.compile(r"[;&><`]|\$\(|\.env\b")


def block(reason: str) -> int:
    print(f"qa_guard: blockiert - {reason}", file=sys.stderr)
    return 2


def check_bash(command: str) -> int:
    command = command.strip()
    command = re.sub(r'^cd\s+("[^"]*"|\S+)\s*&&\s*', "", command)
    if FORBIDDEN.search(command):
        return block("Verkettung, Umleitung, Substitution oder .env sind nicht erlaubt")
    first, *rest = [part.strip() for part in command.split("|")]
    if not any(re.fullmatch(pattern, first) for pattern in ALLOWED):
        return block(f"Befehl nicht freigegeben: {first}")
    for part in rest:
        if not re.fullmatch(FILTERS, part):
            return block(f"Pipe nur in head/tail/grep/wc/sort/uniq erlaubt: {part}")
    return 0


def main() -> int:
    data = json.load(sys.stdin)
    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input") or {}
    if tool == "Bash":
        return check_bash(str(tool_input.get("command", "")))
    if tool == "mcp__Roblox_Studio__execute_luau":
        if tool_input.get("datamodel_type") not in ("Client", "Server"):
            return block("execute_luau nur im laufenden Spieltest (Client oder Server), nie im Edit-Datamodel")
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
