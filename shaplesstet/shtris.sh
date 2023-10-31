
set -u # non initialized variable is an error
set -f # disable pathname expansion

# game versioin
# should follow "Semantic Versioning 2.0.0" <https://semver.org/>
# so that users have a clear indicator of when an upgrade will introduce breaking changes.
VERSION='3.0.0'

# program name
PROG=${0##*/}

# Explicitly reset to the default value to prevent the import of IFS
# from the environment. The following shells will work more safely.
#   dash <= 0.5.10.2, FreeBSD sh <= 10.4, etc.
IFS=$(printf '\n\t') && SP=' ' TAB=${IFS#?} LF=${IFS%?} && IFS=" ${TAB}${LF}"

# Force POSIX mode if available
( set -o posix ) 2>/dev/null && set -o posix
if [ "${ZSH_VERSION:-}" ]; then
  IFS="$IFS"$'\0'    # Default IFS value for zsh.
  emulate -R sh      # Required for zsh support.
fi

# Some ancient shells have an issue with empty position parameter references.
# There is a well-known workaround for this, ${1+"$@"}, but it is
# easy to miss and cumbersome to deal with, we disable nounset (set -u).
#
# What does ${1+"$@"} mean
# ref: <https://www.in-ulm.de/~mascheck/various/bourne_args/>
(set --; : "$@") 2>/dev/null || set +u

# NOTICE: alias is FAKE.
#   This is only used to make the local variables stand out.
#   Since ksh does not support local, local will be ignored by all shells
if [ -z "${POSH_VERSION:-}" ]; then # alias is not implemented in posh.
  alias local=""
fi

# Log file to be written for debug.
# the contents in the file will not be deleted,
# but always written in appending.
LOG='.log'

# these signals are used for communicating with each process(i.e. reader, timer, ticker, controller).
# Note:
#   in shell enviroment, should Drop the SIG prefix, just input the signal name.
SIGNAL_TERM=TERM
SIGNAL_INT=INT
SIGNAL_STOP=STOP
SIGNAL_CONT=CONT
SIGNAL_LEVEL_UP=USR1
SIGNAL_RESET_LEVEL=USR2
SIGNAL_RESTART_LOCKDOWN_TIMER=USR1
SIGNAL_RELEASE_INPUT=USR1
SIGNAL_CAPTURE_INPUT=USR2

# Those are commands sent to controller by key press processing code
# In controller they are used as index to retrieve actual function from array
QUIT=0
RIGHT=1
LEFT=2
FALL=3
SOFT_DROP=4
HARD_DROP=5
ROTATE_CW=6
ROTATE_CCW=7
HOLD=8
TOGGLE_BEEP=9
TOGGLE_COLOR=10
TOGGLE_HELP=11
REFRESH_SCREEN=12
LOCKDOWN=13
PAUSE=14
NOTIFY_PID=15
