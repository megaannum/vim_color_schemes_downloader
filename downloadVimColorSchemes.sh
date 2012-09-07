#!/bin/bash
############################################################################
# downloadVimColorSchemes.sh
#
#   Author: Richard Emberson
#   Version: 1.0
#
#   Download all (many) of the Vim color schemes.
#   Bash script tested only on Fedora Linux.
#   May not work on Cygwin or other Linux systems.
#   For Cygwin, the TARGET_DIR which will have to be changed.
#   In the past I've written bash scripts and have had access to
#     Cygwin platforms for testing. Currently, I do not have such
#     access, so the script will need fixing for Cygwin use.
#   The location of some of the executables used by the script may
#     differ in different Linux distributions. They will have to be
#     adjusted in such cases.
#
############################################################################

declare -r SCRIPT=$(basename $0)
declare -r BIN_DIR=$(cd "$(dirname $0)"; pwd)

if [[ "$(uname)" == CYGWIN* ]]; then
  CYGWIN=true
else
  CYGWIN=false
fi


# default values
declare SEACH_OUT="search.out"
declare TMP_OUT="tmp.out"

declare TARGET_DIR="$HOME/.vim/tmpcolors" 
declare OUT_FILE="OUT" 

declare -i VERBOSE=0

declare -i DOWNLOAD_VIM_RUNTIME_CS=1
declare -i DOWNLOAD_VIM_CS=1
declare -i DOWNLOAD_OTHER_CS=1
declare -i RESOLVE_FILES=1

function usage() {
  echo $1
  cat <<EOF
Usage: $SCRIPT options
  Download color schemes from www.vim.org.
  An attempt is made to remove duplicate versions of the same 
    color scheme.
  Stages:
    Download Vim runtime color scheme files
        These are the cs files bundled with Vim
    Download Vim user contributed color scheme files
        These are cs files created by users and registered at vim.org
        Included in these files are some compilations
    Download other color scheme file compilations
        These are cs file compiliations created by users 
        and are not at vim.org
    Resolve downloaded files
  Options:
   -h --help -\?:      
     Help, print this message.
   -v --verbose :      
     Echo messages to output file $OUT_FILE  
   -o outfile || --outfile outfile:
   -o=outfile || --outfile=outfile:      
     Change verbose output file from default: $OUT_FILE
   -t dir || --targetdir dir:
   -t=dir || --targetdir=dir:      
     Change target download directory from default: $TARGET_DIR
   -nortcs --no_runtime_color_scheme -\?:      
     Do not download Vim runtime color scheme files
   -nocs --no_color_scheme -\?:      
     Do not download Vim color scheme files
   -noocs --no_other_color_scheme -\?:      
     Do not download other color scheme file compilations
   -norf --no_resolve_files -\?:      
     Do not resolve all of the downloaded files
Examples:
./$SCRIPT
./$SCRIPT --help
./$SCRIPT -v
./$SCRIPT -t $HOME/.vim/csdownload
EOF
exit 1
}


# parse options
while [[ $# -gt 0 && "$1" == -* ]]; do
    declare optarg=

    case "$1" in
    -*=*)
        optarg=$(echo "$1" | sed 's/[-_a-zA-Z0-9]*=//')
        ;;
    *)
        optarg=
        ;;
    esac
    case "$1" in
        -h | --help | -\?)
            usage ""
        ;;
        -v | --verbose )
            VERBOSE=1
        ;;
        -o=* | --outfile=*)
            OUT_FILE="$optarg"
        ;;
        -o | --outfile )
            shift
            if [[ $# -eq 0 ]]; then
                usage "Missing verbose output file -o"
            fi
            OUT_FILE="$1"
        ;;
        -t=* | --targetdir=*)
            TARGET_DIR="$optarg"
        ;;
        -t | --target_dir )
            shift
            if [[ $# -eq 0 ]]; then
                usage "Missing target directory -t"
            fi
            TARGET_DIR="$1"
        ;;
        -nortcs | --no_runtime_color_scheme )
            DOWNLOAD_VIM_RUNTIME_CS=0
        ;;
        -nocs | --no_color_scheme )
            DOWNLOAD_VIM_CS=0
        ;;
        -noocs | --no_other_color_scheme )
            DOWNLOAD_OTHER_CS=0
        ;;
        -norf | --no_resolve_files )
            RESOLVE_FILES=0
        ;;
        *)
            usage "Unknown option \"$1\""
        ;;
    esac
    shift
done

