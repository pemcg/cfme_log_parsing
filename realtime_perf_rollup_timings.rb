require 'optparse'

def delta_timings(current_timings, last_timings)
  new_timings = {}
  current_timings.each do |metric, current_value|
    if /^num_.*/.match(metric)
      new_timings[metric] = current_value
    else
      new_timings[metric] = last_timings.has_key?(metric) ? current_value - last_timings[metric] : 0
    end
  end
  new_timings
end

def put_timings(o, timings)
  unless timings.nil?
    timings.keys.each do |metric|
      next if /total_time/.match(metric)
      format = /^num_.*/.match(metric) ? "%-36s %5.6f" : "%-36s %5.6f seconds"
      o.puts "  #{sprintf(format, "#{metric}:", timings[metric])}" unless timings[metric].zero?
    end
    # print total_time last in each section
    if timings.has_key?(:total_time)
      o.puts "  #{sprintf("%-36s %5.6f seconds", "total_time:", timings[:total_time])}" unless timings[:total_time].zero?
    end
  end
end

def update_timings(last_timings, current_timings)
  updated_timings = last_timings
  current_timings.each do |metric, timing|
    updated_timings[metric] = timing
  end
  updated_timings
end

def stats (workers, options)
  
  non_rollup_counters = [:purge_metrics,:server_dequeue,:query_batch,:process_bottleneck]
  rollup_counters     = [:db_find_prev_perf,:rollup_perfs,:db_update_perf,:process_perfs_tag,:total_time]

  if options[:outputfile]
    o = File.open(options[:outputfile],'w')
  else
    o = $stdout.dup
  end

  workers.each do |pid, messages|
    last_timings = {}
    messages.each do |rollup|
      o.puts "---"
      o.puts "Worker PID:                    #{pid}"
      if rollup[:first_rollup_for_message]
        o.puts "Message ID:                    #{rollup[:message_id]} (new)"
        o.puts "Message fetch time:            #{rollup[:message_time]}"
        o.puts "Message time in queue:         #{rollup[:message_dequeue_time]} seconds"
      else
        o.puts "Message ID:                    #{rollup[:message_id]} (continued)"
      end
      o.puts "Rollup processing start time:  #{rollup[:start_time]}"
      o.puts "Object Type:                   #{rollup[:obj_type]}"
      o.puts "Object Name:                   #{rollup[:obj_name]}"
      o.puts "Time:                          #{rollup[:time]}"
      o.puts "Rollup timings:"
      rollup_timings = eval(rollup[:timings]) if @timings_re.match(rollup[:timings])
      unless rollup_timings.nil?
        if (rollup_timings.keys & (non_rollup_counters)).any?
          # Need to delete the erroneous counters then subtract previous counters from the remainder (https://bugzilla.redhat.com/show_bug.cgi?id=1424716)
          rollup_timings.delete_if { |key, _| !rollup_counters.include?(key) }
          put_timings(o, delta_timings(rollup_timings,last_timings))
        else
          put_timings(o, rollup_timings)
        end
        last_timings = update_timings(last_timings, rollup_timings)
      end
      o.puts "Rollup processing end time:    #{rollup[:end_time]}"
      if rollup[:last_rollup_for_message]
        o.puts "Message delivered time:        #{rollup[:message_delivered_time]}"
        o.puts "Message state:                 #{rollup[:message_state]}"
        o.puts "Message delivered in:          #{rollup[:message_delivered_in]} seconds"
      end
      o.puts "---"
      o.puts ""
    end
  end
end

# [----] I, [2017-02-24T05:28:23.216307 #40450:85113c]  INFO -- : MIQ(ManageIQ::Providers::Openstack::NetworkManager::MetricsCollectorWorker::Runner#get_message_via_drb) Message id: [119351], MiqWorker id: [7821], Zone: [default], Role: [ems_metrics_collector], Server: [], Ident: [openstack_network], Target id: [], Instance id: [209], Task id: [], Command: [ManageIQ::Providers::Openstack::CloudManager::Vm.perf_capture_realtime], Timeout: [600], Priority: [100], State: [dequeue], Deliver On: [], Data: [], Args: [], Dequeued in: [127.147928764] seconds

