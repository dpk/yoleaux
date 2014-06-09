require 'securerandom'

module Yoleaux
  class Database
    def initialize name, value=nil
      @name = name
      @value = value
      @file = "#{Yoleaux::Bot::BASE}/#{name}.db"
      if File.exist? @file
        @value = Marshal.load File.read @file
      else
        write!
      end
    end
    
    attr_reader :value
    def value= x
      @value = x
      write!
    end
    
    def write!
      tempf = "#@file.#{SecureRandom.hex(4)}"
      File.write tempf, Marshal.dump(@value)
      File.rename tempf, @file
    end
    
    def method_missing *a, &b
      v = @value.send *a, &b
      write!
      v
    end
    def respond_to_missing? *a
      @value.respond_to? *a
    end
  end
end

