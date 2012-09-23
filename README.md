# vim_color_schemes_downloader

Bash script to download Vim color schemes

# Introduction

The script *downloadVimColorSchemes.sh* can be used to 
download all (many) of the Vim color schemes.
It first does an ftp to get the current Vim Runtime color scheme
files and then does a search for all color scheme labeled
scripts, finds their page script id, gets their (generally) 
first download entry script id and name and, finally, downloads
the script.
Bash script tested only on Fedora Linux.
May not work on Cygwin or other Linux systems.
For Cygwin, the TARGET_DIR which will have to be changed.
In the past I've written bash scripts and have had access to
Cygwin platforms for testing. Currently, I do not have such
access, so the script will need fixing for Cygwin use.
The location of some of the executables used by the script may
differ in different Linux distributions. They will have to be
adjusted in such cases.

Currently, the script downloads some 686 "unique" Vim color scheme files.

# Purpose

I wrote the script so that I could populate the Vim script
[color_schemer.vim] (https://github.com/megaannum/colorschemer)
with an initial set of Vim color schemes.
I posted the script to github simply for safe keeping.
