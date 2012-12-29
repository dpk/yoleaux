
class Yoleaux
  # the scheduler is a process for putting objects in, and getting them
  # out again at a specific later time. eg. send in [4, "hello world"]
  # and it will return "hello world" after 4 seconds
  class Scheduler
    attr_reader :pid, :inqueue, :outqueue
    def initialize pid, inqueue, outqueue
      @pid = pid
      @inqueue = inqueue
      @outqueue = outqueue
    end
    
    def run
      return nil unless @pid == $$
      unless @spr and @spw
        @spr, @spw = IO.pipe
      end
      load_schedule
      trap(:TERM) { @spw.write_nonblock("\x00") }
      trap(:INT) { }
      
      loop do
        timetillnext = (@schedule.empty? ? nil : (@schedule.first.first - Time.now))
        
        if not timetillnext.nil? and timetillnext < 0
          do_tasks
        else
          selectresult, _, _ = Queue.select [@inqueue, @spr], [], [], timetillnext
          if selectresult
            selectresult.each do |i|
              if i == @inqueue
                add_task @inqueue.receive
              elsif i == @spr
                write_schedule
                exit 0
              end
            end
          end
        end
      end
    end
    
    # do a sorted insertion if this gets slow
    def add_task task
      time, obj = task
      if time.is_a? Numeric
        time = Time.now + time
      elsif time.is_a? DateTime
        time = time.to_time
      end
      @schedule << [time, obj]
      sort_schedule
      write_schedule
    end
    def do_tasks
      # if a task is overdue or due in the next 0.1 seconds, do it now:
      @schedule.each do |task|
        time, obj = task
        if Time.now >= (time - 0.1)
          @outqueue.send task
          @schedule.delete task
        else
          break
        end
      end
      write_schedule
    end
    
    def load_schedule
      if File.exist? "#{Yoleaux::BASE}/schedule.db"
        @schedule = Marshal.load File.read "#{Yoleaux::BASE}/schedule.db"
        sort_schedule
      else
        @schedule = []
        write_schedule
      end
    end
    def sort_schedule
      @schedule.sort_by! &:first
    end
    def write_schedule
      tempname = "#{Yoleaux::BASE}/.schedule.#{SecureRandom.hex(4)}.db"
      File.write tempname, Marshal.dump(@schedule)
      File.rename tempname, "#{Yoleaux::BASE}/schedule.db"
    end
  end
end  
