#!/usr/bin/env ruby

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
# - https://github.com/evernote/evernote-sdk-ruby -- gem install evernote-thrift

require 'fileutils'
require 'base64'
require 'json'
require 'evernote-thrift'

CLIENT_NAME = 'Everbackup'
NETWORK_RETRIES = 10
PATH_NOTEBOOKS = 'notebooks'
PATH_NOTES = 'notes'
NOTES_BULK = 250

def createThriftProtocol(url)
    return Thrift::BinaryProtocol.new(Thrift::HTTPClientTransport.new(url))
end

def convertToJson(value, info)
    type = info[:type]

    if [
        Thrift::Types::BOOL,
        Thrift::Types::BYTE,
        Thrift::Types::DOUBLE,
        Thrift::Types::I16,
        Thrift::Types::I32,
        Thrift::Types::I64,
    ].include?(type)
        value
    elsif type == Thrift::Types::STRING
        if !info[:binary]
            value
        elsif info[:name] =~ /hash/i
            value.bytes.map { |b| sprintf('%02x', b) }.join
        else
            Base64.encode64(value).strip
        end
    elsif type == Thrift::Types::STRUCT
        result = {}

        value.each_field do |_, innerInfo|
            innerName = innerInfo[:name]
            innerValue = value.instance_variable_get("@#{innerName}")
            result[innerName] = convertToJson(innerValue, innerInfo) unless innerValue.nil?
        end

        result
    elsif type == Thrift::Types::MAP
        result = {}

        value.each do |innerKey, innerValue|
            result[innerKey] = convertToJson(innerValue, info[:value])
        end

        result
    elsif [Thrift::Types::SET, Thrift::Types::LIST]
        result = []

        value.each do |innerValue|
            result << convertToJson(innerValue, info[:element])
        end

        result
    else
        raise Error.new("Unsupported element type = #{type}")
    end
end

def shouldUpdateNotebookOrNote(path, updateSequenceNum)
    return true unless File.exists?(path)

    File.open(path, 'rb') do |fi|
        line = fi.gets(256)
        return true if line.nil?

        mt = /^\/\/[ ]*?updateSequenceNum:[ ]*?([0-9]+?)[ ]*?$/.match(line.strip)
        return true if mt.nil?

        return mt[1] != updateSequenceNum.to_s
    end
end

def saveNotebookOrNote(path, element)
    jsonString = JSON.pretty_generate(convertToJson(element, {:type => Thrift::Types::STRUCT}))
    FileUtils.mkdir_p File.dirname(path)

    File.open(path, 'wb') do |fo|
        fo << "// updateSequenceNum: #{element.updateSequenceNum}\n" unless element.updateSequenceNum.nil?
        fo << jsonString
    end
end

def networkCall
    lastError = nil

    for i in 1 .. NETWORK_RETRIES
        begin
            return yield
        rescue SocketError => e
            lastError = e
        end
    end

    raise lastError.nil? ? Error.new('Should not happen') : lastError
end

def findExistingPathsMap(path)
    result = {}

    Dir.open(path).each do |name|
        result["#{path}/#{name}"] = true unless name == '.' || name == '..'
    end

    return result
end

def updateNotebooks(basePath, authToken, noteStore)
    folderPath = "#{basePath}/#{PATH_NOTEBOOKS}"
    pathsMap = findExistingPathsMap(folderPath)

    notebooks = networkCall { noteStore.listNotebooks(authToken) }
    position = 0
    statAdded = 0
    statUpdated = 0
    statDeleted = 0

    notebooks.each do |notebook|
        position += 1
        puts "[#{position} / #{notebooks.size}] Notebook: #{notebook.guid}"
        path = "#{folderPath}/#{notebook.guid}.json"

        if pathsMap.key?(path)
            pathsMap.delete(path)
            next unless shouldUpdateNotebookOrNote(path, notebook.updateSequenceNum)
            statUpdated += 1
        else
            statAdded += 1
        end

        saveNotebookOrNote(path, notebook)
    end

    pathsMap.keys.each do |path|
        statDeleted += 1
        File.delete(path)
    end

    puts "Notebooks added: #{statAdded}, updated: #{statUpdated}, deleted: #{statDeleted}"
end

def updateNotes(basePath, authToken, noteStore)
    folderPath = "#{basePath}/#{PATH_NOTES}"
    pathsMap = findExistingPathsMap(folderPath)

    resultSpec = Evernote::EDAM::NoteStore::NotesMetadataResultSpec.new
    resultSpec.includeUpdateSequenceNum = true

    offset = 0
    position = 0
    statAdded = 0
    statUpdated = 0
    statDeleted = 0

    loop do
        notesMetadataList = noteStore.findNotesMetadata(
            authToken,
            Evernote::EDAM::NoteStore::NoteFilter.new,
            offset,
            NOTES_BULK,
            resultSpec
        )

        break if notesMetadataList.notes.empty?

        notesMetadataList.notes.each do |noteMetadata|
            position += 1
            puts "[#{position} / #{notesMetadataList.totalNotes}] Note: #{noteMetadata.guid}"
            path = "#{folderPath}/#{noteMetadata.guid}.json"

            if pathsMap.key?(path)
                pathsMap.delete(path)
                next unless shouldUpdateNotebookOrNote(path, noteMetadata.updateSequenceNum)
                statUpdated += 1
            else
                statAdded += 1
            end

            saveNotebookOrNote(path, networkCall {
                noteStore.getNote(
                    authToken,
                    noteMetadata.guid,
                    true, # withContent
                    true, # withResourcesData
                    true, # withResourcesRecognition
                    true # withResourcesAlternateData
                )
            })
        end

        offset += notesMetadataList.notes.size
    end

    pathsMap.keys.each do |path|
        statDeleted += 1
        File.delete(path)
    end

    puts "Notes added: #{statAdded}, updated: #{statUpdated}, deleted: #{statDeleted}"
end

def process(basePath, authToken, evernoteHost)
    userStoreUrl = "https://#{evernoteHost}/edam/user"
    userStore = Evernote::EDAM::UserStore::UserStore::Client.new(createThriftProtocol("https://#{evernoteHost}/edam/user"))

    raise Error.new('Evernote API version mismatch') unless networkCall {
        userStore.checkVersion(
            CLIENT_NAME,
            Evernote::EDAM::UserStore::EDAM_VERSION_MAJOR,
            Evernote::EDAM::UserStore::EDAM_VERSION_MINOR
        )
    }

    noteStore = Evernote::EDAM::NoteStore::NoteStore::Client.new(createThriftProtocol(userStore.getNoteStoreUrl(authToken)))
    updateNotebooks(basePath, authToken, noteStore)
    updateNotes(basePath, authToken, noteStore)
end

if ARGV.size == 2
    process(ARGV[0], ARGV[1], 'www.evernote.com')
elsif ARGV.size == 3
    process(ARGV[0], ARGV[1], ARGV[2])
else
    puts "Usage: #{__FILE__} <backup path> <token>"
end
