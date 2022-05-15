#!/bin/bash

set -e

should_backup () {
    [[ " $1 " =~ " --only-${2} " ]] && return 0
    [[ " $1" =~ " --only-" ]] && return 1
    [[ " $1 " =~ " --skip-${2} " ]] && return 1
    return 0
}

cd "$(dirname "$0")"
source .env

##
## Evernote
##

# https://www.evernote.com/api/DeveloperToken.action
if should_backup "$*" "evernote" ; then
    echo "Backing up Evernote..."
    mkdir -p .backup/evernote
    ./tools/everbackup.rb .backup/evernote "$EVERNOTE_TOKEN"
fi

##
## Fastmail: mail
##

if should_backup "$*" "fastmail-mail" ; then
    echo "Backing up Fastmail's mail..."
    mkdir -p .backup/fastmail-mail
    ./tools/imapbackup.sh .backup fastmail-mail 'imap.fastmail.com' 993 "$FASTMAIL_USERNAME" "$FASTMAIL_PASSWORD"
fi

##
## Fastmail: calendar
##

if should_backup "$*" "fastmail-calendar" ; then
    echo "Backing up Fastmail's calendar..."
    mkdir -p .backup/fastmail-calendar
    ./tools/calbackup.sh .backup/fastmail-calendar 'https://caldav.fastmail.com' "$FASTMAIL_USERNAME" "$FASTMAIL_PASSWORD"
fi

##
## Todoist
##

# https://developer.todoist.com/rest/v1/#overview
if should_backup "$*" "todoist" ; then
    echo "Backing up Todoist..."
    mkdir -p .backup/todoist
    ./tools/todobackup.sh .backup/todoist "$TODOIST_TOKEN"
fi

##
## GitHub
##

# https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token
if should_backup "$*" "github" ; then
    echo "Backing up GitHub repos..."
    mkdir -p .backup/github

    URL="https://api.github.com/search/repositories?q=user:${GITHUB_USERNAME}+fork:true&per_page=100"

    ./tools/gitbackup.sh \
        .backup/github \
        'git@github.com' \
        $(curl -u "${GITHUB_USERNAME}:${GITHUB_TOKEN}" $URL 2>/dev/null | jq -r '.items[] | .full_name')
fi

##
## Bitbucket
##

if should_backup "$*" "bitbucket" ; then
    echo "Backing up Bitbucket repos..."
    mkdir -p .backup/bitbucket

    ./tools/gitbackup.sh \
        .backup/bitbucket \
        'git@bitbucket.org' \
        restorer/fire-strike restorer/gd2d restorer/i-motivate restorer/scop \
        restorer/shopus restorer/ya-contest scop_me/android-app scop_me/attachments-server \
        scop_me/backend scop_me/scop_server scop_me/socket-server
fi

##
## Server
##

## /etc/sudoers.d/my-sudo:
#
# %sudo ALL=(ALL) NOPASSWD: /usr/local/bin/my-mount-backup, /usr/local/bin/my-umount-backup

## /usr/local/bin/my-mount-backup
#
# #!/bin/bash
#
# if [ "$1" = "" ] || [ "$2" = "" ] ; then
#     echo "Usage: $0 <uid> <gid>"
#     exit 1
# fi
#
# exec mount.cifs '...' /mnt/backup -o \
#     "iocharset=utf8,rw,username=...,password=...,uid=${1},gid=${2},file_mode=0660,dir_mode=0770"

## /usr/local/bin/my-umount-backup
#
# #!/bin/bash
#
# umount /mnt/backup

if should_backup "$*" "server" ; then
    echo "Backing up Server..."
    mkdir -p .backup/server

    if [ "$(mount | grep " on /mnt/backup type cifs ")" = "" ] ; then
        sudo /usr/local/bin/my-mount-backup "$(id -u)" "$(id -g)"
    fi

    LAST="$(ls -1 /mnt/backup | grep -E '^[0-9]{4}\-[0-9]{2}\-[0-9]{2}$' | sort -r | head -n 1)"

    if [ "$LAST" = "" ] ; then
        echo "Unable to detect last backup folder"
        exit 1
    fi

    echo ">>> Backing up $LAST ..."
    cp /mnt/backup/$LAST/* .backup/server
    sudo /usr/local/bin/my-umount-backup
fi

##
## External
##

if should_backup "$*" "external" ; then
    echo "External backups:"
    echo
    echo "* restorer.fct (contacts & drive) - https://takeout.google.com/settings/takeout"
    echo "* viachaslau.tratsiak (drive) - https://takeout.google.com/settings/takeout"
    echo "* medium - https://medium.com/me/settings"
fi
