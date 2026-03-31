#!/bin/bash
#
# SPDX-FileCopyrightText: 2024-2026 Alex Turbov <i.zaufi@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#

set -e

shopt -s extglob globstar

# BEGIN Helper functions
function die()
{
    echo "$@" >&2
    exit 1
}

function warning()
{
    echo "$@" >&2
}

function try_match_file_and_get_object()
{
    local -r input_file="$(realpath -m "$1")"
    local repo_relative_file=
    local -r array_json="$2"
    local -ir count=$(jq '. | length' <<<"${array_json}")
    local -a patterns=()
    local candidate_json
    local pattern

    if [[ -n ${git_toplevel} ]]; then
        repo_relative_file="$(realpath -m --relative-to="${git_toplevel}" "${input_file}")"
    fi

    for ((i=0; i<=count-1; i++)) do
        candidate_json="$(jq ".[${i}]" <<<"${array_json}")"
        mapfile -t patterns < <(jq -r '.patterns[]' <<<"${candidate_json}")
        for pattern in "${patterns[@]}"; do
            # shellcheck disable=SC2053
            if [[ ${repo_relative_file} == ${pattern} || ${input_file} == ${pattern} ]]; then
                if [[ ${VERBOSE} -gt 0 ]]; then
                    echo "Match: ${repo_relative_file:-${input_file}} -> ${pattern}" >&2
                fi
                jq -r 'del(.patterns)' <<<"${candidate_json}"
                return
            fi
        done
    done
}

function get_any_of_git_options()
{
    local name
    for name in "$@"; do
        local value="$(git config --get "${name}")"
        if [[ -n ${value} ]]; then
            echo "${value}"
            break
        fi
    done
}

function subst_git_config_options()
{
    local -r name="$1"
    local -r value="$2"
    local -r text="$3"
    if [[ ${text} =~ (.*)%${name}%(.*) ]]; then
        echo "${BASH_REMATCH[1]}${value}${BASH_REMATCH[2]}"
    else
        echo "${text}"
    fi
}

function get_extra_reuse_cli_option()
{
    local -r name="$1"
    local -r option_type="$2"
    local -r json="$3"

    case "${option_type}" in
        bool)
            jq -r \
                "if .extra_reuse_cli_options.${name} == true then \
                    \"--${name//_/-}\" \
                else \
                    \"\" \
                end" \
                <<<"${json}"
            ;;
        str)
            jq -r ".extra_reuse_cli_options.${name} // empty" <<<"${json}"
            ;;
        *)
            ;;
    esac
}

function parse_reuse_annotate_allowed_values()
{
    local -r option_name="$1"
    local option_line=
    local option_values=
    local value

    option_line="$(grep -F -- "--${option_name} [" <<<"${reuse_annotate_help}")"
    [[ -n ${option_line} ]] || die "Error: Failed to parse \`reuse annotate --help\` for --${option_name}"

    if [[ ${option_line} =~ --${option_name}[[:space:]]\[([^]]+)\] ]]; then
        option_values="${BASH_REMATCH[1]}"
    else
        die "Error: Failed to parse \`reuse annotate --help\` for --${option_name}"
    fi

    for value in ${option_values//|/ }; do
        [[ -n ${value} ]] && printf '%s\n' "${value}"
    done
}

function option_value_allowed_in()
{
    local -n allowed_values="$1"
    local -r value="$2"
    local allowed_value

    for allowed_value in "${allowed_values[@]}"; do
        [[ ${allowed_value} == "${value}" ]] && return 0
    done

    return 1
}

function try_get_extra_options()
{
    local -r json="$1"
    local -n output_opts="$2"
    local value

    value="$(get_extra_reuse_cli_option merge_copyrights bool "${json}")"
    [[ -n ${value} ]] && output_opts+=("${value}")
    value="$(get_extra_reuse_cli_option no_replace bool "${json}")"
    [[ -n ${value} ]] && output_opts+=("${value}")
    value="$(get_extra_reuse_cli_option force_dot_license bool "${json}")"
    [[ -n ${value} ]] && output_opts+=("${value}")
    value="$(get_extra_reuse_cli_option exclude_year bool "${json}")"
    [[ -n ${value} ]] && output_opts+=("${value}")

    value="$(get_extra_reuse_cli_option copyright_prefix str "${json}")"
    if [[ -n ${value} ]]; then
        if option_value_allowed_in _ALLOWED_COPYRIGHT_PREFIXES "${value}"; then
            output_opts+=('--copyright-prefix' "${value}")
        else
            die 'Error: Invalid value for copyright_prefix'
        fi
    fi

    # TODO Deduplicate this code. It's very similar to `copyright_prefix`!
    value="$(get_extra_reuse_cli_option style str "${json}")"
    if [[ -n ${value} ]]; then
        if option_value_allowed_in _ALLOWED_STYLES "${value}"; then
            output_opts+=('--style' "${value}")
        else
            die 'Error: Invalid value for style'
        fi
    fi

    value="$(get_extra_reuse_cli_option template str "${json}")"
    if [[ -n ${value} ]]; then
        output_opts+=('--template' "${value}")
    fi

    # TODO Any other options to add?
}

function usage()
{
    cat <<EOF
Usage: $0 [-d] [FILENAME]...

Add copyright header to files according to the matched patterns in the '.reuse-hdrmap.json'

Options:
    -d      show REUSE command but don't execute it
EOF
}
# END Helper functions

declare git_toplevel="$(git rev-parse --show-toplevel 2>/dev/null)"
declare hdrmap_file="${git_toplevel}"/.reuse-hdrmap.json
declare dry_run

while getopts 'hc:d' option; do
    case ${option} in
    c)
        hdrmap_file="${OPTARG}"
        ;;
    d)
        dry_run='echo'
        ;;
    h)
        usage
        exit 0
        ;;
    *)
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

