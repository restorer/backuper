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
    mkdir -p .backup
    pushd .backup

    python2 "../tools/imapgrab.py" --verbose \
        --download \
        --server 'imap.fastmail.com' \
        --ssl \
        --port 993 \
        --folder 'fastmail-mail' \
        --username "$FASTMAIL_USERNAME" \
        --password "$FASTMAIL_PASSWORD" \
        --mailboxes '_ALL_,-Trash,-Spam'

    rm fastmail-mail/oldmail-*
    popd
fi

##
## Fastmail: calendar
##

if shoud_backup "$@" "fastmail-calendar" ; then
    echo "Backing up Fastmail's calendar..."
    mkdir -p .backup/fastmail-calendar

    CURRENT_USER_PRINCIPAL="$(curl -s \
        --basic \
        --user "${FASTMAIL_USERNAME}:${FASTMAIL_PASSWORD}" \
        --url 'https://caldav.fastmail.com/dav/calendars' \
        --header 'Content-Type: application/xml' \
        --request PROPFIND \
        --data '<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:">
    <d:prop>
        <d:current-user-principal />
    </d:prop>
</d:propfind>' | xq -r '."d:multistatus"."d:response"."d:propstat"."d:prop"."d:current-user-principal"."d:href"')"

    CALENDAR_HOME_SET="$(curl -s \
        --basic \
        --user "${FASTMAIL_USERNAME}:${FASTMAIL_PASSWORD}" \
        --url "https://caldav.fastmail.com${CURRENT_USER_PRINCIPAL}" \
        --header 'Content-Type: application/xml' \
        --request PROPFIND \
        --data '<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <c:calendar-home-set />
  </d:prop>
</d:propfind>' | xq -r '."d:multistatus"."d:response"."d:propstat"."d:prop"."c:calendar-home-set"."d:href"')"

    CALENDAR_HREF="$(curl -s \
        --basic \
        --user "${FASTMAIL_USERNAME}:${FASTMAIL_PASSWORD}" \
        --url "https://caldav.fastmail.com${CALENDAR_HOME_SET}" \
        --header 'Content-Type: application/xml' \
        --header 'Depth: 1' \
        --request PROPFIND \
        --data '<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
  <d:prop>
    <d:displayname />
    <d:getcontenttype />
    <d:resourcetype />
    <c:supported-calendar-component-set />
    <cs:getctag />
  </d:prop>
</d:propfind>' | xq -r '."d:multistatus"."d:response"[] | select(."d:propstat"[]."c:supported-calendar-component-set"? != null) | select(."d:propstat"."d:prop"."d:displayname" == "Calendar") | ."d:href"')"

    if [ "$CALENDAR_HREF" = "" ] ; then
        echo "Unable to detect calendar"
        exit 1
    fi

    ICS_LIST="$(curl -s \
        --basic \
        --user "${FASTMAIL_USERNAME}:${FASTMAIL_PASSWORD}" \
        --url "https://caldav.fastmail.com${CALENDAR_HREF}" \
        --header 'Content-Type: application/xml' \
        --request PROPFIND \
        --data '<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
  <d:prop>
    <d:getcontenttype />
  </d:prop>
</d:propfind>' | xq -r '."d:multistatus"."d:response"[]."d:href"' | grep '\.ics$')"

    RESULT=".backup/fastmail-calendar/calendar.ics"

    echo 'BEGIN:VCALENDAR
VERSION:2.0
CALSCALE:GREGORIAN' > "$RESULT"

    printf '%s\n' "$ICS_LIST" | while IFS= read -r ICS ; do
        echo "Downloading $ICS..."

        curl -s\
            --basic \
            --user "${FASTMAIL_USERNAME}:${FASTMAIL_PASSWORD}" \
            --request GET \
            --url "https://caldav.fastmail.com${ICS}" | sed -e '$d' | sed -e '1,/VEVENT/{/VEVENT/p;d}' >> "$RESULT"
    done

    echo 'END:VCALENDAR' >> $RESULT
