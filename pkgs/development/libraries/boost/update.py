#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Regenerate versions/<version>.json for a Boost release.

    ./update.py 1.90.0

With no argument, refreshes the newest version already in versions/.

Nothing in those files is hand-maintained; it all comes from upstream:

  * which libraries exist, and which repository each lives in, come from the
    superproject's .gitmodules;
  * the CMake target name, its dependencies, and whether the library installs
    itself come from parsing the library's own CMakeLists.txt;
  * the source hashes come from prefetch.nix (see `hashes` for why not
    nix-prefetch-github).
"""

import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

HERE = Path(__file__).parent
VERSIONS = HERE / "versions"

# `project( boost_filesystem ... )` -- the library's own name for itself, and
# the authoritative one: a library may declare several targets (Boost.Asio has
# asio_core, asio_deadline_timer, asio_spawn and asio), and only the project
# name says which of them the library *is*.
PROJECT_RE = re.compile(r"^project\(\s*boost_([a-z0-9_]+)", re.MULTILINE)
# `add_library( Boost::filesystem ALIAS ... )` -- every target the library
# defines, and so every CMake package it installs. Boost.Asio, for instance,
# installs boost_asio, boost_asio_core, boost_asio_deadline_timer and
# boost_asio_spawn, and Boost.Log depends on boost_asio_core specifically.
ALIAS_RE = re.compile(r"add_library\(\s*Boost::([a-z0-9_]+)\s+ALIAS")
# Any target the library refers to, which is how it names its dependencies.
TARGET_RE = re.compile(r"Boost::([a-z0-9_]+)")
# `add_library( boost_filesystem ... )` and everything up to the closing paren.
# A library all of whose targets are INTERFACE or ALIAS builds nothing, and so
# wants a single output rather than an empty `out` beside a `dev` holding
# everything.
#
# The whole call has to be captured, not just the token after the target name:
# sources are often given as a variable, as in
# `add_library(boost_filesystem ${BOOST_FILESYSTEM_SOURCES})`, and a pattern
# that only matched a bare word would fail to match those calls at all -- which
# silently makes every such library look header-only.
ADD_LIBRARY_RE = re.compile(r"add_library\(\s*boost_[a-z0-9_]+([^)]*)\)", re.DOTALL)
INTERFACE_OR_ALIAS_RE = re.compile(r"\b(INTERFACE|ALIAS)\b")
# `if(BOOST_SUPERPROJECT_VERSION ...)` -- the branch a library takes when it is
# part of a superproject, which is what library.nix's wrapper makes it.
SUPERPROJECT_GUARD_RE = re.compile(r"if\s*\(\s*BOOST_SUPERPROJECT_VERSION")

SUBMODULE_RE = re.compile(
    r"path\s*=\s*(?P<path>\S+)\s+url\s*=\s*(?:\.\./)?(?P<repo>\S+?)(?:\.git)?\s", re.MULTILINE
)


def log(message: str) -> None:
    print(message, file=sys.stderr)


def raw(repo: str, path: str, tag: str) -> str | None:
    """A file from a boostorg repository at the release tag."""
    url = f"https://raw.githubusercontent.com/boostorg/{repo}/{tag}/{path}"
    try:
        with urllib.request.urlopen(url) as response:
            return response.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise


def submodules(tag: str) -> dict[str, str]:
    """Library submodule path -> repository name, from the superproject."""
    gitmodules = raw("boost", ".gitmodules", tag)
    if gitmodules is None:
        raise SystemExit(f"boostorg/boost has no .gitmodules at {tag}")
    return {
        m["path"]: m["repo"]
        for m in SUBMODULE_RE.finditer(gitmodules)
        if m["path"].startswith("libs/")
    }


def describe(repo: str, tag: str) -> tuple[str, dict] | None:
    """Everything we need about one library, read out of its CMakeLists.txt."""
    cmakelists = raw(repo, "CMakeLists.txt", tag)
    if cmakelists is None:
        log(f"  ! {repo} has no CMakeLists.txt, skipping")
        return None

    project = PROJECT_RE.search(cmakelists)
    aliases = ALIAS_RE.findall(cmakelists)
    name = project.group(1) if project else aliases[0] if aliases else None
    if name is None:
        log(f"  ! {repo} declares no Boost:: target, skipping")
        return None

    provides = sorted({name, *aliases})
    deps = sorted(set(TARGET_RE.findall(cmakelists)) - set(provides))

    # A few libraries -- generally the ones building several libraries at once,
    # where no single target is named after the library -- install themselves
    # once they believe they are part of a superproject, and the wrapper in
    # library.nix must not install those a second time.
    #
    # The guard is what matters, not the call: several libraries also call
    # boost_install from a branch taken only when they are the top-level
    # project, which they never are here.
    self_installs = bool(SUPERPROJECT_GUARD_RE.search(cmakelists)) and "boost_install" in cmakelists

    # Anything that is not INTERFACE or ALIAS -- SHARED, STATIC, or a list of
    # sources however it is spelled -- means something gets compiled.
    #
    # A declaration with no arguments at all, `add_library(boost_any)`, is the
    # C++20 modules form: it names a target whose sources arrive later via
    # target_sources, and it only ever appears inside `if(BOOST_USE_MODULES)`,
    # which this build does not set. Counting it would call Boost.Any compiled
    # on the strength of a branch that is never taken.
    declarations = ADD_LIBRARY_RE.findall(cmakelists)
    header_only = bool(declarations) and all(
        not declaration.strip() or INTERFACE_OR_ALIAS_RE.search(declaration)
        for declaration in declarations
    )

    return name, {
        "repo": repo,
        "provides": provides,
        "deps": deps,
        "selfInstalls": self_installs,
        "headerOnly": header_only,
    }


GOT_HASH_RE = re.compile(r"got:\s+(sha256-\S+)")
SOURCE_RE = re.compile(r"boost-([a-z0-9_]+)-source")


def hashes(repos: list[str], tag: str) -> dict[str, str]:
    """Source hashes for every repository, from prefetch.nix.

    Deliberately not nix-prefetch-github, which is what a multi-source updater
    would normally reach for. It makes one GitHub API call per repository, and
    Boost is ~157 repositories per release: a single run goes through the
    60/hour unauthenticated rate limit twice over, and refreshing every release
    Nixpkgs carries is nearer 1900 calls. Needing a GITHUB_TOKEN to regenerate
    a data file is a worse trade than the alternative.

    So prefetch.nix asks Nix to fetch the tarballs with a deliberately wrong
    hash, and we read the real ones out of the failures. That needs no API at
    all, and it has one property nix-prefetch-github does not: the hash is
    exact by construction, because it comes from the very `fetchFromGitHub`
    call the build will later make rather than from a reimplementation of it.
    """
    process = subprocess.run(
        [
            "nix-build",
            "--no-out-link",
            "--keep-going",
            str(HERE / "prefetch.nix"),
            "--argstr", "tag", tag,
            "--argstr", "repos", json.dumps(sorted(set(repos))),
        ],
        capture_output=True,
        text=True,
    )

    found: dict[str, str] = {}
    repo = None
    for line in process.stderr.splitlines():
        source = SOURCE_RE.search(line)
        if source:
            repo = source.group(1)
        got = GOT_HASH_RE.search(line)
        if got and repo is not None:
            found[repo] = got.group(1)

    missing = sorted(set(repos) - set(found))
    if missing:
        raise SystemExit(f"no hash for: {', '.join(missing)}")
    return found


def main() -> None:
    if len(sys.argv) > 2:
        raise SystemExit(f"usage: {sys.argv[0]} [version]")
    if len(sys.argv) == 2:
        version = sys.argv[1]
    else:
        existing = sorted(VERSIONS.glob("*.json"))
        if not existing:
            raise SystemExit(f"usage: {sys.argv[0]} <version>")
        version = existing[-1].stem
    tag = f"boost-{version}"
    output = VERSIONS / f"{version}.json"

    log(f"boost {version}: reading submodules")
    repos = submodules(tag)

    log(f"boost {version}: reading {len(repos)} CMakeLists.txt")
    with ThreadPoolExecutor(max_workers=16) as pool:
        described = pool.map(lambda repo: describe(repo, tag), sorted(repos.values()))
    libraries = dict(entry for entry in described if entry is not None)

    # Which library installs which CMake package. Mostly one apiece, but the
    # multi-target libraries install several, and a dependency may name any of
    # them (Boost.Log wants boost_asio_core, which comes from Boost.Asio).
    provider = {
        target: name for name, library in libraries.items() for target in library["provides"]
    }

    # Drop targets that no library installs -- placeholders such as
    # Boost::library, and targets defined only inside a test or example.
    for library in libraries.values():
        library["deps"] = [d for d in library["deps"] if d in provider]

    log(f"boost {version}: fetching {len(libraries) + 1} repositories")
    wanted = [library["repo"] for library in libraries.values()] + ["cmake", "boost_install"]
    found = hashes(wanted, tag)

    for library in libraries.values():
        library["hash"] = found[library["repo"]]

    VERSIONS.mkdir(exist_ok=True)
    output.write_text(
        json.dumps(
            {
                "version": version,
                "cmakeHash": found["cmake"],
                "installHash": found["boost_install"],
                "libraries": {
                    name: {
                        "repo": library["repo"],
                        "hash": library["hash"],
                        "provides": library["provides"],
                        "deps": library["deps"],
                        "selfInstalls": library["selfInstalls"],
                        "headerOnly": library["headerOnly"],
                    }
                    for name, library in sorted(libraries.items())
                },
            },
            indent=2,
        )
        + "\n"
    )
    log(f"boost {version}: {len(libraries)} libraries")


if __name__ == "__main__":
    main()
