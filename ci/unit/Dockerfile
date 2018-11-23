ARG ELASTIC_STACK_VERSION
FROM docker.elastic.co/logstash/logstash:$ELASTIC_STACK_VERSION
COPY --chown=logstash:logstash Gemfile /usr/share/plugins/this/Gemfile
COPY --chown=logstash:logstash *.gemspec /usr/share/plugins/this/
RUN cp /usr/share/logstash/logstash-core/versions-gem-copy.yml /usr/share/logstash/versions.yml
ENV PATH="${PATH}:/usr/share/logstash/vendor/jruby/bin"
ENV LOGSTASH_SOURCE=1
ENV JARS_SKIP="true"
RUN gem install bundler
WORKDIR /usr/share/plugins/this
RUN bundle install
COPY --chown=logstash:logstash . /usr/share/plugins/this
