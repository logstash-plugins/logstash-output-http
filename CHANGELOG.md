## 4.1.0
 - Allow nested field definitions in `mappings`

## 4.0.0
 - Major overhaul of internals, adds new retry options
 - Allow users to specify non-standard response codes as ignorable
 - Set concurrency level to shared allowing for greater efficiency across threads
 
## 3.1.1
  - Relax constraint on logstash-core-plugin-api to >= 1.60 <= 2.99

## 3.1.0
 - breaking,config: Remove deprecated config 'verify_ssl'. Please use 'ssl_certificate_validation'.

## 3.0.1
 - Republish all the gems under jruby.

## 3.0.0
 - Update the plugin to the version 2.0 of the plugin api, this change is required for Logstash 5.0 compatibility. See https://github.com/elastic/logstash/issues/5141

## 2.1.3
 - Depend on logstash-core-plugin-api instead of logstash-core, removing the need to mass update plugins on major releases of logstash

## 2.1.2
 - New dependency requirements for logstash-core for the 5.0 release

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

## 1.1.0
 - Concurrent execution
 - Add many HTTP options via the http_client mixin
 - Switch to manticore as HTTP Client