fi

##
## Todoist
##

# https://developer.todoist.com/rest/v1/#overview
if shoud_backup "$@" "todoist" ; then
    echo "Backing up Todoist..."
    mkdir -p .backup/todoist

    curl -s -H "Authorization: Bearer ${TODOIST_TOKEN}" https://api.todoist.com/rest/v1/projects > .backup/todoist/projects.json
    curl -s -H "Authorization: Bearer ${TODOIST_TOKEN}" https://api.todoist.com/rest/v1/tasks > .backup/todoist/tasks.json
    curl -s -H "Authorization: Bearer ${TODOIST_TOKEN}" https://api.todoist.com/rest/v1/labels > .backup/todoist/labels.json

    while read -r PROJECT_ID ; do
        echo "Sections for project ${PROJECT_ID}..."
        SECTIONS="$(curl -s -H "Authorization: Bearer ${TODOIST_TOKEN}" "https://api.todoist.com/rest/v1/sections?project_id=${PROJECT_ID}")"

        if [ "$SECTIONS" != "[]" ] ; then
            echo "$SECTIONS" > ".backup/todoist/project_${PROJECT_ID}_sections.json"
        fi
    done < <(cat .backup/todoist/projects.json | jq '.[] | .id')

    while read -r PROJECT_ID ; do
        echo "Comments for project ${PROJECT_ID}..."

        curl -s \
            -H "Authorization: Bearer ${TODOIST_TOKEN}" \
            "https://api.todoist.com/rest/v1/comments?project_id=${PROJECT_ID}" \
            > ".backup/todoist/project_${PROJECT_ID}_comments.json"
    done < <(cat .backup/todoist/projects.json | jq '.[] | select(.comment_count != 0) | .id')

    while read -r TASK_ID ; do
        echo "Comments for task ${TASK_ID}..."

        curl -s \
            -H "Authorization: Bearer ${TODOIST_TOKEN}" \
            "https://api.todoist.com/rest/v1/comments?task_id=${TASK_ID}" \
            > ".backup/todoist/task_${TASK_ID}_comments.json"
    done < <(cat .backup/todoist/tasks.json | jq '.[] | select(.comment_count != 0) | .id')
fi

##
## GitHub
##

# https://docs.github.com/en/github/authenticating-to-github/creating-a-personal-access-token
if shoud_backup "$@" "github" ; then
    echo "Backing up GitHub repos..."
    mkdir -p .backup/github
    pushd .backup/github

    URL="https://api.github.com/search/repositories?q=user:${GITHUB_USERNAME}+fork:true&per_page=100"

    while read -r REPO ; do
        if [ -e "$REPO" ] ; then
            pushd "$REPO" && git pull && popd
        else
            git clone "git@github.com:${GITHUB_USERNAME}/${REPO}.git"
        fi
    done < <(curl -u "${GITHUB_USERNAME}:${GITHUB_TOKEN}" $URL 2>/dev/null | jq -r '.items[] | .name')

    popd
fi

##
## Bitbucket
##

if shoud_backup "$@" "bitbucket" ; then
    echo "Backing up Bitbucket repos..."
    mkdir -p .backup/bitbucket
    pushd .backup/bitbucket

    for REPO in restorer/fire-strike restorer/gd2d restorer/i-motivate restorer/scop restorer/shopus restorer/ya-contest scop_me/android-app scop_me/attachments-server scop_me/backend scop_me/scop_server scop_me/socket-server ; do

        DEST="$(echo "$REPO" | tr / _)"

        if [ -e "$DEST" ] ; then
            pushd "$DEST" && git pull && popd
        else
            git clone "git@bitbucket.org:${REPO}.git" "$DEST"
        fi
    done

    popd
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
        sudo mount.cifs "${SERVER_SERVICE}" .mount -o "iocharset=utf8,rw,username=${SERVER_USERNAME},password=${SERVER_PASSWORD},uid=${_UID},gid=${_GID},file_mode=0660,dir_mode=0770"
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
