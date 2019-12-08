FROM ruby:2.6-alpine

ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8
ENV GEM_HOME="/usr/local/bundle"
ENV PATH $GEM_HOME/bin:$GEM_HOME/gems/bin:$PATH

RUN apk add --update --no-cache build-base --quiet

WORKDIR /app

COPY Gemfile Gemfile.lock ./
COPY vendor/cache ./vendor/cache
RUN gem install bundler --no-document
RUN bundle install --deployment --local --jobs 4 --quiet --without development test

COPY . .

CMD bundle exec ruby lib/sync_wp_to_static.rb