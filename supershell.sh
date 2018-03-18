#!/usr/bin/env sh
# shellcheck shell=bash
# shellcheck disable=SC2039

#                                         .__           .__  .__   
#   ________ ________   ___________  _____|  |__   ____ |  | |  |  
#  /  ___/  |  \____ \_/ __ \_  __ \/  ___/  |  \_/ __ \|  | |  |  
#  \___ \|  |  /  |_> >  ___/|  | \/\___ \|   Y  \  ___/|  |_|  |__
# /____  >____/|   __/ \___  >__|  /____  >___|  /\___  >____/____/
#      \/      |__|        \/           \/     \/     \/           
# MIT License
#
# Copyright (c) 2018 Luís Ferreira
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Displays the given error.
# Used for common error output.
_supershell_error()
{
  (>&2 echo -e "supershell: $1: \033[31mERROR\033[0m: $2")
}

# Displays the given warning.
# Used for common warning output.
_supershell_warning()
{
  (>&2 echo -e "supershell: $1: \033[33mWARN\033[0m: $2")
}

#                 __          
#    ____   _____/  |_  ____  
#   / ___\ /  _ \   __\/  _ \ 
#  / /_/  >  <_> )  | (  <_> )
#  \___  / \____/|__|  \____/ 
# /_____/                     
# Based on: https://github.com/iridakos/goto
# MIT License
# Copyright (c) 2018 Lazarus Lazaridis


# Changes to the given alias directory
# or executes a command based on the arguments.
goto()
{
  local target
  _goto_resolve_db

  if [ -z "$1" ]; then
    # display usage and exit when no args
    _goto_usage
    return
  fi

  subcommand="$1"
  shift
  case "$subcommand" in
    -c|--cleanup)
      _goto_cleanup "$@"
      ;;
    -r|--register) # Register an alias
      _goto_register_alias "$@"
      ;;
    -u|--unregister) # Unregister an alias
      _goto_unregister_alias "$@"
      ;;
    -p|--push) # Push the current directory onto the pushd stack, then goto
      _goto_directory_push "$@"
      ;;
    -o|--pop) # Pop the top directory off of the pushd stack, then change that directory
      _goto_directory_pop
      ;;
    -l|--list)
      _goto_list_aliases
      ;;
    -x|--expand) # Expand an alias
      _goto_expand_alias "$@"
      ;;
    -h|--help)
      _goto_usage
      ;;
    -v|--version)
      _goto_version
      ;;
    *)
      _goto_directory "$subcommand"
      ;;
  esac
  return $?
}

_goto_resolve_db()
{
  GOTO_DB="${GOTO_DB:-$HOME/.goto}"
}

_goto_usage()
{
  cat <<\USAGE
usage: goto [<option>] <alias> [<directory>]

default usage:
  goto <alias> - changes to the directory registered for the given alias

OPTIONS:
  -r, --register: registers an alias
    goto -r|--register <alias> <directory>
  -u, --unregister: unregisters an alias
    goto -u|--unregister <alias>
  -p, --push: pushes the current directory onto the stack, then performs goto
    goto -p|--push <alias>
  -o, --pop: pops the top directory from the stack, then changes to that directory
    goto -o|--pop
  -l, --list: lists aliases
    goto -l|--list
  -x, --expand: expands an alias
    goto -x|--expand <alias>
  -c, --cleanup: cleans up non existent directory aliases
    goto -c|--cleanup
  -h, --help: prints this help
    goto -h|--help
  -v, --version: displays the version of the goto script
    goto -v|--version
USAGE
}

# Displays version
_goto_version()
{
  echo "goto version 1.2.3"
}

# Expands directory.
# Helpful for ~, ., .. paths
_goto_expand_directory()
{
  cd "$1" 2>/dev/null && pwd
}

# Lists registered aliases.
_goto_list_aliases()
{
  local IFS=$'\n'
  if [ -f "$GOTO_DB" ]; then
    column -t "$GOTO_DB" 2>/dev/null
  else
    echo "You haven't configured any directory aliases yet."
  fi
}

