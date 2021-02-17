#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2021, Viachaslau Tratsiak (viachaslau@fastmail.com)
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

# Dependencies:
# - curl
# - jq
# - xq (from "yq" package)

set -e

if [ "$1" = "" ] || [ "$2" = "" ] || [ "$3" = "" ] || [ "$4" = "" ] ; then
    echo "Usage: $(basename "$0") <backup path> <server> <username> <password>"
    exit 1
fi

BACKUP="$1"
SERVER="$2"
USERNAME="$3"
PASSWORD="$4"

CURRENT_USER_PRINCIPAL="$(curl -s \
    --basic \
    --user "${USERNAME}:${PASSWORD}" \
    --url "${SERVER}/dav/calendars" \
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
    --user "${USERNAME}:${PASSWORD}" \
    --url "${SERVER}${CURRENT_USER_PRINCIPAL}" \
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
    --user "${USERNAME}:${PASSWORD}" \
    --url "${SERVER}${CALENDAR_HOME_SET}" \
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
    --user "${USERNAME}:${PASSWORD}" \
    --url "${SERVER}${CALENDAR_HREF}" \
    --header 'Content-Type: application/xml' \
    --request PROPFIND \
    --data '<?xml version="1.0" encoding="UTF-8"?>
<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
<d:prop>
<d:getcontenttype />
</d:prop>
</d:propfind>' | xq -r '."d:multistatus"."d:response"[]."d:href"' | grep '\.ics$')"

RESULT="${BACKUP}/calendar.ics"

echo 'BEGIN:VCALENDAR
VERSION:2.0
CALSCALE:GREGORIAN' > "$RESULT"

printf '%s\n' "$ICS_LIST" | while IFS= read -r ICS ; do
    echo "Downloading $ICS..."

    curl -s \
        --basic \
        --user "${USERNAME}:${PASSWORD}" \
        --request GET \
        --url "${SERVER}${ICS}" | sed -e '$d' | sed -e '1,/VEVENT/{/VEVENT/p;d}' >> "$RESULT"
done

echo 'END:VCALENDAR' >> $RESULT
exit 0
