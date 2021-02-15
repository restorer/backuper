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

NOTES_BULK = 250
RETRIES = 10

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

def shouldUpdateNote(path, updateSequenceNum)
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

def process(basePath, authToken, evernoteHost)
    userStoreUrl = "https://#{evernoteHost}/edam/user"
    userStore = Evernote::EDAM::UserStore::UserStore::Client.new(createThriftProtocol("https://#{evernoteHost}/edam/user"))

    versionOk = userStore.checkVersion(
        'Everbackup',
        Evernote::EDAM::UserStore::EDAM_VERSION_MAJOR,
        Evernote::EDAM::UserStore::EDAM_VERSION_MINOR
    )

    raise Error.new('Evernote API version mismatch') unless versionOk

    noteStore = Evernote::EDAM::NoteStore::NoteStore::Client.new(createThriftProtocol(userStore.getNoteStoreUrl(authToken)))
    notebooks = noteStore.listNotebooks(authToken)
    notebookIndex = 0

    notebooks.each do |notebook|
        notebookIndex += 1
        puts "[#{notebookIndex} / #{notebooks.size}] Notebook: #{notebook.guid}"
        saveNotebookOrNote("#{basePath}/notebooks/#{notebook.guid}.json", notebook)
    end

    resultSpec = Evernote::EDAM::NoteStore::NotesMetadataResultSpec.new
    resultSpec.includeUpdateSequenceNum = true

    offset = 0
    noteIndex = 0

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
            noteIndex += 1
            puts "[#{noteIndex} / #{notesMetadataList.totalNotes}] Note: #{noteMetadata.guid}"

            notePath = "#{basePath}/notes/#{noteMetadata.guid}.json"
            next unless shouldUpdateNote(notePath, noteMetadata.updateSequenceNum)

            for i in 1 .. RETRIES
                begin
                    note = noteStore.getNote(
                        authToken,
                        noteMetadata.guid,
                        true, # withContent
                        true, # withResourcesData
                        true, # withResourcesRecognition
                        true # withResourcesAlternateData
                    )
                rescue SocketError
                    next
                end

                break
            end

            saveNotebookOrNote(notePath, note)
        end

        offset += notesMetadataList.notes.size
    end
end

if ARGV.size == 2
    process(ARGV[0], ARGV[1], 'www.evernote.com')
elsif ARGV.size == 3
    process(ARGV[0], ARGV[1], ARGV[2])
else
    puts "Usage: #{__FILE__} <backup path> <token>"
end
