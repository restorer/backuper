#!/bin/sh

cd "$(dirname "$0")"

[ -e .backup/bitbucket ] && rm -rf .backup/bitbucket
[ -e .backup/fastmail-calendar ] && rm -rf .backup/fastmail-calendar
[ -e .backup/fastmail-mail ] && rm -rf .backup/fastmail-mail
[ -e .backup/github ] && rm -rf .backup/github
[ -e .backup/server ] && rm -rf .backup/server
[ -e .backup/todoist ] && rm -rf .backup/todoist

find .backup -name '*.zip' -exec rm {} \;
find .backup -name '*.tgz' -exec rm {} \;