# Expands a registered alias.
_goto_expand_alias()
{
  if [ "$#" -ne "1" ]; then
    _supershell_error "goto" "usage: goto -x|--expand <alias>"
    return
  fi

  local resolved

  resolved=$(_goto_find_alias_directory "$1")
  if [ -z "$resolved" ]; then
    _supershell_error "goto" "alias '$1' does not exist"
    return
  fi

  echo "$resolved"
}

# Lists duplicate directory aliases
_goto_find_duplicate()
{
  local duplicates=

  duplicates=$(sed -n 's:[^ ]* '"$1"'$:&:p' "$GOTO_DB" 2>/dev/null)
  echo "$duplicates"
}

# Registers and alias.
_goto_register_alias()
{
  if [ "$#" -ne "2" ]; then
    _supershell_error "goto" "usage: goto -r|--register <alias> <directory>"
    return 1
  fi

  if ! [[ $1 =~ ^[[:alnum:]]+[a-zA-Z0-9_-]*$ ]]; then
    _supershell_error "goto" "invalid alias - can start with letters or digits followed by letters, digits, hyphens or underscores"
    return 1
  fi

  local resolved
  resolved=$(_goto_find_alias_directory "$1")

  if [ -n "$resolved" ]; then
    _supershell_error "goto" "alias '$1' exists"
    return 1
  fi

  local directory
  directory=$(_goto_expand_directory "$2")
  if [ -z "$directory" ]; then
    _supershell_error "goto" "failed to register '$1' to '$2' - can't cd to directory"
    return 1
  fi

  local duplicate
  duplicate=$(_goto_find_duplicate "$directory")
  if [ -n "$duplicate" ]; then
    _supershell_warning "goto" "duplicate alias(es) found: \\n$duplicate"
  fi

  # Append entry to file.
  echo "$1 $directory" >> "$GOTO_DB"
  echo "Alias '$1' registered successfully."
}

# Unregisters the given alias.
_goto_unregister_alias()
{
  if [ "$#" -ne "1" ]; then
    _supershell_error "goto" "usage: goto -u|--unregister <alias>"
    return 1
  fi

  local resolved
  resolved=$(_goto_find_alias_directory "$1")
  if [ -z "$resolved" ]; then
    _supershell_error "goto" "alias '$1' does not exist"
    return 1
  fi

  # shellcheck disable=SC2034
  local readonly GOTO_DB_TMP="$HOME/.goto_"
  # Delete entry from file.
  sed "/^$1 /d" "$GOTO_DB" > "$GOTO_DB_TMP" && mv "$GOTO_DB_TMP" "$GOTO_DB"
  echo "Alias '$1' unregistered successfully."
}

# Pushes the current directory onto the stack, then goto
_goto_directory_push()
{
  if [ "$#" -ne "1" ]; then
    _supershell_error "goto" "usage: goto -p|--push <alias>"
    return
  fi

  { pushd . || return; } 1>/dev/null 2>&1

  _goto_directory "$@"
}

# Pops the top directory from the stack, then goto
_goto_directory_pop()
{
  { popd || return; } 1>/dev/null 2>&1
}

# Unregisters aliases whose directories no longer exist.
_goto_cleanup()
{
  if ! [ -f "$GOTO_DB" ]; then
    return
  fi

  while IFS= read -r i && [ -n "$i" ]; do
    echo "Cleaning up: $i"
    _goto_unregister_alias "$i"
  done <<< "$(awk '{al=$1; $1=""; dir=substr($0,2);
                    system("[ ! -d \"" dir "\" ] && echo " al)}' "$GOTO_DB")"
}

# Changes to the given alias' directory
_goto_directory()
{
  local target

  target=$(_goto_resolve_alias "$1") || return 1

  cd "$target" 2> /dev/null || \
    { _supershell_error "goto" "Failed to goto '$target'" && return 1; }
}

# Fetches the alias directory.
_goto_find_alias_directory()
{
  local resolved

  resolved=$(sed -n "s/^$1 \\(.*\\)/\\1/p" "$GOTO_DB" 2>/dev/null)
  echo "$resolved"
}

# Displays entries with aliases starting as the given one.
_goto_print_similar()
{
  local similar

  similar=$(sed -n "/^$1[^ ]* .*/p" "$GOTO_DB" 2>/dev/null)
  if [ -n "$similar" ]; then
    (>&2 echo "Did you mean:")
    (>&2 column -t <<< "$similar")
  fi
}