# takes no additional arguments
if [[ $# -ne 0 ]]; then
    usage "Bad argument \"$1\""
fi


if [[ ! -d "$TARGET_DIR" ]]; then
  mkdir "$TARGET_DIR"
fi

TMP_DIR="$TARGET_DIR/tmp" 



# uses might have to change these locations
VIM=/bin/vim
UNRAR=/bin/unrar
UNZIP=/bin/unzip
ZCAT=/bin/zcat 
GUNZIP=/bin/gunzip 
TAR=/bin/tar
BZCAT=/bin/bzcat
WGET=/bin/wget
MV=/bin/mv
RM=/bin/rm
CP=/bin/cp
FTP=/bin/ftp

############################################################################
# checkExcutableStatus 
#  Parameters 
#    file  : the file to check
############################################################################
function checkExcutableStatus() {
  local -r file="$1"

  if [[ ! -e "$file" ]]; then
    echo "ERROR: File does not exist: $file"
    exit 1
  elif [[ ! -x "$file" ]]; then
    echo "ERROR: File not executable: $file"
    exit 1
  fi
}

checkExcutableStatus "$VIM"
checkExcutableStatus "$UNRAR"
checkExcutableStatus "$UNZIP"
checkExcutableStatus "$ZCAT"
checkExcutableStatus "$GUNZIP"
checkExcutableStatus "$TAR"
checkExcutableStatus "$BZCAT"
checkExcutableStatus "$WGET"
checkExcutableStatus "$MV"
checkExcutableStatus "$RM"
checkExcutableStatus "$FTP"

# used as a function string return value
declare RVAL=""


############################################################################
# shouldDelete 
#  Parameters 
#    file0  : the first file with path
#    file1  : the second file with path
#
#  Returns: "file1" or "file2" or ""
#
# Rules:
#   If either file does not have a Maintainer or
#     if neither file has a Maintainer
#     then there is no way to determine if they are the same
#       colorscheme (but, possibly different verions) so
#       neither should be deleted.
#   If both Maintainers are identical then
#     if they have versions
#       then the eariler version should be deleted or
#     if they have dates 
#       then the eariler date should be deleted or
#     if their sizes differ
#       then the smaller sized one should be deleted or
#     there is no way to tell a difference and neither is deleted.
#   Break each Maintainer field into parts, 
#   if number of fields, n, is the same and n-1 fields are equal
#       then treat them as identical (above) or
#   if last fields are identical, 
#       then treat them as identical (above) or
#   if each has three fields and the second fields are identical,
#       then treat them as identical (above) or
#   if 5 out of the first 6 lines in each file the same.
#       then treat them as identical (above) or
#   if the last 10 lines in each file are the same.
#       then treat them as identical (above) or
#   then are different and neither should be deleted.
#
############################################################################
function shouldDelete() {
  local -r file0="$1"
  local -r file1="$2"
  RVAL=""
  IFS=$' \t\n'

  # file0 get maintainer
  local m0=$( head -10 "$file0" | grep 'Maintainer:' | sed -e 's/^.*Maintainer:\s*\(.*\)$/\1/' )

  if [[ "$m0" == "" ]]; then
    m0=$( head -10 "$file0" | grep 'Author' | sed -e 's/^.*Author\s*:\s*\(.*\)$/\1/' )
  fi

  if [[ "$m0" == "" ]]; then
    m0=$( head -10 "$file0" | grep 'author' | sed -e 's/^.*author\s*:\s*\(.*\)$/\1/' )
  fi

  # file1 get maintainer
  local m1=$( head -10 "$file1" | grep 'Maintainer:' | sed -e 's/^.*Maintainer:\s*\(.*\)$/\1/' )

  if [[ "$m1" == "" ]]; then
    m1=$( head -10 "$file1" | grep 'Author' | sed -e 's/^.*Author\s*:\s*\(.*\)$/\1/' )
  fi

  if [[ "$m1" == "" ]]; then
    m1=$( head -10 "$file1" | grep 'author' | sed -e 's/^.*author\s*:\s*\(.*\)$/\1/' )
  fi
# echo "m0=$m0"
# echo "m1=$m1"

  # get change date
  local d0=$( head -10 "$file0" | grep 'Last Change:' | sed -e 's/^.*Last Change:.*\(20[0-9][0-9]\).*$/\1/' )
  if [[ "$d0" == "" ]]; then
    d0=$( head -10 "$file0" | grep 'Last Modified:' | sed -e 's/^.*Last Modified:.*\(20[0-9][0-9]\).*$/\1/' )
  fi
  local -a da0=( $( echo $d0) )
  d0=${da0[0]}

  local d1=$( head -10 "$file1" | grep 'Last Change:' | sed -e 's/^.*Last Change:.*\(20[0-9][0-9]\).*$/\1/' )
  if [[ "$d1" == "" ]]; then
    d1=$( head -10 "$file1" | grep 'Last Modified:' | sed -e 's/^.*Last Modified:.*\(20[0-9][0-9]\).*$/\1/' )
  fi
  local -a da1=( $( echo $d1) )
  d1=${da1[0]}
  IFS=$' \t'
# echo "d0=$d0"
# echo "d1=$d1"

  # get version
  local v0=$( head -10 "$file0" | grep 'Version:' | sed -e 's/^.*Version:[ 	]*\([^ 	]*\)[ 	]*$/\1/' )
  if [[ "$v0" == "" ]]; then
    v0=$( head -10 "$file0" | grep 'version' | sed -e 's/^.*version[ 	]*\([^ 	]*\)[ 	]*$/\1/' )
  fi
  if [[ "$v0" == "" ]]; then
    v0=$( head -10 "$file0" | grep ' v[0-9]*\..*$' | sed -e 's/^.*\(v[0-9]*\..*\)$/\1/' )
  fi
  local -a va0=( $( echo $v0) )
  v0=${va0[0]}

  local v1=$( head -10 "$file1" | grep 'Version:' | sed -e 's/^.*Version:[ 	]*\([^ 	]*\)[ 	]*$/\1/' )
  if [[ "$v1" == "" ]]; then
    v1=$( head -10 "$file1" | grep 'version' | sed -e 's/^.*version[ 	]*\([^ 	]*\)[ 	]*$/\1/' )
  fi
  if [[ "$v1" == "" ]]; then
    v1=$( head -10 "$file1" | grep ' v[0-9]*\..*$' | sed -e 's/^.*\(v[0-9]*\..*\)$/\1/' )
  fi
  local -a va1=( $( echo $v1) )
  v1=${va1[0]}
# echo "v0=$v0"
# echo "v1=$v1"

  # get file size
  local -r s0=$( stat -c %s "$file0" )
  local -r s1=$( stat -c %s "$file1" )

  local -i are_equal=0

  # maintainer are identical
  if [[ "$m0" == "$m1" ]] && [[ "$m0" != "" ]]; then
# echo "identical non empty"
    are_equal=1
  else
    # break maintainer field into parts
    if [[ "$m0" != "" ]] && [[ "$m1" != "" ]]; then
      local -a ms0=( $( echo $m0 ) )
      local -a ms1=( $( echo $m1 ) )
      local -r ms0_len=${#ms0[@]}
      local -r ms1_len=${#ms1[@]}
      local -r ms0_last=$(( $ms0_len - 1 ))
      local -r ms1_last=$(( $ms1_len - 1 ))
# echo "ms0_len=$ms0_len"
# echo "ms1_len=$ms1_len"
# echo "ms0_last=$ms0_last"
# echo "ms1_last=$ms1_last"
# echo "ms0[ms0_last]=${ms0[$ms0_last]}"
# echo "ms1[ms1_last]=${ms1[$ms1_last]}"

      # majority of fields equal
      if [[ $ms0_len -eq $ms1_len ]] && [[  $ms0_len -gt 3  ]] ; then
        local -i cnt=0
        local -i end=$(( $ms0_len - 1 ))
        for ((index=0; index <= $end ; index++)); do 
          if [[ ${ms0[$index]} == ${ms1[$index]} ]]; then
	    cnt=$(( cnt + 1 ))
	  fi
        done
        if [[ $cnt -eq $end ]]; then
          are_equal=1
        fi
      fi

      if [[ $are_equal -eq 0 ]]; then
	  # last field equal
	  if [[ "${ms0[$ms0_last]}" == "${ms1[$ms1_last]}" ]]; then
	      are_equal=1
	  elif [[ $ms0_len -ge 3 ]] && [[ $ms1_len -ge 3 ]] && [[ "${ms0[1]}" == "${ms1[1]}" ]]; then
	      # last names equal??
	      are_equal=1
	  fi
      fi
    fi

    # are 5 out of the first 6 lines in each file the same
    if [[ $are_equal -eq 0 ]]; then
	local  -a h0=( $( head -6 "$file0" ) )
	local  -a h1=( $( head -6 "$file1" ) )
	local -i cnt=0
	local -i end=5
	for ((index=0; index <= $end ; index++)); do 
	    if [[ ${h0[$index]} == ${h1[$index]} ]]; then
		cnt=$(( cnt + 1 ))
	    fi
	done
	# if only one line in the first 6 lines is different, 
	# assume the same color scheme modulo version
	if [[ $cnt -ge $end ]]; then
# echo "first lines equal"
	    are_equal=1
	fi
    fi
    # if the last 10 lines in each file are the same.
    if [[ $are_equal -eq 0 ]]; then
	local  -a h0=( $( tail -10 "$file0" ) )
	local  -a h1=( $( tail -10 "$file1" ) )
	local -i cnt=0
	local -i end=9
	for ((index=0; index <= $end ; index++)); do 
	    if [[ ${h0[$index]} == ${h1[$index]} ]]; then
		cnt=$(( cnt + 1 ))
	    fi
	done
	if [[ $cnt -eq 10 ]]; then
# echo "last lines equal"
	    are_equal=1
	fi
    fi
  fi

# echo "are_equal==$are_equal"
  # maintainer are identical
  if [[ $are_equal -eq 1 ]]; then
# echo "are_equal"
    # check versions, delete earlier
    if [[ "$v0" != "" ]] && [[ "$v1" != "" ]]; then
# echo "do version"
      if [[ "$v0" < "$v1" ]]; then
        RVAL="$file0"
      else
        RVAL="$file1"
      fi
    fi
    # check dates, delete older
    if [[ "$RVAL" == "" ]] && [[ "$d0" != "" ]] && [[ "$d1" != "" ]]; then
# echo "do date"
      if [[ "$d0" < "$d1" ]]; then
        RVAL="$file0"
      else
        RVAL="$file1"
      fi
    fi
# echo "s0=$s0"
# echo "s1=$s1"
    # check size, delete smaller
    if [[ "$RVAL" == "" ]]; then
      if [[ $s0 -eq $s1 ]]; then
# echo "do size s0 == s1"
        RVAL="$file1"
      elif [[ $s0 -lt $s1 ]]; then
# echo "do size s0 < s1"
        RVAL="$file0"
      fi
    fi
  fi

  IFS=$' \t'
  return 0
}

# baycomb.vim baycomb_1.vim
# version 2004.0
# derefined.vim derefined_1.vim
# desertedocean v0.2b desertedocean v0.5

#shouldDelete breeze.vim breeze_1.vim
#echo "RVAL=$RVAL"

# These will not match
#   NOTE: silent.vim size > silent_1.vim size
# shouldDelete silent.vim      silent_1.vim      
# echo "RVAL=$RVAL"
# shouldDelete blue.vim blue_1.vim
# echo "RVAL=$RVAL"
# shouldDelete railscasts.vim  railscasts_1.vim  
# echo "RVAL=$RVAL"
# shouldDelete tango.vim tango_1.vim
# echo "RVAL=$RVAL"
# shouldDelete darkblue.vim  darkblue_1.vim  
# echo "RVAL=$RVAL"
# shouldDelete twilight.vim twilight_1.vim
# echo "RVAL=$RVAL"

# These will match
# shouldDelete desertedocean.vim  desertedocean_1.vim  
# echo "RVAL=$RVAL"
# shouldDelete desert.vim         desert_1.vim         
# echo "RVAL=$RVAL"
# shouldDelete torte.vim torte_1.vim
# echo "RVAL=$RVAL"
# shouldDelete delek.vim     delek_1.vim     
# echo "RVAL=$RVAL"
# shouldDelete lingodirector.vim  lingodirector_1.vim  
# echo "RVAL=$RVAL"

# exit

function testShouldDelete() {
    PWD=$( pwd )
    cd "$TARGET_DIR"
    for file in *; do
        case "$file" in
            *_1.vim)
                f1=$file
                f0=$( echo "$f1" | sed -e 's/\(.*\)_1.vim/\1/' )
                f0="${f0}.vim"
                RVAL=""
                shouldDelete "$f0" "$f1"
                echo "$f0 $f1"
                if [[ "$RVAL" == "" ]]; then
                    echo "RVAL=$RVAL"
                fi
                ;;
            *)
                ;;
        esac
    done
    cd $PWD
}
# testShouldDelete


############################################################################
# moveVimFile "file"
#  Assumption: in TMP_DIR
#  Parameters 
#    file  : the file to move
#
# Determine if "file" should be moved to target directory.
# If there is already a file with the same name in the target directory,
# then use shouldDelete to deterime which one or both to save.
#
############################################################################
function moveVimFile() {
  local -r file="$1"
  local -r base=$( basename "$file" )
  local filename=""

if [[ $VERBOSE -eq 1 ]]; then
echo "moveVimFile: file=$file"
echo "moveVimFile: base=$base"
fi
    if [[ -e ../"$base" ]]; then
echo "moveVimFile: EXISTS ../$base"
        diff -q ../"$base" "$file" > /dev/null 2>&1
        status=$?
echo "moveVimFile: status=$status"
        if [[ $status -eq 1 ]]; then

            # files are different
            # file with same name already exists
            # see which one would be kept/deleted
            shouldDelete ../"$base" "$file"
echo "moveVimFile RVAL=$RVAL"
            if [[ "$RVAL" != "" ]]; then
                if [[ "$RVAL" == "../$base" ]]; then
echo "moveVimFile moving "$file""
                    $MV -f "$file" ../"$base"
                fi
            else
                # echo "ERROR: could not move $file"
                filename=$( basename "$base" .vim )
echo "moveVimFile: filename=$filename"
                name1="$filename"_1.vim
echo "moveVimFile: name1=$name1"
                if [[ -e ../"$name1" ]]; then
                    diff -q ../"$name1" "$file" > /dev/null 2>&1
                    status=$?
                    if [[ $status -eq 1 ]]; then

                        # files are different
                        # file with same name already exists
                        # see which one would be kept/deleted
                        shouldDelete ../"$name1" "$file"
echo "moveVimFile RVAL=$RVAL"
                        if [[ "$RVAL" != "" ]]; then
                            if [[ "$RVAL" == "../$name1" ]]; then
echo "moveVimFile moving "$file""
                                $MV -f "$file" ../"$name1"
                            fi
                        else
                            name2="$filename"_2.vim
                            if [[ -e ../"$name2" ]]; then
                                diff -q ../"$name2" "$file" > /dev/null 2>&1
                                status=$?
                                if [[ $status -eq 1 ]]; then
                                    name3="$filename"_3.vim
                                    if [[ -e ../"$name3" ]]; then
                                        diff -q ../"$name3" "$file" > /dev/null 2>&1
                                        status=$?
                                        if [[ $status -eq 1 ]]; then
                                        name4="$filename"_4.vim
                                        if [[ -e ../"$name4" ]]; then
                                            echo "ERROR: could not move $name4"
                                        else
                                            $MV "$file" ../"$name4"
                                        fi
                                        fi
                                    else
                                        $MV "$file" ../"$name3"
                                    fi
                                fi
                            else
# echo "moveVimFile file does not exist: moving $name2"
                                $MV "$file" ../"$name2"
                            fi
                        fi
                    fi
                else
# echo "moveVimFile file does not exist: moving $name1"
                    $MV "$file" ../"$name1"
                fi
            fi
        fi
    else
# echo "moveVimFile file does not exist: moving $file"
        $MV "$file" ../"$base"
    fi
}

############################################################################
# moveVimFiles 
#  Assumption: in TMP_DIR
#  Parameters NONE
#
# Find all files ending in ".vim". Each one that is either a the top 
# directory level, is in a "colors" sub directory or not in one of
# the standard Vim directories (syntax, autoload, plugin, after, indent,
# ftplugin) is a candidate for moving.
#
############################################################################
function moveVimFiles() {
    IFS=$'\n'
    local  -a vimfiles=( $( find . -type f -name "*.vim" ) )
    IFS=$' \t'
    for vimfile in "${vimfiles[@]}" ; do
if [[ $VERBOSE -eq 1 ]]; then
echo "moveVimFiles: file=$vimfile"
fi
        dirpart=$( dirname "$vimfile")
        if [[ "$dirpart" == "." ]]; then
            moveVimFile "$vimfile"
        else
            dirbase=$( basename "$dirpart")
            if [[ "$dirbase" == "colors" ]]; then
                moveVimFile "$vimfile"
            elif [[ "$dirbase" == "syntax" ]]; then
                x=1
            elif [[ "$dirbase" == "autoload" ]]; then
                x=1
            elif [[ "$dirbase" == "plugin" ]]; then
                x=1
            elif [[ "$dirbase" == "after" ]]; then
                x=1
            elif [[ "$dirbase" == "indent" ]]; then
                x=1
            elif [[ "$dirbase" == "ftplugin" ]]; then
                x=1
            else
                moveVimFile "$vimfile"
            fi
        fi
    done
}

############################################################################
# handleVba 
#  Parameters 
#    file  : the vba file
#
# Unpack a VBA file and move contents to target directory.
#
############################################################################
function handleVba() {
    local -r file="$1"
    mkdir "$TMP_DIR"
    cd "$TMP_DIR"
    $MV ../"$file" .

    $VIM -c "UseVimball $TMP_DIR" -c q "$file"

    moveVimFiles
    cd ..
    $RM -rf "$TMP_DIR"
}

############################################################################
# handleVbaGz 
#  Parameters 
#    file  : the vba gzip file
#
# Unpack a ZIP+VBA file and move contents to target directory.
#
############################################################################
function handleVbaGz() {
    local -r file="$1"
    mkdir "$TMP_DIR"
    cd "$TMP_DIR"
    $MV ../"$file" .

    $GUNZIP "$file" 
    local -r base=$( basename "$file" .gz )
    $VIM -c "UseVimball $TMP_DIR" -c q "$base"

    moveVimFiles
    cd ..
    $RM -rf "$TMP_DIR"
}

############################################################################
# handleRar
#  Parameters 
#    file  : the rar file
#
# Unpack a RAR file and move contents to target directory.
#
############################################################################
function handleRar() {
    local -r file="$1"
    mkdir "$TMP_DIR"
    cd "$TMP_DIR"
    $MV ../"$file" .

    $UNRAR e "$file" > /dev/null 2>&1

    moveVimFiles
    cd ..
    $RM -rf "$TMP_DIR"
}

############################################################################
# handleZip
#  Parameters 
#    file  : the zip file
#
# Unpack a ZIP file and move contents to target directory.
#
############################################################################
function handleZip() {
    local -r file="$1"
    mkdir "$TMP_DIR"
    cd "$TMP_DIR"
    $MV ../"$file" .

    $UNZIP "$file" > /dev/null 2>&1

    moveVimFiles
    cd ..
    $RM -rf "$TMP_DIR"
}

############################################################################
# handleTarGz
#  Parameters 
#    file  : the tar gnzip file
#
# Unpack a ZIP+TAR file and move contents to target directory.
#
############################################################################
function handleTarGz() {
    local -r file="$1"
    mkdir "$TMP_DIR"
    cd "$TMP_DIR"
    $MV ../"$file" .

    $ZCAT "$file" | $TAR -xf - > /dev/null 2>&1

    moveVimFiles
    cd ..
    $RM -rf "$TMP_DIR"
}

############################################################################
# handleTarBzip
#  Parameters 
#    file  : the tar bzip file
#
# Unpack a BZIP+TAR file and move contents to target directory.
#
############################################################################
function handleTarBzip() {
    local -r file="$1"
    mkdir "$TMP_DIR"
    cd "$TMP_DIR"
    $MV ../"$file" .

    $BZCAT "$file" | $TAR -xf - > /dev/null 2>&1


    moveVimFiles
    cd ..
    $RM -rf "$TMP_DIR"
}

############################################################################
# resolveFiles
#  Parameters NONE
#
# For each file in target directory, if the file is not a *.vim (color scheme)
#   file, then apply actions based upon the file's packaging and then
#   move content files to target directory.
#
############################################################################
function resolveFiles() {
  local -r pwd=$( pwd )
  cd "$TARGET_DIR"

  for file in *; do
if [[ $VERBOSE -eq 1 ]]; then
echo "resolveFiles: file=$file"
fi
    case "$file" in
        *.vim)
            # This script is really cool, but its not a color scheme,
            # rather, it will change your colors based upon time of day.
            if [[ "$file" == "daytimecolorer.vim" ]]; then
                $RM "$file"
            fi
            ;;
        tmp)
            ;;
        *.tar.gz)
            handleTarGz "$file"
            ;;
        *.tgz)
            handleTarGz "$file"
            ;;
        *.tbz2)
            handleTarBzip "$file"
            ;;
        *.zip)
            handleZip "$file"
            ;;
        *.vba)
            handleVba "$file"
            ;;
        *.vba.gz)
            handleVbaGz "$file"
            ;;
        *.rar)
            # username ChianRen added lyj--- entries in 2003
            # and there are later versions for all such color schemes
            # so I filter out his collection, sorry.
            # http://www.vim.org/scripts/script.php?script_id=1498
            if [[ "$file" != "all_colors.rar" ]]; then
                handleRar "$file"
            else
                $RM "$file"
            fi
            ;;
        _vimrc)
            $RM -f $file
            ;;
        oh-l_l_vim)
            $MV -f oh-l_l_vim oh-l_l.vim
            ;;
        white.txt)
            $MV white.txt white_1.vim
            ;;
        *)
            echo "ERROR can not resolve file=$file"
            ;;
    esac
  done

  for file in *; do
    dos2unix "$file"  > /dev/null 2>&1
  done

  cd $pwd
}