get_message_via_drb_re = %r{
                          ----\]\ I,\ \[(?<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6})
                          \ \#(?<pid>\h+):\h+\]
                          \ .*get_message_via_drb\)
                          \ Message\ id:\ \[(?<message_id>\d+)\],
                          \ MiqWorker\ id:\ \[(?<worker_id>\h*)\],
                          \ Zone:\ \[(?<zone>.*)\],
                          \ Role:\ \[(?<role>.*)\],
                          (\ Server:\ \[(?<server>.*)\],)?
                          \ Ident:\ \[(?<ident>.*)\],
                          \ Target\ id:\ \[(?<target_id>.*)\],
                          \ Instance\ id:\ \[(?<instance_id>.*)\],
                          \ Task\ id:\ \[(?<task_id>.*)\],
                          \ Command:\ \[(?<command>.*)\],
                          \ Timeout:\ \[(?<timeout>\d*)\],
                          \ Priority:\ \[(?<priority>\d*)\],
                          \ State:\ \[(?<state>\w+)\],
                          \ Deliver\ On:\ \[(?<deliver_on>.*)\],
                          \ Data:\ \[(?<data>.*)\],
                          \ Args:\ \[(?<args>.*)\],
                          \ Dequeued\ in:\ \[(?<dequeued_in>.+)\]\ seconds$
                            }x

# [----] I, [2016-12-13T04:44:31.371524 #15020:11e598c]  INFO -- : MIQ(EmsCluster#perf_rollup) [realtime] Rollup for EmsCluster name: [MSSQL], id: [1000000000009] for time: [2016-12-13T03:08:00Z]...

perf_rollup_start_re = %r{
                          ----\]\ I,\ \[(?<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6})
                          \ \#(?<pid>\h+):\h+\]
                          \ .*perf_rollup\)\ \[realtime\]\ Rollup\ for\ (?<obj_type>.+)
                          \ name:\ \[(?<obj_name>.+?)\],
                          \ id:\ \[(?<obj_id>\d+)\]
                          \ for\ time:\ \[(?<time>.+)\]\.\.\.$
                          }x

# [----] I, [2016-12-13T04:44:31.371524 #15020:11e598c]  INFO -- : MIQ(EmsCluster#perf_rollup) [realtime] Rollup for EmsCluster name: [MSSQL], id: [1000000000009] for time: [2016-12-13T03:08:00Z]...Complete - Timings: {:server_dequeue=>0.0029115676879882812, :db_find_prev_perf=>26.71201252937317, :rollup_perfs=>189.58252334594727, :db_update_perf=>156.7819893360138, :process_perfs_tag=>1.146547555923462, :process_bottleneck=>168.30106329917908, :total_time=>604.6718921661377, :purge_metrics=>12.701744079589844, :query_batch=>0.04195547103881836}

perf_rollup_complete_re = %r{
                            ----\]\ I,\ \[(?<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6})
                            \ \#(?<pid>\h+):\h+\]
                            \ .*perf_rollup\)\ \[realtime\]\ Rollup\ for\ (?<obj_type>.+)
                            \ name:\ \[(?<obj_name>.+?)\],
                            \ id:\ \[(?<obj_id>\d+)\]
                            \ for\ time:\ \[(?<time>.+)\]\.\.\.Complete\ -
                            \ Timings: (?<timings>.*$)
                            }x


# [----] I, [2016-12-13T03:43:24.621330 #21612:11e598c]  INFO -- : MIQ(MiqQueue#delivered) Message id: [1000032162564], State: [ok], Delivered in [3.849833806] seconds

message_delivered_re = %r{
                          ----\]\ I,\ \[(?<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6})
                          \ \#(?<pid>\h+):\h+\]
                          \ .*MIQ\(MiqQueue\#delivered\)\ Message\ id:\ \[(?<message_id>\d+)\],
                          \ State:\ \[(?<state>\w+)\],
                          \ Delivered\ in\ \[(?<delivered_in>.+)\]\ seconds
                          }x