# Fetches alias directory, errors if it doesn't exist.
_goto_resolve_alias()
{
  local resolved

  resolved=$(_goto_find_alias_directory "$1")

  if [ -z "$resolved" ]; then
    _supershell_error "goto" "unregistered alias $1"
    _goto_print_similar "$1"
    return 1
  else
    echo "${resolved}"
  fi
}

# Completes the goto function with the available commands
_complete_goto_commands()
{
  local IFS=$' \t\n'

  # shellcheck disable=SC2207
  COMPREPLY=($(compgen -W "-r --register -u --unregister -p --push -o --pop -l --list -x --expand -c --cleanup -v --version" -- "$1"))
}

# Completes the goto function with the available aliases
_complete_goto_aliases()
{
  local IFS=$'\n' matches
  _goto_resolve_db

  # shellcheck disable=SC2207
  matches=($(sed -n "/^$1/p" "$GOTO_DB" 2>/dev/null))

  if [ "${#matches[@]}" -eq "1" ]; then
    # remove the filenames attribute from the completion method
    compopt +o filenames 2>/dev/null

    # if you find only one alias don't append the directory
    COMPREPLY=("${matches[0]// *}")
  else
    for i in "${!matches[@]}"; do
      # remove the filenames attribute from the completion method
      compopt +o filenames 2>/dev/null

      if ! [[ $(uname -s) =~ Darwin* ]]; then
        matches[$i]=$(printf '%*s' "-$COLUMNS" "${matches[$i]}")

        COMPREPLY+=("$(compgen -W "${matches[$i]}")")
      else
        COMPREPLY+=("${matches[$i]// */}")
      fi
    done
  fi
}

# Bash programmable completion for the goto function
_complete_goto_bash()
{
  local cur="${COMP_WORDS[$COMP_CWORD]}" prev

  if [ "$COMP_CWORD" -eq "1" ]; then
    # if we are on the first argument
    if [[ $cur == -* ]]; then
      # and starts like a command, prompt commands
      _complete_goto_commands "$cur"
    else
      # and doesn't start as a command, prompt aliases
      _complete_goto_aliases "$cur"
    fi
  elif [ "$COMP_CWORD" -eq "2" ]; then
    # if we are on the second argument
    prev="${COMP_WORDS[1]}"

    if [[ $prev = "-u" ]] || [[ $prev = "--unregister" ]]; then
      # prompt with aliases if user tries to unregister one
      _complete_goto_aliases "$cur"
    elif [[ $prev = "-x" ]] || [[ $prev = "--expand" ]]; then
      # prompt with aliases if user tries to expand one
      _complete_goto_aliases "$cur"
    elif [[ $prev = "-p" ]] || [[ $prev = "--push" ]]; then
      # prompt with aliases only if user tries to push
      _complete_goto_aliases "$cur"
    fi
  elif [ "$COMP_CWORD" -eq "3" ]; then
    # if we are on the third argument
    prev="${COMP_WORDS[1]}"

    if [[ $prev = "-r" ]] || [[ $prev = "--register" ]]; then
      # prompt with directories only if user tries to register an alias
      local IFS=$' \t\n'

      # shellcheck disable=SC2207
      COMPREPLY=($(compgen -d -- "$cur"))
    fi
  fi
}

# Zsh programmable completion for the goto function
_complete_goto_zsh()
{
  local all_aliases=()
  while IFS= read -r line; do
    all_aliases+=("$line")
  done <<< "$(sed -e 's/ /:/g' ~/.goto 2>/dev/null)"

  local state
  local -a options=(
    '(1)'{-r,--register}'[registers an alias]:register:->register'
    '(- 1 2)'{-u,--unregister}'[unregisters an alias]:unregister:->unregister'
    '(: -)'{-l,--list}'[lists aliases]'
    '(*)'{-c,--cleanup}'[cleans up non existent directory aliases]'
    '(1 2)'{-x,--expand}'[expands an alias]:expand:->aliases'
    '(1 2)'{-p,--push}'[pushes the current directory onto the stack, then performs goto]:push:->aliases'
    '(*)'{-o,--pop}'[pops the top directory from stack, then changes to that directory]'
    '(: -)'{-h,--help}'[prints this help]'
    '(* -)'{-v,--version}'[displays the version of the goto script]'
  )

  _arguments -C \
    "${options[@]}" \
    '1:alias:->aliases' \
    '2:dir:_files' \
  && ret=0

  case ${state} in
    (aliases)
      _describe -t aliases 'goto aliases:' all_aliases && ret=0
    ;;
    (unregister)
      _describe -t aliases 'unregister alias:' all_aliases && ret=0
    ;;
  esac
  return $ret
}