function lastCleanup() {
  local -r pwd=$( pwd )
  cd "$TARGET_DIR"

  for file in *; do
    case "$file" in
        *_1.vim)
            base=$( basename "$file" _1.vim)
            if [[ -e $base.vim ]]; then
              shouldDelete $base.vim $file
              if [[ "$RVAL" != "" ]]; then
#echo "$file   $base.vim"
#echo "RVAL=$RVAL"
                $RM -rf "$file"
              fi
            fi
        ;;
        *.vim)
        ;;
        *)
            echo "ERROR can not cleanup file=$file"
        ;;
    esac
  done

  cd $pwd
}



############################################################################
# downloadVimRuntimeColorSchemes
#  Parameters NONE
#
# This does an ftp to get the current set of Vim Runtime color schemes
#  from ftp://ftp.nluug.nl/ftp/pub/vim/runtime/colors/.
#
############################################################################
function downloadVimRuntimeColorSchemes() {
  local -r pwd=$( pwd )
  cd "$TARGET_DIR"

$FTP -in ftp.nluug.nl  << SCRIPTEND
user "anonymous" "\n"
binary
cd /ftp/pub/vim/runtime/colors/
mget *.vim
bye
SCRIPTEND

  cd $pwd
}

############################################################################
# getColorSchemeIds
#  Parameters NONE
#
# Perform search at vim.org for all color scheme ids and store resulting
#   html in file $SEARCH_OUT.
#
############################################################################
function getColorSchemeIds() {
  local -i success=0
  for ((attempts=0; attempts <= 5 ; attempts++)); do 
# echo "getColorSchemeIds: attempts=$attempts"
    $WGET -O $SEACH_OUT 'http://www.vim.org/scripts/script_search_results.php?&script_type=color%20scheme&show_me=1500'
    if [[ $? -eq 0 ]]; then
      success=1
      break;
    fi
    sleep $attempts
  done
# echo "getColorSchemeIds: success=$success"
  if [[ $success -ne 1 ]]; then
    echo "ERROR: could not download color scheme search"
  fi
}


