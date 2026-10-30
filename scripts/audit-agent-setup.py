#!/usr/bin/env python3
"""Inventory agent setup without emitting credentials or remote URLs."""

import argparse
import hashlib
import json
import tomllib
from collections import Counter
from pathlib import Path


def load(path):
    if not path.exists():
        return {}
    content = path.read_text()
    return tomllib.loads(content) if path.suffix == ".toml" else json.loads(content)


def inventory(home):
    configs = {}
    for relative in [
        ".codex/config.toml", ".codex/mcp.json", ".claude/settings.json",
        ".claude.json", ".config/opencode/opencode.json", ".pi/agent/settings.json",
    ]:
        path = home / relative
        data = load(path)
        if not data:
            continue
        entry = {"sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
        for key in ["model", "model_reasoning_effort", "model_context_window",
                    "model_auto_compact_token_limit", "approval_policy", "sandbox_mode"]:
            if key in data:
                entry[key] = data[key]
        for key in ["plugins", "enabledPlugins"]:
            if isinstance(data.get(key), dict):
                entry[key] = {
                    name: value.get("enabled", True) if isinstance(value, dict) else value
                    for name, value in data[key].items()
                }
        if "skillOverrides" in data:
            entry["skill_visibility"] = data["skillOverrides"]
        if relative == ".pi/agent/settings.json":
            entry["defaults"] = {
                key: data[key] for key in ["defaultProvider", "defaultModel", "defaultThinkingLevel"]
                if key in data
            }
        if isinstance(data.get("instructions"), list):
            entry["relay_instruction_pointers"] = sum("relay" in item.lower() for item in data["instructions"])
        for key in ["mcp_servers", "mcpServers", "mcp"]:
            if key in data:
                entry["mcp"] = {
                    name: {
                        "enabled": server.get("enabled", not server.get("disabled", False)),
                        "transport": server.get("type", "remote" if "url" in server else "stdio"),
                        "has_env": bool(server.get("env")),
                    }
                    for name, server in data[key].items() if isinstance(server, dict)
                }
        if "hooks" in data:
            entry["hooks"] = {
                event: {"groups": len(groups), "relay_hooks": sum(
                    "relay" in hook.get("command", "").lower()
                    for group in groups for hook in group.get("hooks", [])
                )}
                for event, groups in data["hooks"].items()
            }
        entry["skill_overrides"] = [
            {"skill": Path(item["path"]).name, "enabled": item.get("enabled", True)}
            for item in data.get("skills", {}).get("config", [])
        ] if isinstance(data.get("skills"), dict) else []
        if isinstance(data.get("permission"), dict):
            entry["skill_permissions"] = data["permission"].get("skill", {})
        configs[relative] = entry

    lock = load(home / ".agents/.skill-lock.json").get("skills", {})
    skills = {}
    for relative in [".agents/skills", ".codex/skills", ".claude/skills",
                     ".config/opencode/skills", ".pi/agent/skills"]:
        root = home / relative
        rows = []
        if root.exists():
            for folder in sorted(root.iterdir()):
                if folder.name.startswith("."):
                    continue
                skill = folder / "SKILL.md"
                source = lock.get(folder.name, {}).get("source")
                rows.append({
                    "name": folder.name, "symlink": folder.is_symlink(),
                    "broken_link": folder.is_symlink() and not folder.exists(),
                    "has_skill": skill.is_file(), "source": source,
                    "sha256": hashlib.sha256(skill.read_bytes()).hexdigest() if skill.is_file() else None,
                })
        skills[relative] = rows
    return {
        "configs": configs, "skills": skills,
        "source_counts": dict(Counter(value.get("source", "unknown") for value in lock.values())),
        "limits": "Configured state only. Does not prove connection, authentication, usage or new-session loading.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = inventory(args.home)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, indent=2) + "\n")
    else:
        print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