# Register the goto completions.
if [ -n "${BASH_VERSION}" ]; then
  if ! [[ $(uname -s) =~ Darwin* ]]; then
    complete -o filenames -F _complete_goto_bash goto
  else
    complete -F _complete_goto_bash goto
  fi
elif [ -n "${ZSH_VERSION}" ]; then
  compdef _complete_goto_zsh goto
else
  echo "Unsupported shell."
  exit 1
fi

#==============================================================================

#         .__  __  .__     
# __  _  _|__|/  |_|  |__  
# \ \/ \/ /  \   __\  |  \ 
#  \     /|  ||  | |   Y  \
#   \/\_/ |__||__| |___|  /
#                       \/ 
# Based on: https://github.com/mchav/with
# MIT License
# Copyright (c) 2016 Michael Chavinda

_with_print_usage()
{
  print """
    USAGE:
      with <prefix>
    Prefix can be any string with a valid executable.
  """
}

with()
{
  _supershell_error "with" "simple error"
  #add options here, such as -h, -v
  declare -a prefix
  prefix=( "$@" )

  case ${prefix[*]} in
    "" )
      echo "Missing arguments."
      echo "usage: with <program>";;
    "-v"|"--version")
      echo "with, version $VERSION";;
    "-h"|"--help")
      _with_print_help;;
    -*|--*)
      echo "Unrecognised option:" ${prefix[*]}
      echo "  -h, --help   : Display command help"
      echo "  -v, --version: Display the currently installed version of with";;
  esac

  pmpt=${prefix[*]}

  trap _with_finish exit
  [ "$PROMPT_FORMAT" ] || PROMPT_FORMAT+='%yel%$%nc% ' \
                        PROMPT_FORMAT+='%cyn%%prefix%%nc% ' \
                        PROMPT_FORMAT+='%wht%>%nc% '

  HISTCONTROL=ignoreboth

  # run script setup
  
  # source bash completions
  [ -f /etc/bash_completion ] && source /etc/bash_completion

  BASH_COMPLETION_DEFAULT_DIR=/usr/share/bash-completion/completions
  for completion_file in $BASH_COMPLETION_DEFAULT_DIR/* $BASH_COMPLETION_COMPAT_DIR/*
  do
    . "$completion_file" &> /dev/null
  done

  # initialise history file
  touch /tmp/with_history

  # set up colour codes
  __blk="$(tput setaf 0)"
  __red="$(tput setaf 1)"
  __grn="$(tput setaf 2)"
  __yel="$(tput setaf 3)"
  __blu="$(tput setaf 4)"
  __mag="$(tput setaf 5)"
  __cyn="$(tput setaf 6)"
  __wht="$(tput setaf 7)"

  __bold_blk="$__bold$__blk"
  __bold_red="$__bold$__red"
  __bold_grn="$__bold$__grn"
  __bold_yel="$__bold$__yel"
  __bold_blu="$__bold$__blu"
  __bold_mag="$__bold$__mag"
  __bold_cyn="$__bold$__cyn"
  __bold_wht="$__bold$__wht"

  __on_blk="$(tput setab 0)"
  __on_red="$(tput setab 1)"
  __on_grn="$(tput setab 2)"
  __on_yel="$(tput setab 3)"
  __on_blu="$(tput setab 4)"
  __on_mag="$(tput setab 5)"
  __on_cyn="$(tput setab 6)"
  __on_wht="$(tput setab 7)"

  # color reset
  __nc="$(tput sgr0)"

  __blk() { echo -n "$__blk$*$__nc"; }
  __red() { echo -n "$__red$*$__nc"; }
  __grn() { echo -n "$__grn$*$__nc"; }
  __yel() { echo -n "$__yel$*$__nc"; }
  __blu() { echo -n "$__blu$*$__nc"; }
  __mag() { echo -n "$__mag$*$__nc"; }
  __cyn() { echo -n "$__cyn$*$__nc"; }
  __wht() { echo -n "$__wht$*$__nc"; }

  __bold_blk() { echo -n "$__bold_blk$*$__nc"; }
  __bold_red() { echo -n "$__bold_red$*$__nc"; }
  __bold_grn() { echo -n "$__bold_grn$*$__nc"; }
  __bold_yel() { echo -n "$__bold_yel$*$__nc"; }
  __bold_blu() { echo -n "$__bold_blu$*$__nc"; }
  __bold_mag() { echo -n "$__bold_mag$*$__nc"; }
  __bold_cyn() { echo -n "$__bold_cyn$*$__nc"; }
  __bold_wht() { echo -n "$__bold_wht$*$__nc"; }

  __on_blk() { echo -n "$__on_blk$*$__nc"; }
  __on_red() { echo -n "$__on_red$*$__nc"; }
  __on_grn() { echo -n "$__on_grn$*$__nc"; }
  __on_yel() { echo -n "$__on_yel$*$__nc"; }
  __on_blu() { echo -n "$__on_blu$*$__nc"; }
  __on_mag() { echo -n "$__on_mag$*$__nc"; }
  __on_cyn() { echo -n "$__on_cyn$*$__nc"; }
  __on_wht() { echo -n "$__on_wht$*$__nc"; }

  if [ "$1" == "" ]; then
    print_usage
  elif ! type "$1" > /dev/null 2>&1; then
    echo "error: \"$1\" is not a valid executable"
    exit 1
  fi

  while true ; do
    run_with
done
}

_with__print_prompt() {
  __prefix="${prefix[*]}" _with_print_prompt "$@"
}

_with_print_prompt() {

  # TODO: change name to correct
  hashdollar() {
    (( UID )) && echo '$' \
              || echo '#'
  }

  colorise_prompt() {
    local to_be_replaced=(blk red grn yel blu mag cyn wht)

    local SED_COMMAND_LINE=('sed' '-E')

    for color in "${to_be_replaced[@]}"; do
      SED_COMMAND_LINE+=(
        '-e' "s/%on_$color%/$(eval echo "\$__on_$color")/g"
        '-e' "s/%bold_$color%/$(eval echo "\$__bold_$color")/g"
        '-e' "s/%$color%/$(eval echo "\$__$color")/g"
        )
    done

    "${SED_COMMAND_LINE[@]}" -e "s/%nc%/$__nc/g"
  }
  local __escaped_prefix=$(echo -n "$__prefix" | sed -e 's/\./\\./g' -e 's/\//\\\//g')
  echo -n "$*" | colorise_prompt | sed -E -e "s/%prefix%/$__escaped_prefix/g" \
                                          -e "s/\\$/$(hashdollar)/g"
}

_with_completion()
{
  # print readline's prompt for visual separation
  if [ "$#" -eq 0 ]; then
      echo "$(_with__print_prompt "$PROMPT_FORMAT")$READLINE_LINE"
  fi

  # remove part after readline cursor from completion line
  local completion_line completion_word
  completion_line="${READLINE_LINE:0:READLINE_POINT}"
  completion_word="${completion_line##* }"

  # set completion cursor according to pmpt length
  COMP_POINT=$((${#pmpt}+${#completion_line}+1))
  COMP_WORDBREAKS="\n\"'><=;|&(:"
  COMP_LINE="$pmpt $completion_line"
  COMP_WORDS=($COMP_LINE)

  # TODO: the purpose of these variables is still unclear
  # COMP_TYPE=63
  # COMP_KEY=9

  # get index of word to be completed
  local whitespaces_count escaped_whitespaces_count
  whitespaces_count=$(echo "$COMP_LINE" | grep -o ' ' | wc -l)
  escaped_whitespaces_count=$(echo "$COMP_LINE" | grep -o '\\ ' | wc -l)
  COMP_CWORD=$((whitespaces_count-escaped_whitespaces_count))

  # get sourced completion command
  local program_name complete_command
  program_name=${COMP_WORDS[0]}
  program_name=$(basename "$program_name")
  complete_command=$(complete -p | grep " ${program_name}$")

  COMPREPLY=()

  # execute appropriate complete actions
  if [[ "$complete_command" =~  \ -F\  ]]
  then
    local complete_function
    complete_function=$(awk '{for(i=1;i<=NF;i++) if ($i=="-F") print $(i+1)}' <(echo "$complete_command"))

    # generate completions
    $complete_function
  else
    # construct compgen command
    local compgen_command
    compgen_command=$(echo "$complete_command" | sed 's/^complete/compgen/g')
    compgen_command="${compgen_command//$program_name/$completion_word}"

    # generate completions
    COMPREPLY=($($compgen_command))
  fi

  # get commmon prefix of available completions
  local completions_prefix readline_prefix readline_suffix
  completions_prefix=$(printf "%s\n" "${COMPREPLY[@]}" | \
    sed -e '$!{N;s/^\(.*\).*\n\1.*$/\1\n\1/;D;}' | xargs)
  readline_prefix="${READLINE_LINE:0:READLINE_POINT}"
  readline_suffix="${READLINE_LINE:READLINE_POINT}"
  # remove the word to be completed
  readline_prefix=$(sed s/'\w*$'// <(echo "$readline_prefix") | xargs)

  READLINE_LINE=""
  if [[ "$readline_prefix" != "" ]]; then
    READLINE_LINE="$readline_prefix "
  fi

  READLINE_LINE="$READLINE_LINE$completions_prefix"
  # adjust readline cursor position
  READLINE_POINT=$((${#READLINE_LINE}+1))

  if [[ "$readline_suffix" != "" ]]; then
    READLINE_LINE="$READLINE_LINE $readline_suffix"
  fi

  local completions_count display_all
  completions_count=${#COMPREPLY[@]}
  display_all="y"
  if [[ $completions_count -eq 1 ]]; then
    READLINE_LINE=$(echo "$READLINE_LINE" | xargs)
    READLINE_LINE="$READLINE_LINE "
    return
  elif [[ $completions_count -gt 80 ]]; then
    echo -en "Display all $completions_count possibilities? (y or n) "
    read -N 1 display_all
    echo "$display_all"
  fi

  if [[ "$display_all" = "y" ]]; then
    for completion in "${COMPREPLY[@]}"; do echo "$completion"; done | column
  fi
}

_with_finish()
{
  # save history to bash history
  if [ -f ~/.bash_history ]; then
    cat /tmp/with_history >> ~/.bash_history
  fi
  rm /tmp/with_history
}

_drop_with()
{
  if [ ${#prefix[@]} -gt 1 ]
  then
    prefix=( "${prefix[@]:0:${#prefix[@]}-1}" )
  else
    exit 0
  fi
}

_add_with()
{
  # separate into white space
  # FIXME: foo "bar baz" should add two elements not one
  IFS=' ' read -r -a parse_array <<< "$@"
  prefix=( "${prefix[@]}" "${parse_array[@]}" )
}

_run_with()
{
  while IFS="" read -r -e -d $'\n' -p "$(_with__print_prompt "$PROMPT_FORMAT")" options; do
    history -s "$options" > /dev/null 2>&1

    curr_command="$(echo "$options" | { read -r first rest ; echo "$first" ; })"
    case $curr_command in
      "" )
        # null case: run prefix
        ${prefix[*]} ;;
      !* )
        # replace current command
        drop_with
        parsed=${options#"!"}
        add_with "$parsed" ;;
      -* )
        # remove with
        parsed=${options#"-"}
        if [ -z "$parsed" ]; then
          drop_with
        else
          for ((x=0; x<$((parsed)); x++)) {
            drop_with
          }
        fi
        pmpt="${prefix[*]}" ;;
      +* )
        # nesting withs
        parsed=${options#"+"}
        add_with "$parsed"
        pmpt="${prefix[*]}" ;;
      :* )
        # shell command
        parsed=${options#":"}
        if [ "$parsed" = "q" ]; then
          exit 0
        fi
        IFS=' ' read -r -a parsed_array <<< "$parsed"
        echo "${parsed_array[@]}" >> /tmp/with_history
        eval "${parsed_array[@]}" ;;
      * )
        # prepend prefix to command
        echo "${prefix[*]} ${options}" >> /tmp/with_history
        eval "${prefix[*]} ${options}"
    esac
  done
}
