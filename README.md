# Backuper

My personal tool to make an automated local backup of some data in the cloud.

## Third-party tools

- https://github.com/ralbear/IMAPbackup - MIT / GPLv2, `tools/imapgrab.py`

## Dependencies for macOS

```shell
# IMAPbackup doesn't work well with Python3
brew tap-new restorer/python2
brew extract python@2 restorer/python2
brew install restorer/python2/python@2.7.17

# IMAPbackup dependencies
brew install getmail

# Everbackup dependencies
gem install evernote-thrift

# Backuper dependencies
brew install jq
```

## Dependencies for Gentoo Linux

```shell
# IMAPbackup dependencies
emerge -v net-mail/getmail

# Everbackup dependencies
gem install evernote-thrift

# Backuper dependencies
emerge -v app-misc/jq app-misc/yq
```
