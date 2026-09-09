#!/usr/bin/env zsh

# Types a command line into a real interactive zsh and prints what TAB offered.
# zsh completes only under a terminal, so the shell runs on a pseudo-terminal;
# nothing short of that exercises the snippet the way a reader will.
#
# $1 is the line to type. $HOME must hold a .zshrc that sources the snippet, and
# legu must be on PATH under its own name.

setopt extendedglob
set -e
zmodload zsh/zpty

die() { print -u2 -- "complete_in_zsh: $1"; exit 1 }

zpty legu-completion 'zsh -i' || die "could not start zsh on a pseudo-terminal"
# .zshrc runs before the first keystroke lands, so without this wait the reads
# below would catch a prompt drawn before the snippet was sourced.
sleep 2
while zpty -r -t legu-completion discard; do : ; done

zpty -w -n legu-completion "$1"$'\t'
sleep 3

typeset offered=''
while zpty -r -t legu-completion chunk; do offered+=$chunk; done
zpty -d legu-completion

# The candidates reach the terminal wrapped in cursor movement.
typeset painted=${offered//$'\e'\[[0-9;?]#[a-zA-Z]/}

# Nothing came back at all: zsh never started, or never drew the line. Saying so
# here keeps a silent exit 0 from reading as "completion offered nothing".
[[ -n ${painted//[[:space:]]/} ]] || die "zsh painted nothing for: $1"

print -r -- $painted
