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

function usage() {
  echo $1
  cat <<EOF
Usage: $SCRIPT options
  Download color schemes from www.vim.org.
  An attempt is made to remove duplicate versions of the same 
    color scheme.
  Options:
   -h --help -\?:      
     Help, print this message.
Examples:
./$SCRIPT
./$SCRIPT --help
EOF
exit 1
}

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
        -*)
            usage "Unknown option \"$1\""
        ;;
    esac
    shift
done


# uses might have to change these locations
VIM=/bin/vim
UNRAR=/bin/unrar
UNZIP=/bin/unzip
ZCAT=/bin/zcat 
UNZIP=/bin/gunzip 
TAR=/bin/tar
BZCAT=/bin/bzcat
WGET=/bin/wget
MV=/bin/mv
RM=/bin/rm

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
checkExcutableStatus "$UNZIP"
checkExcutableStatus "$TAR"
checkExcutableStatus "$BZCAT"
checkExcutableStatus "$WGET"
checkExcutableStatus "$MV"
checkExcutableStatus "$RM"

declare RVAL=""

SEACH_OUT="search.out"
TMP_OUT="tmp.out"

TARGET_DIR="$HOME/.vim/tmpcolors" 
if [[ ! -d $TARGET_DIR ]]; then
  mkdir $TARGET_DIR
fi

TMP_DIR="$TARGET_DIR/tmp" 

############################################################################
# shouldDelete 
#  Parameters 
#    file0  : the first file
#    file1  : the second file
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
  IFS=$' \t'

  local -r pwd=$( pwd )
  cd $TARGET_DIR

  # file0 get maintainer
  local m0=$( head -10 "$file0" | grep 'Maintainer:' | sed -e 's/^.*Maintainer:\s*\(.*\)$/\1/' )

  if [[ "$m0" == "" ]]; then
    m0=$( head -10 "$file0" | grep 'Author' | sed -e 's/^.*Author\s*:\s*\(.*\)$/\1/' )
  fi

  if [[ "$m0" == "" ]]; then
    m0=$( head -10 "$file0" | grep 'author' | sed -e 's/^.*author\s*:\s*\(.*\)$/\1/' )
  fi
# echo "m0=$m0"

  # file1 get maintainer
  local m1=$( head -10 "$file1" | grep 'Maintainer:' | sed -e 's/^.*Maintainer:\s*\(.*\)$/\1/' )

  if [[ "$m1" == "" ]]; then
    m1=$( head -10 "$file1" | grep 'Author' | sed -e 's/^.*Author\s*:\s*\(.*\)$/\1/' )
  fi

  if [[ "$m1" == "" ]]; then
    m1=$( head -10 "$file1" | grep 'author' | sed -e 's/^.*author\s*:\s*\(.*\)$/\1/' )
  fi
# echo "m1=$m1"

  # get change date
  local d0=$( head -10 "$file0" | grep 'Last Change:' | sed -e 's/^.*Last Change:.*\(20[0-9][0-9]\).*$/\1/' )
  if [[ "$d0" == "" ]]; then
    d0=$( head -10 "$file0" | grep 'Last Modified:' | sed -e 's/^.*Last Modified:.*\(20[0-9][0-9]\).*$/\1/' )
  fi
  local d1=$( head -10 "$file1" | grep 'Last Change:' | sed -e 's/^.*Last Change:.*\(20[0-9][0-9]\).*$/\1/' )
  if [[ "$d1" == "" ]]; then
    d1=$( head -10 "$file1" | grep 'Last Modified:' | sed -e 's/^.*Last Modified:.*\(20[0-9][0-9]\).*$/\1/' )
  fi

  # get version
  local v0=$( head -10 "$file0" | grep 'Version:' | sed -e 's/^.*Version:[ 	]*\([^ 	]*\)[ 	]*$/\1/' )
  if [[ "$v0" == "" ]]; then
    v0=$( head -10 "$file0" | grep 'version' | sed -e 's/^.*version[ 	]*\([^ 	]*\)[ 	]*$/\1/' )
  fi
  local v1=$( head -10 "$file1" | grep 'Version:' | sed -e 's/^.*Version:[ 	]*\([^ 	]*\)[ 	]*$/\1/' )
  if [[ "$v1" == "" ]]; then
    v1=$( head -10 "$file1" | grep 'version' | sed -e 's/^.*version[ 	]*\([^ 	]*\)[ 	]*$/\1/' )
  fi

  # get file size
  local -r s0=$( stat -c %s "$file0" )
  local -r s1=$( stat -c %s "$file1" )

  local -i are_equal=0

  # maintainer are identical
  if [[ "$m0" == "$m1" ]] && [[ "$m0" != "" ]]; then
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
      if [[ "$v0" < "$v1" ]]; then
        RVAL="$file0"
      else
        RVAL="$file1"
      fi
    fi
    # check dates, delete older
    if [[ "$d0" != "" ]] && [[ "$d1" != "" ]]; then
      if [[ "$d0" < "$d1" ]]; then
        RVAL="$file0"
      else
        RVAL="$file1"
      fi
    fi
# echo "s0=$s0"
# echo "s1=$s1"
    # check size, delete smaller
    if [[ $s0 -le $s1 ]]; then
      RVAL="$file0"
    fi
  fi

  cd $pwd
  return 0
}

# baycomb.vim baycomb_1.vim
# version 2004.0
# derefined.vim derefined_1.vim

