module Yoleaux
  class Queue
    def self.select r, w=[], e=[], timeout=nil
      rmaps = {}
      wmaps = {}
      emaps = {}
      rios = r.map do |q|
        if q.is_a? Queue
          rmaps[q.reader] = q
          q.reader
        else
          q
        end
      end
      wios = w.map do |q|
        if q.is_a? Queue
          wmaps[q.writer] = q
          q.writer
        else
          q
        end
      end
      eios = e.map do |q|
        if q.is_a? Queue
          emaps[q.writer] = q
          emaps[q.reader] = q
          [q.reader, q.writer]
        else
          q
        end
      end.flatten
     
      result = IO.select(rios, wios, eios, timeout)
      return nil if result.nil?
      result[0].map! {|io| rmaps[io] or io }
      result[1].map! {|io| wmaps[io] or io }
      result[2].map! {|io| emaps[io] or io }
      result
    end
   
    def initialize
      @read, @write = IO.pipe
    end
   
    def send obj
      rep = Marshal.dump obj
      @write.write rep
    end
    def read
      Marshal.load @read
    end
    alias receive read
    alias recv read
   
    def send_nonblock obj
      IO.select([], [@write], [], 0) and send obj
    end
    def read_nonblock
      IO.select([@read], [], [], 0) and send obj
    end
    alias receive_nonblock read_nonblock
    alias recv_nonblock read
   
    def each &block
      until @read.eof?
        block.call receive
      end
    end
   
    def close_read
      @read.close
    end
    def close_write
      @write.close
    end
   
    def reader
      @read
    end
    def writer
      @write
    end
   
    def inspect
      "#<#{self.class} fd:#{@read.inspect},#{@write.inspect}>"
    end
  end
end

