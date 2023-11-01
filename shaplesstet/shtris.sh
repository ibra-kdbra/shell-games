
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

PROCESS_CONTROLLER=0
PROCESS_TICKER=1
PROCESS_TIMER=2
PROCESS_READER=3
PROCESS_INKEY=4

# The normal Fall Speed is defined here to be the time it takes a Tetrimino to fall by one line.
# The current level of the game determines the normal Fall Speed using the following equation:
# (0.8 - ((level - 1) * 0.007))^(level-1)
FALL_SPEED_LEVEL_1=1
FALL_SPEED_LEVEL_2=0.793
FALL_SPEED_LEVEL_3=0.618
FALL_SPEED_LEVEL_4=0.473
FALL_SPEED_LEVEL_5=0.355
FALL_SPEED_LEVEL_6=0.262
FALL_SPEED_LEVEL_7=0.190
FALL_SPEED_LEVEL_8=0.135
FALL_SPEED_LEVEL_9=0.094
FALL_SPEED_LEVEL_10=0.064
FALL_SPEED_LEVEL_11=0.043
FALL_SPEED_LEVEL_12=0.028
FALL_SPEED_LEVEL_13=0.018
FALL_SPEED_LEVEL_14=0.011
FALL_SPEED_LEVEL_15=0.007
LEVEL_MAX=15

# Those are Tetrimino type (and empty)
EMPTY=0
O_TETRIMINO=1
I_TETRIMINO=2
T_TETRIMINO=3
L_TETRIMINO=4
J_TETRIMINO=5
S_TETRIMINO=6
Z_TETRIMINO=7

# Those are the facing
# Tetrimino has four facings
NORTH=0
EAST=1
SOUTH=2
WEST=3

ACTION_NONE=0
ACTION_SINGLE=1
ACTION_DOUBLE=2
ACTION_TRIPLE=3
ACTION_TETRIS=4
ACTION_SOFT_DROP=5
ACTION_HARD_DROP=6
ACTION_TSPIN=7
ACTION_TSPIN_SINGLE=8
ACTION_TSPIN_DOUBLE=9
ACTION_TSPIN_TRIPLE=10
ACTION_MINI_TSPIN=11
ACTION_MINI_TSPIN_SINGLE=12
ACTION_MINI_TSPIN_DOUBLE=13

eval SCORE_FACTOR_"$ACTION_NONE"=0
eval SCORE_FACTOR_"$ACTION_SINGLE"=100
eval SCORE_FACTOR_"$ACTION_DOUBLE"=300
eval SCORE_FACTOR_"$ACTION_TRIPLE"=500
eval SCORE_FACTOR_"$ACTION_TETRIS"=800
eval SCORE_FACTOR_"$ACTION_TSPIN"=400
eval SCORE_FACTOR_"$ACTION_TSPIN_SINGLE"=800
eval SCORE_FACTOR_"$ACTION_TSPIN_DOUBLE"=1200
eval SCORE_FACTOR_"$ACTION_TSPIN_TRIPLE"=1600
eval SCORE_FACTOR_"$ACTION_MINI_TSPIN"=100
eval SCORE_FACTOR_"$ACTION_MINI_TSPIN_SINGLE"=200
eval SCORE_FACTOR_"$ACTION_MINI_TSPIN_DOUBLE"=300
eval SCORE_FACTOR_"$ACTION_SOFT_DROP"=1
eval SCORE_FACTOR_"$ACTION_HARD_DROP"=2
SCORE_FACTOR_COMBO=50
SCORE_FACTOR_SINGLE_LINE_PERFECT_CLEAR=800
SCORE_FACTOR_DOUBLE_LINE_PERFECT_CLEAR=1200
SCORE_FACTOR_TRIPLE_LINE_PERFECT_CLEAR=1800
SCORE_FACTOR_TETRIS_PERFECT_CLEAR=2000


# A Tetrimino that is Hard Dropped Locks Down immediately. However, if a Tetrimino naturally falls
# or Soft Drops onto a Surface, it is given 0.5 seconds on a Lock Down Timer before it actually
# Locks Down. Three rulesets -Infinite Placement, Extended, and Classic- dictate the conditions
# for Lock Down. The default is Extended Placement.
#
# Extended Placement Lock Down
#   This is the default Lock Down setting.
#   Once the Tetrimino in play lands on a Surface in the Matrix, the Lock Down Timer starts counting
#   down from 0.5 seconds. Once it hits zero, the Tetrimino Locks Down and the Next Tetrimino's
#   generation phase starts. The Lock Down Timer resets to 0.5 seconds if the player simply moves
#   or rotates the Tetrimino. In Extended Placement, a Tetrimino gets 15 left/right movements or
#   rotations before it Locks Down, regardless of the time left on the Lock Down Timer. However, if
#   the Tetrimino falls one row below the lowest row yet reached, this counter is reset. In all other
#   cases, it is not reset.
#
# Infinite Placement Lock Down
#   Once the Tetrimino in play lands on a Surface in the Matrix, the Lock Down Timer starts counting
#   down from 0.5 seconds. Once it hits zero, the Tetrimino Locks Down and the Next Tetrimino's
#   generation phase starts. However, the Lock Down Timer resets to 0.5 seconds if the player simply
#   moves or rotates the Tetrimino. Thus, Infinite Placement allows the player to continue movement
#   and rotation of a Tetrimino as long as there is an actual change in its position or orientation
#   before the timer expires.
#
# Classic Lock Down
#   Classic Lock Down rules apply if Infinite Placement and Extended Placement are turned off.
#   Like Infinite Placement, the Lock Down Timer starts counting down from 0.5 seconds once the
#   Tetrimino in play lands on a Surface. The y-coordinate of the Tetrimino must decrease (i.e., the
#   Tetrimino falls further down in the Matrix) in order for the timer to be reset.


LOCKDOWN_RULE_EXTENDED=0
LOCKDOWN_RULE_INFINITE=1
LOCKDOWN_RULE_CLASSIC=2
LOCKDOWN_ALLOWED_MANIPULATIONS=15

# Location and size of playfield and border
PLAYFIELD_W=10
PLAYFIELD_H=20
PLAYFIELD_X=18
PLAYFIELD_Y=2

# Location of error logs
ERRLOG_Y=$((PLAYFIELD_Y + PLAYFIELD_H + 2))

# Location of score information
SCORE_X=3
SCORE_Y=6

# Location of help information
HELP_X=52
HELP_Y=8

# Next piece location
NEXT_X=41
NEXT_Y=2
NEXT_MAX=7

# Hold piece location
HOLD_X=7
HOLD_Y=2

# Location of center of play field
CENTER_X=$((PLAYFIELD_X + PLAYFIELD_W)) # 1 width equals 2 character
CENTER_Y=$((PLAYFIELD_Y + PLAYFIELD_H / 2 - 1))