#shouldDelete darkdot.vim darkdot_1.vim
#echo "RVAL=$RVAL"
#shouldDelete Dark.vim Dark_1.vim
#echo "RVAL=$RVAL"
# shouldDelete blackdust.vim blackdust_1.vim
# echo "RVAL=$RVAL"
# shouldDelete buttercream.vim buttercream_1.vim
# echo "RVAL=$RVAL"
#shouldDelete aiseered.vim aiseered_1.vim
#echo "RVAL=$RVAL"
# shouldDelete white.vim white_1.vim 
# echo "RVAL=$RVAL"
# echo "shouldDelete billw.vim billw_1.vim"
# shouldDelete billw.vim billw_1.vim 
# echo "RVAL=$RVAL"
# shouldDelete zen.vim zen_1.vim
# echo "RVAL=$RVAL"
# shouldDelete adam.vim adam_1.vim
# echo "RVAL=$RVAL"
# shouldDelete adaryn.vim adaryn_1.vim
# echo "RVAL=$RVAL"


function testShouldDelete() {
    PWD=$( pwd )
    cd $TARGET_DIR
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

    if [[ -e ../"$base" ]]; then
        diff -q ../"$base" "$file" > /dev/null 2>&1
        status=$?
        if [[ $status -eq 1 ]]; then
            # echo "ERROR: could not move $file"
            filename=$( basename "$base" .vim )
            name1="$filename"_1.vim
            if [[ -e ../"$name1" ]]; then
                diff -q ../"$name1" "$file" > /dev/null 2>&1
                status=$?
                if [[ $status -eq 1 ]]; then
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
                        $MV "$file" ../"$name2"
                    fi
                fi
            else
                $MV "$file" ../"$name1"
            fi
        fi
    else
        # echo "moving $file"
        $MV "$file" ..
    fi
}

############################################################################
# moveVimFiles 
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
    cd $TMP_DIR
    $MV ../"$file" .

    $VIM -c "UseVimball $TMP_DIR" -c q "$file"

    moveVimFiles
    cd ..
    $RM -rf $TMP_DIR
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
    cd $TMP_DIR
    $MV ../"$file" .

    $UNZIP "$file" 
    local -r base=$( basename "$file" .gz )
    $VIM -c "UseVimball $TMP_DIR" -c q "$base"

    moveVimFiles
    cd ..
    $RM -rf $TMP_DIR
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
    cd $TMP_DIR
    $MV ../"$file" .

    $UNRAR e "$file" > /dev/null 2>&1

    moveVimFiles
    cd ..
    $RM -rf $TMP_DIR
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
    mkdir $TMP_DIR
    cd $TMP_DIR
    $MV ../"$file" .

    $UNZIP "$file" > /dev/null 2>&1

    moveVimFiles
    cd ..
    $RM -rf $TMP_DIR
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
    mkdir $TMP_DIR
    cd $TMP_DIR
    $MV ../"$file" .

    $ZCAT "$file" | $TAR -xf - > /dev/null 2>&1

    moveVimFiles
    cd ..
    $RM -rf $TMP_DIR
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
    mkdir $TMP_DIR
    cd $TMP_DIR
    $MV ../"$file" .

    $BZCAT "$file" | $TAR -xf - > /dev/null 2>&1


    moveVimFiles
    cd ..
    $RM -rf $TMP_DIR
}

############################################################################
# fixFiles
#  Parameters NONE
#
# For each file in target directory, if the file is not a *.vim (color scheme)
#   file, then apply actions based upon the file's packaging and then
#   move content files to target directory.
#
############################################################################
function fixFiles() {
  local -r pwd=$( pwd )
  cd $TARGET_DIR

  for file in *; do
    case "$file" in
        *.vim)
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
                $RM -f "$file"
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
            echo "ERROR file=$file"
            ;;
    esac
  done

  for file in *; do
    dos2unix "$file"  > /dev/null 2>&1
  done

  cd $pwd
}

# fixFiles


############################################################################
# getColorSchemeIds
#  Parameters NONE
#
# Perform search at vim.org for all color scheme ids and store resulting
#   html in file $SEARCH_OUT.
#
############################################################################
function getColorSchemeIds() {
    $WGET -O $SEACH_OUT 'http://www.vim.org/scripts/script_search_results.php?&script_type=color%20scheme&show_me=1500'
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
  local -r filename="$2"

echo "downloadColorSchemeFile: id=$id   filename=$filename"

  $WGET -O $TARGET_DIR/"$filename" 'http://www.vim.org/scripts/download_script.php?src_id='$id
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

    # download each schema page and then download 
    # first (latest) color scheme file
    for page_id in "${page_ids[@]}" ; do
    
# echo "downloadColorSchemeFiles: page_id=$page_id"
        $WGET -O $TMP_OUT 'http://www.vim.org/scripts/script.php?script_id='$page_id
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
    done
}

############################################################################
# maintainer
#  Parameters: NONE
#
# Drives the downloading of color scheme files
#
############################################################################
function mainDriver() {

echo "mainDriver: Get Color Scheme Ids"
    getColorSchemeIds

echo "mainDriver: Extract Script Ids"
    local -a ids=( $(extractScriptIds) )

# echo "mainDriver: ids=${ids[@]}"
    # debug
    #for p in "${ids[@]}" ; do
    #    echo "id=$p"
    #done

echo "mainDriver: MID"

echo "mainDriver: Download Color Scheme Files"
    downloadColorSchemeFiles "${ids[@]}"

echo "mainDriver: Fix Files"
    fixFiles

    #######################
    # cleanup
    #######################
    /bin/rm -f $SEACH_OUT
    /bin/rm -f $TMP_OUT

echo "mainDriver: Finished"
    return
}

mainDriver


exit 0

