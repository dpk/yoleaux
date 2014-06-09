module Yoleaux
  # the sender is responsible for actually talking to the server. it's a
  # bit of abstraction to allow buffering and flood control to happen
  # without interfering with important, time-sensitive goings-on in the
  # bot's core
  # 
  # the algorithm needs to be made a little (ok, a lot) more advanced,
  # so that floods from one command don't needlessly hold up responses
  # to other commands, perhaps in other channels. in other words, the
  # position of a message in the buffer should be proportional to the
  # number of messages recently sent as a result of that command. i
  # think it's quite safe to assume here that only one command happens
  # in a channel at once, which should make things a tad easier. there
  # needs to be some code somewhere else to kill flooding commands anyway
  
  class Sender
    attr_reader :pid, :inqueue, :outqueue
    def initialize pid, inqueue, outqueue
      @pid = pid
      @inqueue = inqueue
      @outqueue = outqueue
      
      trap(:INT) { }
      trap(:TERM) { exit }
    end
    attr_accessor :socket
    
    def run
      @buffer = []
      @last_written = Time.now - 86400
      @before_that = Time.now - (86400 * 2)
      loop do
        selected = Queue.select([@inqueue], [], [], (Time.now.to_f % 1.5))
        if selected
          str = @inqueue.receive
          if @buffer.empty? and (Time.now - @last_written) > 0.5 and (@last_written - @before_that) > 1.0
            write_now str
          else
            @buffer.unshift str
          end
        elsif not @buffer.empty?
          write_now @buffer.pop
        end
      end
    end
    
    def write_now str
      @before_that = @last_written
      @last_written = Time.now
      @socket.write str
      @outqueue.send str
    end
  end
end
