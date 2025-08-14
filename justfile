################################################################################
# This justfile is designed to be placed one directory above the bitcoin core source tree
# e.g.
#
# src/core/
# ├── bitcoin
# │   ├── build
# │   ├── ci
# │   ├── cmake
# │   ├── CMakeLists.txt
# │   ├── CMakePresets.json
# │   ├── contrib
# │   ├── CONTRIBUTING.md
# │   ├── COPYING
# │   ├── depends
# │   ├── doc
# │   ├── INSTALL.md
# │   ├── libbitcoinkernel.pc.in
# │   ├── README.md
# │   ├── SECURITY.md
# │   ├── share
# │   ├── src
# │   ├── test
# │   └── vcpkg.json
# └── justfile
#
# This helps to keep a clean source directory.
#
# If you prefer to use this file from within the bitcoin source directory
# remove the below instruction:
#
# `set working-directory := "bitcoin"`
#
# See https://github.com/casey/just?tab=readme-ov-file#working-directory for
# more information on `working-directory`.
#
################################################################################

set dotenv-load := true
set quiet
set shell := ["bash", "-euc"]
set unstable := true # Needed for `&&` in ramdisk-params
set working-directory := "bitcoin"

os := os()

host-triplet := shell('./depends/config.guess')

ramdisk-path := if os == "linux" { "/mnt/tmp" } else if os == "macos" { "/Volumes/ramdisk" } else { "" }
ramdisk-size := "8"
ramdisk-params := if ramdisk-path != "" && path_exists(ramdisk-path) { "--cachedir=" + ramdisk-path + "/cache --tmpdir=" + ramdisk-path } else { "" }

alias b := build
alias bd := build-depends
alias c := clean
alias conf := configure
alias m := make
alias p := prepare
alias t := test

[private]
default:
    just --list

# Configure default project
[group('build')]
configure *args:
    cmake -B build {{ args }}

# Make default project
[group('build')]
make *args:
    cmake --build build -j {{ num_cpus() }}

# Configure and make default project
[group('build')]
build *args: (configure args)
    cmake --build build -j {{ num_cpus() }}

# Configure and make with all optional modules
[group('build')]
build-dev *args: (configure "--preset dev-mode" "-DBUILD_GUI=NO" args)
    cmake --build build -j {{ num_cpus() }}

# Build using depends
[group('build')]
[no-quiet]
build-depends triplet=host-triplet:
    echo depends build running
    make -C depends -j{{ num_cpus() }} CC="clang" CXX="clang++"
    echo depends build complete
    just build --toolchain $(pwd)/depends/{{triplet}}/toolchain.cmake

[private]
[group('build')]
include-what-you-use: clean
    # This is pretty broken still
    CC="clang" CXX="clang++" cmake -B build -DCMAKE_CXX_INCLUDE_WHAT_YOU_USE=include-what-you-use -DCMAKE_GENERATOR="Unix Makefiles"
    cmake --build build -j {{ num_cpus() }} 2> /tmp/iwyu.out
    fix_includes.py -b --nosafe_headers --nocomments < /tmp/iwyu.out

# Show all cmake variables
[group('build')]
cmake-vars:
    cmake -LAH build | less

# Clean build dir and logs
[group('build')]
clean:
    make -C depends clean
    rm -Rf build

# Make a ramdisk at default path found in test/README.md (size in GB)
[no-quiet]
[private]
[linux]
make-ramdisk size=ramdisk-size:
    if ! mountpoint -q {{ramdisk-path}}; then \
        echo "Making a ramdisk at {{ramdisk-path}} with size {{size}}GB (requires sudo)"; \
        sudo mkdir -p {{ramdisk-path}}; \
        sudo mount -t tmpfs -o size={{size}}g tmpfs {{ramdisk-path}}; \
        sudo chown -R $USER:$(id -gn) {{ramdisk-path}}; \
        sudo chmod 755 {{ramdisk-path}}; \
        echo "Ramdisk mounted at {{ramdisk-path}} with size {{size}}GB"; \
    fi

