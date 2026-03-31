<!--
SPDX-FileCopyrightText: 2024-2026 Alex Turbov <i.zaufi@gmail.com>

SPDX-License-Identifier: GPL-3.0-or-later
-->

# What is This

The repo provides a helper script (`add-copyright-header`) that simplifies adding or updating
copyright headers in large projects migrating to the [reuse tool].

The script looks for the configuration file at the top directory of the current Git repository.
The configuration file is a JSON file named `.reuse-hdrmap.json`. Outside of a Git repository,
the script falls back to `${XDG_CONFIG_HOME:-$HOME/.config}/reuse-hdrmap.json`, and then to
`/etc/reuse-hdrmap.json` if the user-level XDG config file does not exist. Use `-c FILE` to
override that lookup chain explicitly. The config consists of the following top-level keys, each
of which is an array of objects: `templates`, `licenses`, and `copyright_headers`. Also, there
could be a "global" `extra_reuse_cli_options` object.

[reuse tool]: https://reuse.software/

```console
$ add-copyright-header -h
Usage: add-copyright-header [-c FILE] [-d] [FILENAME]...

Add copyright header to files according to the matched patterns in the '.reuse-hdrmap.json'

Options:
    -c FILE use the given hdrmap config file
    -d      show command but don't execute it
```


## Templates object

Each object in the `templates` array has the following properties:

- `patterns` is an array of shell (possibly `extglob`) patterns to match input files. [^1]
- `extra_reuse_cli_options` provides extra options to the [`reuse annotate` command line].
   See below.

The first matching pattern stops further matching, and the specified extra options are added to
the final `reuse annotate` command line.

[`reuse annotate` command line]: https://reuse.readthedocs.io/en/stable/man/reuse-annotate.html


## Licenses object

Each object in the `licenses` array has the following properties:

- `patterns` is an array of shell (possibly `extglob`) patterns to match input files. [^1]
- `ref` is an [SPDX license expression] that will be applied to the matched input file.

[SPDX license expression]: https://spdx.github.io/spdx-spec/v3.0/annexes/SPDX-license-expressions/


## Copyright headers object

Each object in the `copyright_headers` array has the following properties:

- `patterns` is an array of shell (possibly `extglob`) patterns to match input files. [^1]
- `text` is a copyright text to apply for the matched input file.


[^1]: Patterns are matched against the path relative to the repository root. Absolute-path
      patterns also work, but repository-relative paths are the intended form.


## Extra options

The following keys are recognized in the `extra_reuse_cli_options` object, each of which has the
corresponding CLI option for `reuse annotate`:

- `style` (string) is a choice of predefined strings documented in the `reuse annotate` help
  screen.

- `template` (string) is a repository-provided template name (from `.reuse/templates` directory),
  which also maps to the corresponding CLI option.

- `copyright_prefix` (string) is a choice of predefined strings documented in the `reuse
  annotate` help screen.

- `force_dot_license`, `exclude_year`, `merge_copyrights`, and `no_replace` (boolean): the `true`
  value adds the corresponding CLI option.

As noted above, extra options can be provided for the `templates` object and will affect only the
input file that matches a pattern.

Additionally, a "global" (top-level) extra options object can be given, and options from it are
added unconditionally to the effective CLI. Therefore, not all options make sense in this
context. For example, `style` or `template` most likely do not make sense in the global context.

See the example configuration file in this repository.
