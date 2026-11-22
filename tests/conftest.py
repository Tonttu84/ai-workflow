"""Shared fixtures for the pytest tests of scripts/decisions.py.

The tests build small git repositories in temporary directories. Every
GIT_* variable of the outer environment is removed first, so a hook or
tool that started the tests cannot point git at another repository, and
git reads no global or system config.
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "decisions.py"
TIMEOUT = 60


def _load_tool():
    spec = importlib.util.spec_from_file_location("decisions", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    # dataclasses look their module up while the module loads
    sys.modules["decisions"] = module
    spec.loader.exec_module(module)
    return module


@pytest.fixture(scope="session")
def tool():
    """The decisions.py module, loaded from its path."""
    return _load_tool()


def clean_env(home: Path) -> dict[str, str]:
    """os.environ without GIT_*, with an empty global config at home."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    config = home / "gitconfig"
    config.touch()
    env["GIT_CONFIG_GLOBAL"] = str(config)
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    env["GIT_CEILING_DIRECTORIES"] = str(home.parent)
    return env


@pytest.fixture(autouse=True)
def isolated_git(tmp_path, monkeypatch):
    """Runs every test with clean_env as its environment."""
    home = tmp_path / "home"
    home.mkdir()
    env = clean_env(home)
    for key in list(os.environ):
        if key not in env:
            monkeypatch.delenv(key)
    for key, value in env.items():
        monkeypatch.setenv(key, value)
    return env


class Repo:
    """A scratch git repository with its own identity."""

    def __init__(self, path: Path):
        self.path = path
        path.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "core.autocrlf", "false")

    def git(self, *args: str) -> str:
        done = subprocess.run(
            ["git", *args], cwd=self.path, capture_output=True,
            timeout=TIMEOUT, check=True,
        )
        return done.stdout.decode("utf-8").strip()

    def write(self, text: str, name: str = "docs/decisions.md") -> None:
        target = self.path / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(text.encode("utf-8"))

    def commit(self, text: str, name: str = "docs/decisions.md") -> str:
        """Writes the file, commits it and returns the commit's SHA."""
        self.write(text, name)
        self.git("add", "-A")
        self.git("commit", "-q", "--allow-empty", "-m", "change")
        return self.git("rev-parse", "HEAD")


@pytest.fixture
def repo(tmp_path):
    return Repo(tmp_path / "repo")


@pytest.fixture
def run(tool, capsys, monkeypatch):
    """run(cwd, *args) calls main in cwd: (status, stdout, stderr)."""

    def call(cwd: Path, *args: str):
        monkeypatch.chdir(cwd)
        try:
            status = tool.main(list(args))
        except SystemExit as stop:
            status = stop.code
        out, err = capsys.readouterr()
        return status, out, err

    return call


def run_script(cwd: Path, *args: str) -> subprocess.CompletedProcess:
    """Runs decisions.py as a program; output is kept as bytes."""
    return subprocess.run(
        [sys.executable, str(SCRIPT), *args], cwd=cwd,
        capture_output=True, timeout=TIMEOUT,
    )


HEADER = (
    "| ID | Decision | Reason | Chosen against | Meta |\n"
    "| --- | --- | --- | --- | --- |\n"
)


def row(rid: str, decision: str = "A decision", reason: str = "why",
        meta: str = "2026-11-16 · agent · none · two-way") -> str:
    return f"| {rid} | {decision} | {reason} | none | {meta} |\n"


def log(*rows: str) -> str:
    return "# Decisions\n\nOne row per decision.\n\n" + HEADER + "".join(rows)