if [[ ! -f ${hdrmap_file} ]]; then
    die "Error: No hdrmap config file found: ${hdrmap_file}"
fi

declare -a input_files=( "${@}" )
if [[ ${#input_files[@]} -eq 0 ]]; then
    die 'Error: No input files given'
fi

declare -r hdrmap_json="$(<"${hdrmap_file}")"
# NOTE Validate JSON
if ! jq empty <<<"${hdrmap_json}" 2>/dev/null; then
    die "Error: Input file isn't a valid JSON: ${hdrmap_file}"
fi

declare -r git_reuse_name="$(get_any_of_git_options reuse.name user.name)"
declare -r git_reuse_email="$(get_any_of_git_options reuse.email user.email)"

declare -r reuse_annotate_help="$(reuse annotate --help)"
declare -a _ALLOWED_STYLES=()
mapfile -t _ALLOWED_STYLES < <(parse_reuse_annotate_allowed_values style)
readonly -a _ALLOWED_STYLES
declare -a _ALLOWED_COPYRIGHT_PREFIXES=()
mapfile -t _ALLOWED_COPYRIGHT_PREFIXES < <(parse_reuse_annotate_allowed_values copyright-prefix)
readonly -a _ALLOWED_COPYRIGHT_PREFIXES

for input_file in "${input_files[@]}"; do
    # Collect the final `reuse` CLI options here
    declare -a extra_opts=()

    declare template_json="$(
        try_match_file_and_get_object "${input_file}" "$(jq .templates <<<"${hdrmap_json}")"
      )"
    try_get_extra_options "${template_json}" extra_opts
    # Make sure template or style has been given in the `extra_reuse_cli_options`
    if [[ ${#extra_opts[@]} -eq 0 ]]; then
        warning "Error: No template or style match found for ${input_file}. Skip it."
        continue
    fi

    declare license_json="$(
        try_match_file_and_get_object "${input_file}" "$(jq .licenses <<<"${hdrmap_json}")"
      )"
    declare license="$(jq -r '.ref // empty' <<<"${license_json}")"
    if [[ -n ${license} ]]; then
        extra_opts+=('--license' "${license}")
    else
        warning "Error: No license match found for ${input_file}. Skip it."
        continue
    fi

    declare copyright_json="$(
        try_match_file_and_get_object "${input_file}" "$(jq .copyright_headers <<<"${hdrmap_json}")"
      )"
    declare copyright="$(jq -r '.text // empty' <<<"${copyright_json}")"
    if [[ -z ${copyright} ]]; then
        warning "Error: No copyright match found for ${input_file}. Skip it."
        continue
    fi
    copyright="$(subst_git_config_options reuse.name "${git_reuse_name}" "${copyright}")"
    copyright="$(subst_git_config_options reuse.email "${git_reuse_email}" "${copyright}")"
    extra_opts+=('--copyright' "${copyright}")

    try_get_extra_options "${hdrmap_json}" extra_opts

    ${dry_run} reuse annotate "${extra_opts[@]}" "${input_file}"
done
