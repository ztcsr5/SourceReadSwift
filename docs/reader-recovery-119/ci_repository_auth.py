"""Resolve the CI repository and read its credential without exposing or storing it.

Used by ci_status.py; GH_TOKEN/GITHUB_TOKEN override repository-scoped Git credentials.
"""
import base64
import os
from pathlib import Path
import re
import subprocess
from typing import Mapping
from urllib.parse import unquote, urlsplit


def resolve_repository_auth(root: Path, environment: Mapping[str, str] | None = None) -> tuple[str, str]:
    """Read the selected HTTPS GitHub remote and its authorization header in memory."""
    environment = dict(os.environ if environment is None else environment)
    remote_name = environment.get("READER_CI_REMOTE", "origin")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/-]{0,99}", remote_name):
        raise ValueError("Expected a Git remote name in READER_CI_REMOTE")
    try:
        selected = subprocess.run(["git", "remote", "get-url", remote_name], cwd=root,
                                  env=environment, text=True, encoding="utf8", capture_output=True,
                                  timeout=20, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise RuntimeError("Could not read the selected Git remote") from None
    if selected.returncode:
        raise RuntimeError("Could not read the selected Git remote")
    try:
        remote = urlsplit(selected.stdout.strip())
        repository = remote.path.strip("/").removesuffix(".git")
        is_github = remote.scheme == "https" and remote.hostname == "github.com" and remote.port in (None, 443)
    except ValueError:
        raise ValueError("Expected an HTTPS github.com repository remote") from None
    if not is_github or remote.query or remote.fragment or not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Expected an HTTPS github.com repository remote")
    for name in ["GH_TOKEN", "GITHUB_TOKEN"]:
        token = environment.get(name, "").strip()
        if token:
            return repository, _bearer_authorization(token)

    # Read-only compatibility for existing clones; new remotes never need a token in their URL.
    username = unquote(remote.username or "")
    password = unquote(remote.password or "")
    if password:
        encoded = base64.b64encode((username + ":" + password).encode("utf8")).decode("ascii")
        return repository, "Basic " + encoded
    if username:
        return repository, _bearer_authorization(username)

    credential_input = "protocol=https\nhost=github.com\npath=" + remote.path.strip("/") + "\n\n"
    environment.update(GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="Never")
    try:
        credential = subprocess.run(["git", "-c", "credential.useHttpPath=true", "credential", "fill"],
                                    input=credential_input, cwd=root, env=environment, text=True,
                                    encoding="utf8", capture_output=True, timeout=20, check=False)
    except (OSError, subprocess.TimeoutExpired):
        raise RuntimeError("Could not read a repository-scoped GitHub credential") from None
    fields = dict(line.split("=", 1) for line in credential.stdout.splitlines() if "=" in line)
    if credential.returncode or not fields.get("password"):
        raise RuntimeError("No GitHub credential for the selected repository; configure Git Credential Manager or GH_TOKEN")
    return repository, _bearer_authorization(fields["password"])


def _bearer_authorization(token: str) -> str:
    if "\r" in token or "\n" in token:
        raise ValueError("GitHub credential must not contain line breaks")
    return "Bearer " + token