############################################################################
# extractScriptIds
#  Parameters NONE
#
# Find all of the "script_id" lines in the file $SEARCH_OUT and then
#   extract the associated ids into an array.
# For each "script_id" there are two "pairs" of entries so loop through
#   array taking only odd entries and place them in another array.
# Return the new array.
#
############################################################################
function extractScriptIds() {
    IFS=$'\n'
    local -a idsp=( $( grep script_id $SEACH_OUT | sed -e 's/.*script_id=\([^"]*\)">.*/\1/' ) )
    IFS=$' \t'

    local -a ids
    local -i cnt=0
    local dowrite=1
    for p in "${idsp[@]}" ; do
        if (( $dowrite == 1 )) ; then
            # echo "PAIR=$p"
            # NOTE: this hack is here because script 4099 uses non-ascii
            # characters in its name and throws off the above sed script
            # When there are more than 9999 scripts, this code will prevent
            # scripts with ids > 9999 from being downloaded
            # A better long-term fix is welcome.
            if [[ ${#p} -gt 4 ]]; then
                ids[$cnt]="${p:0:4}"
            else
                ids[$cnt]="$p"
            fi
            cnt=$(( $cnt + 1 ))
            dowrite=0
        else
            dowrite=1
        fi
    done

    echo "${ids[@]}"
}
# declare -a ids=( extractScriptIds )
# /bin/rm -f $SEACH_OUT

# DEBUG print out is
function debug1() {
    for p in "${ids[@]}" ; do
        echo "id=$p"
    done
}

############################################################################
# downloadColorSchemeFile
#  Parameters
#    id       : script id
#    filename : name of file to place download
#
# Download a Vim script using its "id" into file "filename".
#
############################################################################
function downloadColorSchemeFile() {
  local -r id="$1"
  local filename="$2"
  mkdir "$TMP_DIR"
  cd "$TMP_DIR"

# echo "downloadColorSchemeFile: id=$id   filename=$filename"

  local -i success=0
  for ((attempts=0; attempts <= 5 ; attempts++)); do 
    $WGET -O "$TMP_DIR/$filename" 'http://www.vim.org/scripts/download_script.php?src_id='$id
    if [[ $? -eq 0 ]]; then
      success=1
      break;
    fi
    sleep $attempts
  done
  if [[ $success -ne 1 ]]; then
    echo "ERROR: could not download color scheme id=$id, filename=$filename"
  else
    if [[ ! -e "$TARGET_DIR/$filename" ]]; then
# echo "downloadColorSchemeFile: new file: $filename"
      $MV -f "$TMP_DIR/$filename" "$TARGET_DIR"
    else
# echo "downloadColorSchemeFile: moveVimFile: $filename"
      moveVimFile "$filename"
    fi
  fi

  cd ..
  $RM -rf "$TMP_DIR"
}

############################################################################
# downloadColorSchemeFiles
#  Parameters
#    page_ids  : array of color schema script page ids
#
# Download all Vim scripts using array of script page ids.
#
############################################################################
function downloadColorSchemeFiles() {
    local -a page_ids=( "${@}" )
    # id value/name pairs
    local -a vn_pairs
    local -i success=0

    # download each schema page and then download 
    # first (latest) color scheme file
    for page_id in "${page_ids[@]}" ; do
    
# echo "downloadColorSchemeFiles: page_id=$page_id"
      success=0
      for ((attempts=0; attempts <= 5 ; attempts++)); do 
        $WGET -O $TMP_OUT 'http://www.vim.org/scripts/script.php?script_id='$page_id
        if [[ $? -eq 0 ]]; then
          success=1
          break;
        fi
        sleep $attempts
      done
      if [[ $success -ne 1 ]]; then
        echo "ERROR: could not download color scheme page_id=$page_id"
      else
        IFS=$'\n'
        # id value/name pair
        vn_pairs=( $( grep download_script $TMP_OUT | sed -e 's/.*src_id=\([^"]*\)">\([^<]*\)<.*/\1 \2/' ) )
# echo "vn_pair[0]=${vn_pairs[0]}"
        # IFS=' '
        IFS=$' \t'

# echo "vn_pairs=${vn_pairs[@]}"
        local -i end=$(( ${#vn_pairs[@]} - 1 ))
        for ((index=0; index <= $end ; index++)); do 
# echo "index=$index"
          local xx=${vn_pairs[$index]}
# echo "xx=$xx"
          # local -a vn_pair=( ${vn_pairs[$index]} )
          local -a vn_pair=( $xx )
# echo "vn_pair=${vn_pair[@]}"
          # echo "pair0=${vn_pair[0]}"
          # echo "pair1=${vn_pair[1]}"

          # script id 
          id=${vn_pair[0]}
          # script name 
          name=${vn_pair[1]}
          case "$name" in
            *.png)
            ;;
            *)
              name=$( echo $name | tr -d "[' ]" | tr '[:upper:]' '[:lower:]' )
              downloadColorSchemeFile "$id" "$name"
              break
            ;;
          esac
        done
      fi
    done
}

############################################################################
# downloadVimColorSchemes
#  Parameters: NONE
#
# Download all files from www.vim.org which are "color scheme" files.
#
############################################################################
function downloadVimColorSchemes() {

# echo "downloadVimColorSchemes: Get Color Scheme Ids"
    getColorSchemeIds

# echo "downloadVimColorSchemes: Extract Script Ids"
    local -a ids=( $(extractScriptIds) )

# echo "downloadVimColorSchemes: ids=${ids[@]}"
    # debug
    #for p in "${ids[@]}" ; do
    #    echo "id=$p"
    #done

# echo "downloadVimColorSchemes: Download Color Scheme Files"
    downloadColorSchemeFiles "${ids[@]}"
}

############################################################################
# downloadOtherColorSchemes
#  Parameters: NONE
#
# Download compilations from other sources.
#
############################################################################
function downloadOtherColorSchemes() {
  local -r pwd=$( pwd )
  cd "$TARGET_DIR"

  # https://github.com/flazz/vim-colorschemes/
  outfile="flazz-vim-colorschemes.zip"
  local -i success=0
  for ((attempts=0; attempts <= 5 ; attempts++)); do 
    $WGET -O $outfile 'https://github.com/flazz/vim-colorschemes/zipball/master'
    if [[ $? -eq 0 ]]; then
      success=1
      break;
    fi
    sleep $attempts
  done
  if [[ $success -ne 1 ]]; then
    echo "ERROR: could not download color scheme compilation: flazz-vim-colorschemes.zip"
  fi

  cd $pwd
}

############################################################################
# mainDriver
#  Parameters: NONE
#
# Drives the downloading of color scheme files
#
############################################################################
function mainDriver() {

if [[ $VERBOSE -eq 1 ]]; then
echo "mainDriver: Download Vim Runtime Color Schemes"
fi
    if [[ $DOWNLOAD_VIM_RUNTIME_CS -eq 1 ]]; then
        downloadVimRuntimeColorSchemes
    fi

if [[ $VERBOSE -eq 1 ]]; then
echo "mainDriver: Download Vim Color Schemes"
fi
    if [[ $DOWNLOAD_VIM_CS -eq 1 ]]; then
        downloadVimColorSchemes
    fi

if [[ $VERBOSE -eq 1 ]]; then
echo "mainDriver: Download Other Color Schemes"
fi
    if [[ $DOWNLOAD_OTHER_CS -eq 1 ]]; then
        downloadOtherColorSchemes
    fi

if [[ $VERBOSE -eq 1 ]]; then
echo "mainDriver: Resolve Files"
fi
    if [[ $RESOLVE_FILES -eq 1 ]]; then
        resolveFiles
        lastCleanup
    fi


    #######################
    # cleanup
    #######################
    /bin/rm -f "$SEACH_OUT"
    /bin/rm -f "$TMP_OUT"

if [[ $VERBOSE -eq 1 ]]; then
echo "mainDriver: Finished"
fi
    return
}

mainDriver

function test1() {
if [[ ! -d "$TMP_DIR" ]]; then
  mkdir "$TMP_DIR"
fi
cd "$TMP_DIR"
moveVimFile delek.vim
cd ~/.vim
}

exit 0

