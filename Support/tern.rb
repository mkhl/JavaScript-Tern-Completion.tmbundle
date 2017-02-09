#!/usr/bin/env ruby18 -wKU

$LOAD_PATH << "#{ENV["TM_BUNDLE_SUPPORT"]}/json/lib"

require "#{ENV['TM_SUPPORT_PATH']}/lib/ui"
require "#{ENV['TM_SUPPORT_PATH']}/lib/tm/detach"
require "#{ENV['TM_SUPPORT_PATH']}/lib/tm/save_current_document"
require 'net/http'
require 'ostruct'
require 'pathname'
require 'json'

def Tern(&block)
  Tern.new.start(&block)
end

class Tern
  def initialize
    TextMate.save_if_untitled
    Dir.chdir(root)
  end

  def complete
    send(query_completions) do |response|
      choices = response["completions"].map do |completion|
        name = completion["name"]
        type = completion["type"]
        {
          "match" => name,
          "display" => "#{name} \t#{type}",
        }
      end
      TextMate::UI.complete(choices)
    end
  end

  def start(&block)
    return yield self if port
    TextMate::detach { system TERN, "--ignore-stdin" }
    sleep 1
    return yield self if port
    TextMate::UI.alert(:critical, "Tern failed to start", "Try running tern manually in #{root}")
  end

  private

  FILES = OpenStruct.new(:port => '.tern-port', :project => '.tern-project')
  TERN = ENV['TM_TERN'] || 'tern'

  def port
    @port ||= begin IO.read(FILES.port) rescue nil end
  end

  def root
    files = [FILES.port, FILES.project]
    Pathname.getwd.ascend do |p|
      return p if files.any? { |n| (p+n).exist? }
    end
    Pathname.getwd
  end

  def path
    @path ||= ENV['TM_FILEPATH']
  end

  def text
    @text ||= STDIN.read || IO.read(path)
  end

  def send(body, &block)
    response = Net::HTTP.new('localhost', port).post('/', JSON.generate(body), 'Content-Type' => 'application/json')
    case response
    when Net::HTTPSuccess
      yield JSON.parse(response.body)
    else
      TextMate::UI.alert(:critical, "Tern: #{response.code}: #{response.message}", response.body)
    end
  end

  def query_completions
    {
      "query" => {
        "type" => "completions",
        "file" => "#0",
        "end" => {
          "line" => ENV['TM_LINE_NUMBER'].to_i - 1,
          "ch" => ENV['TM_LINE_INDEX'].to_i,
        },
        "types" => true,
        "docs" => true,
        "urls" => true,
        "origins" => true,
      },
      "files" => [{
        "name" => path,
        "text" => text,
        "type" => "full",
      }],
    }
  end
end
