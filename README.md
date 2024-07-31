<!--
SPDX-FileCopyrightText: 2024 Alex Turbov <i.zaufi@gmail.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# What is This

The repo provides a helper script (`add-copyright-headers`) that simplifies adding or updating
copyright headers in large projects migrating to the [reuse tool].

The script is looking for the configuration file at the top directory of the current Git
repository. The configuration file is a JSON file named `.reuse-hdrmap.json`. It consists of
the following top-level keys, each of which is an array of objects: `templates`, `licenses`, and
`copyright_headers`. Also, there could be a "global" `extra_reuse_cli_options` object.

[reuse tool]: https://reuse.software/

```console
$ add-copyright-header -h
Usage: add-copyright-header [-d] [FILENAME]...

Add copyright header to files according to the matched patterns in the '.reuse-hdrmap.json'

Options:
    -d      show command but don't execute it
```


## Templates object

Each object of the `templates` array has the following properties (keys):

- `patterns` is an array of shell (possibly `extglob`) patterns to match input files.
- `extra_reuse_cli_options` provides extra options to the [`reuse annotate` command line].
   See below.

The first matched pattern will stop further matching, and specified extra options added to the
final CLI for `reuse annotate`.

[`reuse annotate` command line]: https://reuse.readthedocs.io/en/stable/man/reuse-annotate.html


## Licenses object

Each object of the `licenses` array has the following properties (keys):

- `patterns` is an array of shell (possibly `extglob`) patterns to match input files.
- `ref` is an [SPDX license expression] that will be applied to the matched input file.

[SPDX license expression]: https://spdx.github.io/spdx-spec/v3.0/annexes/SPDX-license-expressions/


## Copyright headers object

Each object of the `copyright_headers` array has the following properties (keys):

- `patterns` is an array of shell (possibly `extglob`) patterns to match input files.
- `text` is a copyright text to apply for the matched input file.


## Extra options

The following keys recognized in the `extra_reuse_cli_options` object, each of which has the
corresponding CLI option for `reuse annotate`:

- `style` (string) a choice of predefined strings documented in the `reuse annotate` help screen.

- `template` (string) is a repository-provided template name (from `.reuse/templates` directory),
  which also maps to the corresponding CLI option.

- `copyright_prefix` (string) a choice of predefined strings documented in the `reuse annotate`
  help screen.

- `force_dot_license`, `exclude_year`, `merge_copyrights`, and  `no_replace` (boolean) the `true`
  value will add the corresponding CLI option.

As noticed above, extra options could be provided for the `templates` object and will affect only
input file that matches a pattern.

Additionally, a "global" (top-level) extra options object can be given, and options from it
will be added unconditionally to the effective CLI. Hence, not all options make sense in this
context. E.g., `style` or `template` most likely have no sense in the "global" context ;-)

Please check the example of the configuration file in this repository.
