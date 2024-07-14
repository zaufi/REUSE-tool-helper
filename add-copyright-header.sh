#!/bin/bash
#
# SPDX-FileCopyrightText: 2024 Alex Turbov <i.zaufi@gmail.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#

set -e

shopt -s extglob globstar

# BEGIN Helper functions
function try_match_file_and_get_object()
{
    local -r input_file="$1"
    local -r array_json="$2"
    local -ir count=$(jq '. | length' <<<${array_json})

    for ((i=0; i<=count-1; i++)) do
        local candidate_json="$(jq ".[${i}]" <<<${array_json})"
        local -a patterns=( $(jq .patterns[] <<<${candidate_json}) )
        for pattern in "${patterns[@]}"; do
            if [[ "\"${input_file}\"" == ${pattern} ]]; then
                if [[ ${VERBOSE} -gt 0 ]]; then
                    echo "Match: ${input_file} -> ${pattern}" >&2
                fi
                jq -r 'del(.patterns)' <<<${candidate_json}
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
                <<<${json}
            ;;
        str)
            jq -r \
                "if .extra_reuse_cli_options.${name} then \
                    \"--${name//_/-} \" + .extra_reuse_cli_options.${name} \
                else \
                    \"\" \
                end" \
                <<<${json}
            ;;
        *)
            ;;
    esac
}

function try_get_extra_options()
{
    local -r json="$1"
    local -n output_opts="$2"

    output_opts+=( $(get_extra_reuse_cli_option merge_copyrights bool "${json}") )
    output_opts+=( $(get_extra_reuse_cli_option no_replace bool "${json}") )
    output_opts+=( $(get_extra_reuse_cli_option force_dot_license bool "${json}") )

    declare -r prefix="$(get_extra_reuse_cli_option copyright_prefix str "${json}")"
    if [[ -n ${prefix} ]]; then
        case $(cut -f 2 -d ' ' <<<${prefix}) in
            # TODO Parse `reuse` help and get this list?
            spdx | spdx-c | spdx-symbol | string | string-c | string-symbol | symbol)
                output_opts+=( ${prefix} )
                ;;
            *)
                echo 'Error: Invalid value for copyright_prefix' >&2
                exit 1
                ;;
        esac
    fi

    # TODO Deduplicate this code. It's very similar to `copyright_prefix`!
    declare -r style="$(get_extra_reuse_cli_option style str "${json}")"
    if [[ -n ${style} ]]; then
        case $(cut -f 2 -d ' ' <<<${style}) in
            # TODO Parse `reuse` help and get this list?
            applescript | aspx | bat | bibtex | c |cpp | cppsingle | \
            f | ftl | handlebars | haskell | html | jinja | julia | \
            lisp | m4 | ml | f90 | plantuml | python | rst | \
            semicolon | tex | man | vst | vim | xquery)
                output_opts+=( ${style} )
                ;;
            *)
                echo 'Error: Invalid value for style' >&2
                exit 1
                ;;
        esac
    fi

    declare -r template="$(get_extra_reuse_cli_option template str "${json}")"
    output_opts+=( ${template} )

    # TODO Any other options to add?
}
# END Helper functions

declare hdrmap_file="$(git rev-parse --show-toplevel 2>/dev/null)"/.reuse-hdrmap.json
declare dry_run

while getopts 'c:d' option; do
    case ${option} in
    c)
        hdrmap_file="${OPTARG}"
        ;;
    d)
        dry_run=echo
        ;;
    *)
        exit 1
        ;;
    esac
done
shift $((OPTIND - 1))

if [[ ! -f ${hdrmap_file} ]]; then
    echo "Error: No hdrmap config file found: ${hdrmap_file}" >&2
    exit 1
fi

declare -a input_files=( "${@}" )
if [[ ${#input_files} -eq 0 ]]; then
    echo "Error: No input files given" >&2
    exit 1
fi

declare -r hdrmap_json="$(<${hdrmap_file})"
# NOTE Validate JSON
if ! jq empty <<<${hdrmap_json} 2>/dev/null; then
    echo "Error: Input file isn't a valid JSON: ${hdrmap_file}" >&2
    exit 1
fi

declare git_reuse_name="$(get_any_of_git_options reuse.name user.name)"
declare git_reuse_email="$(get_any_of_git_options reuse.email user.email)"

for input_file in "${input_files[@]}"; do
    # Collect the final `reuse` CLI options here
    declare -a extra_opts=()

    declare template_json="$(
        try_match_file_and_get_object "${input_file}" "$(jq .templates <<<${hdrmap_json})"
      )"
    try_get_extra_options "${template_json}" extra_opts
    # Make sure template or style has been given in the `extra_reuse_cli_options`
    if [[ ${#extra_opts[@]} -eq 0 ]]; then
        echo "Error: No template or style match found for ${input_file}. Skip it."
        continue
    fi

    declare license_json="$(
        try_match_file_and_get_object "${input_file}" "$(jq .licenses <<<${hdrmap_json})"
      )"
    declare license=$(jq -r '.ref // empty' <<<${license_json})
    if [[ -n ${license} ]]; then
        extra_opts+=('--license' "${license}")
    else
        echo "Error: No license match found for ${input_file}. Skip it."
        continue
    fi

    declare copyright_json="$(
        try_match_file_and_get_object "${input_file}" "$(jq .copyright_headers <<<${hdrmap_json})"
      )"
    declare copyright=$(jq -r '.text // empty' <<<${copyright_json})
    if [[ -z ${copyright} ]]; then
        echo "Error: No copyright match found for ${input_file}. Skip it."
        continue
    fi
    copyright="$(subst_git_config_options reuse.name "${git_reuse_name}" "${copyright}")"
    copyright="$(subst_git_config_options reuse.email "${git_reuse_email}" "${copyright}")"
    extra_opts+=('--copyright' "${copyright}")

    try_get_extra_options "${hdrmap_json}" extra_opts

    ${dry_run} reuse annotate "${extra_opts[@]}" "${input_file}"
done
