#!/bin/sh

cd "$(dirname "$0")"

[ -e .backup/fastmail-mail ] && rm -rf .backup/fastmail-mail
[ -e .backup/fastmail-calendar ] && rm -rf .backup/fastmail-calendar
[ -e .backup/todoist ] && rm -rf .backup/todoist
[ -e .backup/github ] && rm -rf .backup/github
[ -e .backup/bitbucket ] && rm -rf .backup/bitbucket
[ -e .backup/server ] && rm -rf .backup/server
