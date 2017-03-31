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
  
  non_rollup_counters = [:purge_metrics,:server_dequeue,:query_batch]
  rollup_counters     = [:db_find_prev_perf,:rollup_perfs,:db_update_perf,:process_perfs_tag,:process_bottleneck,:total_time]

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
      o.puts "Message ID:                    #{rollup[:message_id]}"
      o.puts "Message fetch time:            #{rollup[:message_time]}"
      o.puts "Message time in queue:         #{rollup[:message_dequeue_time]} seconds"
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
      o.puts "Message delivered time:        #{rollup[:message_delivered_time]}"
      o.puts "Message state:                 #{rollup[:message_state]}"
      o.puts "Message delivered in:          #{rollup[:message_delivered_in]} seconds"
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

# [----] I, [2016-12-13T03:56:52.411916 #1439:11e598c]  INFO -- : MIQ(ManageIQ::Providers::Vmware::InfraManager::HostEsx#perf_rollup) [hourly] Rollup for ManageIQ::Providers::Vmware::InfraManager::HostEsx name: [vs3.vi.grp.net - 2], id: [1000000000063] for time: [2016-12-13T01:00:00Z]...
# [----] I, [2017-01-29T12:00:45.773098 #27858:66b14c]  INFO -- : MIQ(MiqEnterprise#perf_rollup) [hourly] Rollup for MiqEnterprise name: [Enterprise], id: [1000000000001] for time: [2017-01-29T10:00:00Z]...
# [----] I, [2017-01-29T12:00:45.775557 #23910:66b14c]  INFO -- : MIQ(EmsCluster#perf_rollup) [hourly] Rollup for EmsCluster name: [Cluster AMD], id: [1000000000003] for time: [2017-01-29T10:00:00Z]...
# [----] I, [2017-01-29T04:01:18.224366 #14717:66b14c]  INFO -- : MIQ(MiqRegion#perf_rollup) [hourly] Rollup for MiqRegion name: [Region 1], id: [1000000000001] for time: [2017-01-29T02:00:00Z]...

perf_rollup_start_re = %r{
                          ----\]\ I,\ \[(?<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6})
                          \ \#(?<pid>\h+):\h+\]
                          \ .*perf_rollup\)\ \[hourly\]\ Rollup\ for\ (?<obj_type>.+)
                          \ name:\ \[(?<obj_name>.+?)\],
                          \ id:\ \[(?<obj_id>\d+)\]
                          \ for\ time:\ \[(?<time>.+)\]\.\.\.$
                          }x

# [----] I, [2016-12-13T03:56:52.847443 #1439:11e598c]  INFO -- : MIQ(ManageIQ::Providers::Vmware::InfraManager::HostEsx#perf_rollup) [hourly] Rollup for ManageIQ::Providers::Vmware::InfraManager::HostEsx name: [vs3.vi.grp.net - 2], id: [1000000000063] for time: [2016-12-13T01:00:00Z]...Complete - Timings: {:server_dequeue=>0.0039708614349365234, :db_find_prev_perf=>1.322969675064087, :rollup_perfs=>9.462254285812378, :db_update_perf=>3.2071571350097656, :process_perfs_tag=>70.51743388175964, :process_bottleneck=>10.498109817504883, :total_time=>97.70416975021362}
# [----] I, [2017-02-21T10:00:46.693621 #20238:33d13c]  INFO -- : MIQ(MiqRegion#perf_rollup) [hourly] Rollup for MiqRegion name: [Region 0], id: [1] for time: [2017-02-21T09:00:00Z]...Complete - Timings: {:server_dequeue=>0.0029115676879882812, :db_find_prev_perf=>26.722290515899658, :rollup_perfs=>189.67185926437378, :db_update_perf=>156.79570960998535, :process_perfs_tag=>1.1467986106872559, :process_bottleneck=>169.6373643875122, :total_time=>606.1658205986023, :purge_metrics=>12.701744079589844, :query_batch=>0.04195547103881836}
# [----] I, [2017-02-21T10:00:43.502162 #20238:33d13c]  INFO -- : MIQ(MiqEnterprise#perf_rollup) [hourly] Rollup for MiqEnterprise name: [Enterprise], id: [1] for time: [2017-02-21T09:00:00Z]...Complete - Timings: {:server_dequeue=>0.0029115676879882812, :db_find_prev_perf=>26.71651792526245, :rollup_perfs=>189.6120822429657, :db_update_perf=>156.78874564170837, :process_perfs_tag=>1.1466748714447021, :process_bottleneck=>169.6322898864746, :total_time=>606.0528314113617, :purge_metrics=>12.701744079589844, :query_batch=>0.04195547103881836}
# [----] I, [2017-02-21T10:00:42.076955 #20238:33d13c]  INFO -- : MIQ(EmsCluster#perf_rollup) [hourly] Rollup for EmsCluster name: [Default], id: [1] for time: [2017-02-21T09:00:00Z]...Complete - Timings: {:server_dequeue=>0.0029115676879882812, :db_find_prev_perf=>26.71201252937317, :rollup_perfs=>189.58252334594727, :db_update_perf=>156.7819893360138, :process_perfs_tag=>1.146547555923462, :process_bottleneck=>168.30106329917908, :total_time=>604.6718921661377, :purge_metrics=>12.701744079589844, :query_batch=>0.04195547103881836}

perf_rollup_complete_re = %r{
                            ----\]\ I,\ \[(?<timestamp>\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6})
                            \ \#(?<pid>\h+):\h+\]
                            \ .*perf_rollup\)\ \[hourly\]\ Rollup\ for\ (?<obj_type>.+)
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
    opts.banner = "Usage: hourly_perf_rollup_timings.rb [options]"
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
                                     :message_id  => new_message[:message_id]}
      next
    end

    started = perf_rollup_start_re.match(line)
    if started
      counter += 1
      print "Found #{counter} hourly rollups\r"
      workers[started[:pid]] = [] unless workers.has_key?(started[:pid])
      workers[started[:pid]] << {:capture_state  => 'rollup_started', 
                                     :obj_type   => started[:obj_type],
                                     :obj_name   => started[:obj_name],
                                     :obj_id     => started[:obj_id],
                                     :time       => started[:time],
                                     :start_time => started[:timestamp]}
      current = workers[started[:pid]].length - 1
      if messages.has_key?(started[:pid])
        workers[started[:pid]][current][:message_id] = messages[started[:pid]][:message_id]
        workers[started[:pid]][current][:message_time] = messages[started[:pid]][:timestamp]
        workers[started[:pid]][current][:message_dequeue_time] = messages[started[:pid]][:dequeued_in]
        messages.delete(started[:pid])
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
      end
      next
    end
  end
  stats(workers, options)

rescue => err
  puts "[#{err}]\n#{err.backtrace.join("\n")}"
  # puts "#{perf_rollup_workers.inspect}"
  exit!
end




