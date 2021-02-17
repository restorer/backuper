#!/bin/bash

set -e

shoud_backup () {
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
if shoud_backup "$@" "evernote" ; then
    echo "Backing up Evernote..."
    mkdir -p .backup/evernote
    ./tools/everbackup.rb .backup/evernote "$EVERNOTE_TOKEN"
fi

##
## Fastmail: mail
##

if shoud_backup "$@" "fastmail-mail" ; then
    echo "Backing up Fastmail's mail..."
    mkdir -p .backup/fastmail-mail
    ./tools/imapbackup.sh .backup fastmail-mail 'imap.fastmail.com' 993 "$FASTMAIL_USERNAME" "$FASTMAIL_PASSWORD"
fi

##
## Fastmail: calendar
##

if shoud_backup "$@" "fastmail-calendar" ; then
    echo "Backing up Fastmail's calendar..."
    mkdir -p .backup/fastmail-calendar
    ./tools/calbackup.sh .backup/fastmail-calendar 'https://caldav.fastmail.com' "$FASTMAIL_USERNAME" "$FASTMAIL_PASSWORD"
fi

##
## Todoist
##

# https://developer.todoist.com/rest/v1/#overview
if shoud_backup "$@" "todoist" ; then
    echo "Backing up Todoist..."
    mkdir -p .backup/todoist
    ./tools/todobackup.sh .backup/todoist "$TODOIST_TOKEN"
fi

##
## GitHub
##

# https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token
if shoud_backup "$@" "github" ; then
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

if shoud_backup "$@" "bitbucket" ; then
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

if shoud_backup "$@" "server" ; then
    echo "Backing up Server..."
    mkdir -p .mount
    mkdir -p .backup/server

    _UID=$(id -u)
    _GID=$(id -g)

    if [ "$(mount | grep " on $(realpath .mount) type cifs ")" = "" ] ; then
        sudo mount.cifs "${SERVER_SERVICE}" .mount -o \
        "iocharset=utf8,rw,username=${SERVER_USERNAME},password=${SERVER_PASSWORD},uid=${_UID},gid=${_GID},file_mode=0660,dir_mode=0770"
    fi

    LAST="$(ls -1 .mount | grep -E '^[0-9]{4}\-[0-9]{2}\-[0-9]{2}$' | sort -r | head -n 1)"

    if [ "$LAST" = "" ] ; then
        echo "Unable to detect last backup folder"
        exit 1
    fi

    cp .mount/$LAST/* .backup/server
    sudo umount .mount
    rmdir .mount
fi

##
## External
##

if shoud_backup "$@" "external" ; then
    echo "External backups:"
    echo
    echo "* restorer.fct (contacts & drive) - https://takeout.google.com/settings/takeout"
    echo "* viachaslau.tratsiak (drive) - https://takeout.google.com/settings/takeout"
    echo "* medium - https://medium.com/me/settings"
fi
