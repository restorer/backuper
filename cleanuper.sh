#!/bin/sh

cd "$(dirname "$0")"

[ -e .backup/fastmail-mail ] && rm -r .backup/fastmail-mail
[ -e .backup/fastmail-calendar ] && rm -r .backup/fastmail-calendar
[ -e .backup/todoist ] && rm -r .backup/todoist
[ -e .backup/github ] && rm -r .backup/github
[ -e .backup/bitbucket ] && rm -r .backup/bitbucket
[ -e .backup/server ] && rm -r .backup/server
