# Bitcoin dev tooling

## Justfile

[`just`](https://github.com/casey/just) is a command runner, like make.

To setup the justfile, symlink or copy it into the bitcoin core source code's parent directory, e.g.:

```bash
# With bitcoin core in this directory:
# /home/user/src/core/bitcoin
# and this repo at:
# /home/user/srcbitcoin-dev-tools/dotfiles

ln -s /home/user/src/bitcoin-dev-tools/dotfiles/justfile /home/user/src/core
```

The *justfile* contains the `working-dir` directive so that it will execute recipes in the bitcoin core source directory.

```justfile
set working-directory := "bitcoin"
```

This setup permits running `git clean -dfx` style cleans.

If you prefer you can symlink the justfile directly into the source directory and remove the `working-directory` option.

You may then like to add the justfile to the ignored git files:

```bash
# ignore .justfile with git without using .gitignore
echo ".justfile" >> ~/src/bitcoin/.git/info/exclude
```

### Usage

List commands with `just` (or `just --list`).

Add your own commands or contribute them back upstream here.
See the [manual](https://just.systems/man/en/chapter_1.html) for syntax and features.

Make sure to install the [completions](https://just.systems/man/en/chapter_65.html) for your shell!

### Workflow

Typical usage for a user of this justfile might be:

1. Show main dependencies for your OS, installing them per the instructions:

    ```bash
    just show-deps
    ```

2. (optional) Install the python dependencies needed for linting:

    ```bash
    just install-python-deps
    ```

3. Compile the current branch with default configuration:

    ```bash
    just build
    ```

4. Check all tests are passing:

    ```bash
    just test
    ```

5. Run linters:

    ```bash
    just lint
    ```

6. Make some changes to the code...

7. Check all new commits in the branch are good, shortcut to run `just check` on each new commit in the branch vs master:

    ```bash
    just prepare
    ```

