set dotenv-load := true
set shell := ["bash", "-uc"]
set working-directory := "bitcoin"

os := os()
n := num_cpus()

alias rb := rebuild
alias c := check
alias b := build
alias bd := build-dev
alias p := prepare

######################
###### recipes #######
######################

[private]
default:
    just --list

# Build default project
[group('build')]
build *args: clean
    cmake -B build {{ args }}
    cmake --build build -j {{ n }}

# Build with all optional modules
[group('build')]
build-dev *args: clean
    cmake -B build --preset dev-mode {{ args }}
    cmake --build build -j {{ n }}

# Re-build current config
[group('build')]
rebuild:
    cmake --build build -j {{ n }}


# Clean build dir
[group('build')]
clean:
    rm -Rf build

# Run unit tests
[group('test')]
test-unit:
    ctest --test-dir build -j {{ n }}

# Run all functional tests
[group('test')]
test-func:
    build/test/functional/test_runner.py -j {{ n }}

# Run all unit and functional tests
[group('test')]
test: test-unit test-func

# Run a single functional test (filename.py)
[group('test')]
test-func1 test:
    build/test/functional/test_runner.py {{ test }}

# Run a single unit test suite
[group('test')]
test-unit1 suite:
    build/src/test/test_bitcoin --log_level=all --run_test={{ suite }}

# Run clang-format-diff on top commit
[no-exit-message]
[private]
format-commit:
    git diff -U0 HEAD~1.. | ./contrib/devtools/clang-format-diff.py -p1 -i -v

# Run clang-format on the diff (must be configured with clang)
[no-exit-message]
[private]
format-diff:
    git diff | ./contrib/devtools/clang-format-diff.py -p1 -i -v

# Run clang-tidy on top commit
[no-exit-message]
[private]
tidy-commit:
    git diff -U0 HEAD~1.. | ( cd ./src/ && clang-tidy-diff-17.py -p2 -j {{ n }} )

# Run clang-tidy on the diff (must be configured with clang)
[no-exit-message]
[private]
tidy-diff:
    git diff | ( cd ./src/ && clang-tidy-diff-17.py -p2 -j {{ n }} )

# Run the linter
[group('lint')]
lint:
    DOCKER_BUILDKIT=1 docker build -t bitcoin-linter --file "./ci/lint_imagefile" ./ && docker run --rm -v $(pwd):/bitcoin -it bitcoin-linter

# Run all linters, clang-format and clang-tidy on top commit
[group('lint')]
lint-commit: lint
    just format-commit
    just tidy-commit

# Run all linters, clang-format and clang-tidy on diff
[group('lint')]
lint-diff: lint
    just format-diff
    just tidy-diff

# Lint (top commit), build and test
[group('pr tools')]
check: lint-commit build test-func

# Interactive rebase current branch from (git merge-base) (`just rebase -i` for interactive)
[confirm("Warning, unsaved changes may be lost. Continue?")]
[no-exit-message]
[group('git')]
rebase *args:
    git rebase {{ args }} `git merge-base HEAD upstream/master`

# Update upstream/master and interactive rebase on it (`just rebase-upstream -i` for interactive)
[confirm("Warning, unsaved changes may be lost. Continue?")]
[group('git')]
rebase-upstream *args:
    git fetch upstream
    git rebase {{ args }} `git merge-base HEAD upstream/master`

# Check each commit in the branch passes `just lint`
[confirm("Warning, unsaved changes may be lost. Continue?")]
[no-exit-message]
[private]
rebase-lint:
    git rebase -i `git merge-base HEAD upstream/master` \
    --exec "just lint" \

# Check each commit in the branch passes `just check`
[confirm("Warning, unsaved changes may be lost. Continue?")]
[no-exit-message]
[group('pr tools')]
prepare:
    git rebase -i `git merge-base HEAD upstream/master` \
    --exec "just check" \

# Git range-diff from <old-rev> to HEAD~ against master
[no-exit-message]
[group('tools')]
range-diff old-rev:
    git range-diff master {{ old-rev }} HEAD~

# Profile a running bitcoind for 60 seconds (e.g. just profile `pgrep bitcoind`). Outputs perf.data
[no-exit-message]
[group('perf')]
profile pid:
    perf record -g --call-graph dwarf --per-thread -F 140 -p {{ pid }} -- sleep 60

# Run benchmarks
[group('perf')]
bench:
    src/bench/bench_bitcoin

# Verify scripted diffs from master to HEAD~
[group('tools')]
verify-scripted-diff:
    test/lint/commit-script-check.sh origin/master..HEAD

# Install python deps from ci/lint/install.sh
[group('tools')]
install-python-deps:
    awk '/^\$\{CI_RETRY_EXE\} pip3 install \\/,/^$/{if (!/^\$\{CI_RETRY_EXE\} pip3 install \\/ && !/^$/) print}' ci/lint/04_install.sh \
        | sed 's/\\$//g' \
        | xargs pip3 install
    pip3 install vulture # currently unversioned in our repo
    pip3 install requests # only used in getcoins.py

deps_command := if os == "linux" { "xdg-open https://github.com/bitcoin/bitcoin/blob/master/doc/build-unix.md" } else { if os == "macos" { "open https://github.com/bitcoin/bitcoin/blob/master/doc/build-osx.md" } else { if os == "windows" { "explorer https://github.com/bitcoin/bitcoin/blob/master/doc/build-windows.md" } else { if os == "freebsd" { "xdg-open https://github.com/bitcoin/bitcoin/blob/master/doc/build-freebsd.md" } else { "echo see https://github.com/bitcoin/bitcoin/tree/master/doc#building for build instructions" } } } }

# Show project dependencies in browser
[group('tools')]
show-deps:
    {{ deps_command }}

# Build depends
[group('build')]
build-depends:
    #!/usr/bin/env bash

    # Run make and capture its output while displaying it
    cd depends && make -j {{ n }} 2>&1 | tee /tmp/make_output.txt

    # Extract the line that starts with 'to: ' and ends with your host triplet
    build_path=$(grep -E '^to: .*/depends/[^/]+$' /tmp/make_output.txt | awk '{print $2}')

    # Check if build_path was found
    if [ -z "$build_path" ]; then
        echo "Error: Build may have completed successfully but host-triplet could not be automatically detected."
        exit 1
    fi

    # Extract the relative path starting from 'depends/'
    HOST_TRIPLET_PATH="depends/${build_path##*/depends/}"

    echo
    echo "To use depends, run cmake using the toolchain of the host triplet."
    echo "This was auto-detected on this run as:"
    echo
    echo "cmake -B build --toolchain $HOST_TRIPLET_PATH/toolchain.cmake"
