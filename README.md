<!--
SPDX-FileCopyrightText: 2024 Alex Turbov <i.zaufi@gmail.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# What is This

The repo provides a helper script, `add-copyright-headers`, aimed to simplify adding or updating
copyright headers in large projects migrating to the `reuse` tool.

The script is looking for the configuration file at the top directory of the current Git
repository. The configuration file is a JSON file named `.reuse-hdrmap.json`. It consists of
the following top-level keys, each of which is an array of objects: `templates`, `licenses`,
and `copyright_headers`. Also, there is could be "global" `extra_reuse_cli_options` object.


## Templates object

Each object of the `templates` array has the following properties (keys):

- `patterns` is an array of shell (possibly `extglob`) patterns to match input files.
- `extra_reuse_cli_options` provides extra options to the `reuse annotate` command line. See below.

The first pattern matched will stop further matching, and specified extra options will be added
to the final CLI for `reuse annotate`.


## Licenses object

Each object of the `licenses` array has the following properties (keys):

- `patterns` is an array of shell (possibly `extglob`) patterns to match input files.
- `ref` is an SPDX license expression to apply for the matched input file.


## Copyright headers object

Each object of the `copyright_headers` array has the following properties (keys):

- `patterns` is an array of shell (possibly `extglob`) patterns to match input files.
- `text` is a copyright text to apply for the matched input file.


## Extra options

The following keys are recognized in the `extra_reuse_cli_options` object, each of wich has
the corresponding CLI option for `reuse annotate`:

- `style` (string) choice of predefined strings documented in the `reuse annotate` help screen.

- `template` (string) a user provided template name, which also maps to the corresponding
  CLI option.

- `copyright_prefix` (string) choice of predefined strings documented in the `reuse annotate`
  help screen.

- `force_dot_license`, `no_replace`, and `merge_copyrights` (boolean) the `true` value will add
  the corresponding CLI option.

As noticed above, extra options could be provided for the `templates` object and will affect only
input files that matches a pattern.

Additionally, a "global" (top-level) extra options object can be given and options from it
unconditionally will be added to the effective CLI. Hence, not all options make sense in
this context. E.g., `style` or `template` most likely have no sense in the "global" context ;-)

