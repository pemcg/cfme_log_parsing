# CFME Log Parsing Scripts

These scripts were written to extract the realtime timings from evm.log lines for EMS refresh, and C&U capture and rollup, working around https://bugzilla.redhat.com/show_bug.cgi?id=1424716.

A typical log line is as follows:

```
[----] I, [2016-12-15T03:37:25.456065 #10563:11e598c]  INFO -- : MIQ(ManageIQ::Providers::Vmware::InfraManager::Vm#perf_capture) [realtime] Capture for ManageIQ::Providers::Vmware::InfraManager::Vm name: [testvm], id: [1000000001397]...Complete - Timings: {:server_dequeue=>0.006188631057739258, :capture_state=>6250.303825616837, :vim_connect=>224820.71756744385, :capture_intervals=>143243.7571492195, :capture_counters=>212285.63348317146, :build_query_params=>196.97519159317017, :num_vim_queries=>1, :vim_execute_time=>281717.0007259846, :perf_processing=>12701.634838581085, :num_vim_trips=>1, :total_time=>1432843.7386136055, :process_counter_values=>12344.215778827667, :db_find_prev_perfs=>2020.4882094860077, :process_perfs=>57061.336858034134, :process_perfs_db=>400192.8604836464, :db_find_storage_files=>152.52931928634644, :init_attrs=>728.9446852207184, :process_perfs_tag=>1806.437477350235, :process_bottleneck=>7600.513473749161}
```

If the scripts are run with no arguments they will search for /var/www/miq/vmdb/log/evm.log, otherwise specify -i and an inputfile (and optionally -o and an output file).

The output for each action is wrapped with the timings of the corresponding message that triggered the action, so as to sanity-check the timings (the "Message delivered in" should be slightly more than the total action time).

The first action printed often has incorrect timings (if there are no previous timing values to subtract), but subsequent actions should be correct.

To extract all EMS Refresh timings from the log file, use: ```ruby ems_refresh_timings.rb -i evm.log```

```
...
---
Worker PID:             4604
Message ID:             1154740
Message fetch time:     2017-03-31T08:54:07.618911
Message time in queue:  11.581588432 seconds
Provider:               Redhat::InfraManager
EMS Name:               RHEV
Refresh type:           targeted
Refresh targets:        Vm: 1
Refresh start time:     2017-03-31T08:54:07.629444
Refresh timings:
  collect_inventory_for_targets:       0.768543 seconds
  parse_inventory:                     0.000432 seconds
  parse_targeted_inventory:            0.000510 seconds
  save_inventory:                      0.417365 seconds
  fetch_vm_data:                       0.448297 seconds
  ems_refresh:                         1.186976 seconds
Refresh end time:       2017-03-31T08:54:08.816679
Message delivered time: 2017-03-31T08:54:08.866894
Message state:          ok
Message delivered in:   1.247759164 seconds
---
...
```

To extract all C&U capture and process timings from the log file, use: ```ruby perf_process_timings.rb -i evm.log```

```
...
---
Worker PID:                    46492
Message ID:                    1576
Message fetch time:            2017-03-10T10:01:16.116989
Message time in queue:         40.47977411 seconds
Provider:                      Openstack::CloudManager
Object type:                   Vm
Object name:                   websrv03
Metrics processing start time: 2017-03-10T10:01:16.119431
Time range:                    2017-03-10T13:00:20+00:00 - 2017-03-10T14:50:00+00:00
Rows added:                    330
Rows updated:                  0
Capture state:                 capture_complete
Capture timings:
  capture_state:                       0.015219 seconds
  connect:                             0.700437 seconds
  capture_counters:                    0.145125 seconds
  capture_counter_values:              0.631272 seconds
Process timings:
  process_counter_values:              0.004998 seconds
  db_find_prev_perfs:                  0.006424 seconds
  process_perfs:                       0.338341 seconds
  process_perfs_db:                    1.468559 seconds
Metrics processing end time:   2017-03-10T10:01:19.488251
Message delivered time:        2017-03-10T10:01:19.488378
Message state:                 ok
Message delivered in:          3.371304091 seconds
---
...
```

To extract all C&U hourly rollup timings from the log file, use: ``` ruby hourly_perf_rollup_timings.rb -i evm.log```

```
...
---
Worker PID:                    14717
Message ID:                    936496
Message fetch time:            2017-01-29T04:24:11.456480
Message time in queue:         6.088957682 seconds
Rollup processing start time:  2017-01-29T04:24:11.463422
Object Type:                   ManageIQ::Providers::Vmware::InfraManager::Vm
Object Name:                   wood545
Time:                          2017-01-29T02:00:00Z
Rollup timings:
  server_dequeue:                      0.000000
  server_monitor:                      0.000000
  db_find_prev_perf:                   0.005566
  rollup_perfs:                        0.126277
  db_update_perf:                      0.026837
  process_perfs_tag:                   0.000024
  process_bottleneck:                  0.006419
  total_time:                          0.196712
Rollup processing end time:    2017-01-29T04:24:11.660251
Message delivered time:        2017-01-29T04:24:11.660422
Message state:                 ok
Message delivered in:          0.203841732 seconds
---
...
```

To extract all C&U daily rollup timings from the log file, use: ``` ruby daily_perf_rollup_timings.rb -i evm.log```

```
...
---
Worker PID:                    10550
Message ID:                    924629
Message fetch time:            2017-01-30T01:01:01.302901
Message time in queue:         82783.027900505 seconds
Rollup processing start time:  2017-01-30T01:01:01.306173
Object Type:                   ManageIQ::Providers::Vmware::InfraManager::Vm
Object Name:                   wood118
Time:                          2017-01-29T00:00:00Z
Rollup timings:
  server_dequeue:                      0.000000
  db_find_prev_perf:                   0.005237
  rollup_perfs:                        0.111509
  db_update_perf:                      0.035400
  process_perfs_tag:                   0.000029
  process_bottleneck:                  0.000000
  total_time:                          0.152221
  purge_metrics:                       0.000000
Rollup processing end time:    2017-01-30T01:01:01.458519
Message delivered time:        2017-01-30T01:01:01.458750
Message state:                 ok
Message delivered in:          0.155730881 seconds
---
...
```

An output file can be useful for further analysis, for example to plot the ems_refresh times for refreshes of a single VM, use a line similar to:

```
grep -A 13 "Vm: 1$" ems_refresh_timings.out | grep ems_refresh | awk {'print $2'}
10.349132
13.402987
10.005210
7.622060
9.256805
17.645049
7.689007
6.217958
6.563067
7.479770
9.267310
6.394239
13.201423
7.942422
24.049659
10.130635
9.506425
7.815337
6.834019
6.594367
14.510838
5.968529
9.137318
11.758176
7.622280
40.144298
87.097816
32.962662
13.777533
8.724405
10.260008
20.032295
16.335240
72.853026
9.043513
6.052773
5.814235
8.883258
9.928022
9.393231
...
```