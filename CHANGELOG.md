## 5.7.0
  - Added new `ssl_enabled` setting for enabling/disabling the SSL configurations [#144](https://github.com/logstash-plugins/logstash-output-http/pull/144)

## 5.6.1
  - Added body logging for non 2xx responses [#142](https://github.com/logstash-plugins/logstash-output-http/pull/142)

## 5.6.0
  - Added standardized SSL settings and deprecates their non-standard counterparts. Deprecated settings will continue to work, and will provide pipeline maintainers with guidance toward using their standardized counterparts [#140](https://github.com/logstash-plugins/logstash-output-http/pull/140)
  - Added new `ssl_truststore_path`, `ssl_truststore_password`, and `ssl_truststore_type` settings for configuring SSL-trust using a PKCS-12 or JKS trust store, deprecating their `truststore`, `truststore_password`, and `truststore_type` counterparts.
  - Added new `ssl_certificate_authorities` setting for configuring SSL-trust using a PEM-formatted list certificate authorities, deprecating its `cacert` counterpart.
  - Added new `ssl_keystore_path`, `ssl_keystore_password`, and `ssl_keystore_type` settings for configuring SSL-identity using a PKCS-12 or JKS key store, deprecating their `keystore`, `keystore_password`, and `keystore_type` counterparts.
  - Added new `ssl_certificate` and `ssl_key` settings for configuring SSL-identity using a PEM-formatted certificate/key pair, deprecating their `client_cert` and `client_key` counterparts. 
  - Added the `ssl_cipher_suites` option

## 5.5.0
  - Feat: added `ssl_supported_protocols` option [#131](https://github.com/logstash-plugins/logstash-output-http/pull/131)

## 5.4.1
  - Fix retry indefinitely in termination process. This feature requires Logstash 8.1 [#129](https://github.com/logstash-plugins/logstash-output-http/pull/129)
  - Docs: Add retry policy description [#130](https://github.com/logstash-plugins/logstash-output-http/pull/130)

## 5.4.0
  - Introduce retryable unknown exceptions for "connection reset by peer" and "timeout" [#127](https://github.com/logstash-plugins/logstash-output-http/pull/127)

## 5.3.0
  - Feat: support ssl_verification_mode option [#126](https://github.com/logstash-plugins/logstash-output-http/pull/126)

## 5.2.5
  - Reduce amount of default logging on a failed request [#122](https://github.com/logstash-plugins/logstash-output-http/pull/122)

## 5.2.4
  - Relax dependency on http_client mixin since current major works on both

## 5.2.3
  - Fixed handling of empty `retryable_codes` [#99](https://github.com/logstash-plugins/logstash-output-http/pull/99)

## 5.2.2
  - Fix high CPU usage on retries in json_batch mode. [#89](https://github.com/logstash-plugins/logstash-output-http/pull/89)
  - Enable compression in json_batch mode. [#89](https://github.com/logstash-plugins/logstash-output-http/pull/89)

## 5.2.1
  - Docs: Set the default_codec doc attribute.

## 5.2.0
  - Added json_batch format
  - Make 429 responses log at debug, not error level. They are really just flow control

## 5.1.2
  - Add check to avoid hanging pipeline if an empty event array is passed in. #80

## 5.1.1
  - Update gemspec summary

## 5.1.0
  - Adding a new option `http_compression` for sending compressed payload with the `Content-Encoding: gzip` header to the configured http endpoint #66

## 5.0.1
  - Fix some documentation issues

## 5.0.0
 - Breaking: bump dependency in breaking version of logstash-mixin-http_client

## 4.3.3
 - Docs: Add plugin description.

## 4.3.2
 - Docs: Update plugin title.

## 4.3.1
 - Fix deadlock that could occur in certain situations. All users should upgrade to the latest version.
   This deadlock was caused by certain async HTTP APIs being called out of order thus creating a race.

## 4.3.0
 - Add `user` and `password` options to support HTTP basic auth
 
## 4.2.0
 - Allow nested array in field definition, See https://github.com/logstash-plugins/logstash-output-http/pull/53

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
