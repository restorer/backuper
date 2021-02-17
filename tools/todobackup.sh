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

set -e

if [ "$1" = "" ] || [ "$2" = "" ] ; then
    echo "Usage: $(basename "$0") <backup path> <token>"
    exit 1
fi

BACKUP="$1"
TOKEN="$2"

curl -s -H "Authorization: Bearer ${TOKEN}" https://api.todoist.com/rest/v1/projects > "${BACKUP}/projects.json"
curl -s -H "Authorization: Bearer ${TOKEN}" https://api.todoist.com/rest/v1/tasks > "${BACKUP}/tasks.json"
curl -s -H "Authorization: Bearer ${TOKEN}" https://api.todoist.com/rest/v1/labels > "${BACKUP}/labels.json"

while read -r PROJECT_ID ; do
    echo "Sections for project ${PROJECT_ID}..."
    SECTIONS="$(curl -s -H "Authorization: Bearer ${TOKEN}" "https://api.todoist.com/rest/v1/sections?project_id=${PROJECT_ID}")"

    if [ "$SECTIONS" != "[]" ] ; then
        echo "$SECTIONS" > "${BACKUP}/project_${PROJECT_ID}_sections.json"
    fi
done < <(cat "${BACKUP}/projects.json" | jq '.[] | .id')

while read -r PROJECT_ID ; do
    echo "Comments for project ${PROJECT_ID}..."

    curl -s \
        -H "Authorization: Bearer ${TOKEN}" \
        "https://api.todoist.com/rest/v1/comments?project_id=${PROJECT_ID}" \
        > "${BACKUP}/project_${PROJECT_ID}_comments.json"
done < <(cat "${BACKUP}/projects.json" | jq '.[] | select(.comment_count != 0) | .id')

while read -r TASK_ID ; do
    echo "Comments for task ${TASK_ID}..."

    curl -s \
        -H "Authorization: Bearer ${TOKEN}" \
        "https://api.todoist.com/rest/v1/comments?task_id=${TASK_ID}" \
        > "${BACKUP}/task_${TASK_ID}_comments.json"
done < <(cat "${BACKUP}/tasks.json" | jq '.[] | select(.comment_count != 0) | .id')

exit 0
