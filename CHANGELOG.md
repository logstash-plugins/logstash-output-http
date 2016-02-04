## 2.1.1
 - Require http_client mixin with better keepalive handling

## 2.1.0
 - Properly close the client on #close
 - Optimized execution for Logstash 2.2 ng pipeline

## 2.0.5
 - fixed memory leak

## 2.0.3
 - fixed potential race condition on async callbacks
 - silenced specs equest logs and other spec robustness fixes

## 2.0.0
 - Plugins were updated to follow the new shutdown semantic, this mainly allows Logstash to instruct input plugins to terminate gracefully,
   instead of using Thread.raise on the plugins' threads. Ref: https://github.com/elastic/logstash/pull/3895
 - Dependency on logstash-core update to 2.0

* 1.1.0
  - Concurrent execution
  - Add many HTTP options via the http_client mixin
  - Switch to manticore as HTTP Client