# Ensure we're not evaling dubious code

@timings_re = %r{
                \{
                (?::\w+=>\d+\.?[\de-]*,?\ ?)+
                \}
                }x

begin
  options = {:inputfile => nil, :outputfile => nil}
  
  parser = OptionParser.new do|opts|
    opts.banner = "Usage: realtime_perf_rollup_timings.rb [options]"
    opts.on('-i', '--inputfile filename', 'Full file path to evm.log (if not /var/www/miq/vmdb/log/evm.log)') do |inputfile|
      options[:inputfile] = inputfile;
    end
    opts.on('-o', '--outputfile outputfile', 'Full file path to optional output file') do |outputfile|
      options[:outputfile] = outputfile;
    end
    opts.on('-h', '--help', 'Displays Help') do
      puts opts
      exit
    end
  end
  parser.parse!

  if options[:inputfile].nil?
    inputfile = "/var/www/miq/vmdb/log/evm.log"
  else
    inputfile = options[:inputfile]
  end

  messages = {}
  workers = {}
  counter = 0
  $stdout.sync = true
  File.foreach( inputfile ) do |line|

    new_message = get_message_via_drb_re.match(line)
    if new_message
      messages[new_message[:pid]] = {:timestamp   => new_message[:timestamp], 
                                     :dequeued_in => new_message[:dequeued_in],
                                     :message_id  => new_message[:message_id],
                                     :status      => 'new'}
      next
    end

    started = perf_rollup_start_re.match(line)
    if started
      counter += 1
      print "Found #{counter} realtime rollups\r"
      workers[started[:pid]] = [] unless workers.has_key?(started[:pid])
      workers[started[:pid]] << {:capture_state  => 'rollup_started', 
                                     :obj_type   => started[:obj_type],
                                     :obj_name   => started[:obj_name],
                                     :obj_id     => started[:obj_id],
                                     :time       => started[:time],
                                     :start_time => started[:timestamp]}
      current = workers[started[:pid]].length - 1
      if messages.has_key?(started[:pid])
        if messages[started[:pid]][:status] == 'new'
          workers[started[:pid]][current][:first_rollup_for_message] = true
          workers[started[:pid]][current][:last_rollup_for_message] = false
          messages[started[:pid]][:status] = ''
        else
          workers[started[:pid]][current][:first_rollup_for_message] = false
        end
        workers[started[:pid]][current][:message_id] = messages[started[:pid]][:message_id]
        workers[started[:pid]][current][:message_time] = messages[started[:pid]][:timestamp]
        workers[started[:pid]][current][:message_dequeue_time] = messages[started[:pid]][:dequeued_in]
      else
        workers[started[:pid]][current][:message_time] = "No message found"
        workers[started[:pid]][current][:message_dequeue_time] = ""
      end
      next
    end

    completed = perf_rollup_complete_re.match(line)
    if completed
      current = workers[completed[:pid]].length - 1 rescue next
      workers[completed[:pid]][current][:state]    = 'rollup_completed'
      workers[completed[:pid]][current][:end_time] = completed[:timestamp]
      workers[completed[:pid]][current][:timings]  = completed[:timings]
      next
    end

    message_delivered = message_delivered_re.match(line)
    if message_delivered
      current = workers[message_delivered[:pid]].length - 1 rescue next
      if message_delivered[:message_id] == workers[message_delivered[:pid]][current][:message_id]
        workers[message_delivered[:pid]][current][:message_delivered_time] = message_delivered[:timestamp]
        workers[message_delivered[:pid]][current][:message_state]          = message_delivered[:state]
        workers[message_delivered[:pid]][current][:message_delivered_in]   = message_delivered[:delivered_in]
        workers[message_delivered[:pid]][current][:last_rollup_for_message] = true
      end
      next
    end
  end
  stats(workers, options)

rescue => err
  puts "[#{err}]\n#{err.backtrace.join("\n")}"
  exit!
end