# Unmount and remove the ramdisk
[private]
[linux]
unmount-ramdisk:
    mountpoint -q {{ramdisk-path}}
    test $? -eq 0 && sudo umount {{ramdisk-path}}
    test $? -eq 0 && echo "Ramdisk unmounted from {{ramdisk-path}}" || echo "No ramdisk mounted at {{ramdisk-path}}"

# Run unit tests
[group('test')]
testu *args:
    ctest --test-dir build -j {{ num_cpus() }} {{args}}

# Run a single unit test suite
[group('test')]
test-suite suite:
    build/src/test/test_bitcoin --log_level=all --run_test={{suite}}

# Run functional test(s)
[group('test')]
testf *args: make-ramdisk
    build/test/functional/test_runner.py -j {{ num_cpus() }} {{ramdisk-params}} {{args}}

# Run all unit and functional tests
[group('test')]
test: make-ramdisk testu testf

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
    git diff -U0 HEAD~1.. | ( cd ./src/ && clang-tidy-diff-17.py -p2 -j {{ num_cpus() }} )

# Run clang-tidy on the diff (must be configured with clang)
[no-exit-message]
[private]
tidy-diff:
    git diff | ( cd ./src/ && clang-tidy-diff-17.py -p2 -j $(nproc) )

# Run the linters
[group('lint')]
lint:
    docker buildx build -t bitcoin-linter --file "./ci/lint_imagefile" ./ && docker run --rm -v $(pwd):/bitcoin -it bitcoin-linter

# Run all linters, clang-format and clang-tidy on top commit
[group('lint')]
lint-commit: lint && format-commit tidy-commit

# Run all linters, clang-format and clang-tidy on diff
[group('lint')]
lint-diff: lint && format-diff tidy-diff

# Run a CI stage locally
[group('ci')]
run-ci file-env:
    env -i HOME="$HOME" PATH="$PATH" USER="$USER" BASE_CACHE="$BASE_CACHE" SOURCES_PATH="$SOURCES_PATH" SDK_PATH="$SDK_PATH" MAKEJOBS="-j$(nproc)" bash -c 'FILE_ENV="{{ file-env }}" ./ci/test_run_all.sh'

# Lint (top commit), build and test
[group('pr tools')]
check: lint-commit build testf

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
    git rebase -i `git merge-base HEAD upstream/master` --exec "just lint" \

# Check each commit in the branch passes `just check`
[confirm("Warning, unsaved changes may be lost. Continue?")]
[no-exit-message]
[group('pr tools')]
prepare:
    git rebase -i `git merge-base HEAD upstream/master` --exec "just check" \

# Git range-diff from <old-rev> to HEAD~ against master
[no-exit-message]
[group('git')]
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
    build/src/bench/bench_bitcoin

# Verify scripted diffs from master to HEAD~
[group('tools')]
verify-scripted-diff:
    test/lint/commit-script-check.sh origin/master..HEAD

# Install python deps from ci/lint/install.sh using uv
[group('tools')]
install-python-deps:
    awk '/^\$\{CI_RETRY_EXE\} pip3 install \\/,/^$/{if (!/^\$\{CI_RETRY_EXE\} pip3 install \\/ && !/^$/) print}' ci/lint/04_install.sh \
        | sed 's/\\$//g' \
        | xargs uv pip install
    uv pip install vulture # currently unversioned in our repo
    uv pip install requests # only used in getcoins.py

# Attest to guix build outputs
[group('guix')]
guix-attest:
    contrib/guix/guix-attest

# Perform a guix build with default options
[group('guix')]
guix-build:
    contrib/guix/guix-build

# Clean intermediate guix build work directories
[group('guix')]
guix-clean:
    contrib/guix/guix-clean

# Codesign build outputs
[group('guix')]
guix-codesign:
    contrib/guix/guix-codesign

# Verify build output attestations
[group('guix')]
guix-verify:
    contrib/guix/guix-verify
