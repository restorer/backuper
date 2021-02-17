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
# - git

set -e

if [ "$1" = "" ] || [ "$2" = "" ] ; then
    echo "Usage: $(basename "$0") <backup path> <server> [repo full name 1] [repo full name 2] ..."
    exit 1
fi

BACKUP="$1" ; shift
SERVER="$1" ; shift

pushd "$BACKUP"

while [ "$1" != "" ] ; do
    REPO="$1" ; shift
    DEST="$(echo "$REPO" | tr / _)"

    if [ -e "$DEST" ] ; then
        pushd "$DEST" && git pull && popd
    else
        git clone "${SERVER}:${REPO}.git" "$DEST"
    fi
done

popd
