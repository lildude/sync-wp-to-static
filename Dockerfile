FROM ruby:2.6-alpine

ENV LC_ALL C.UTF-8
ENV LANG en_US.UTF-8
ENV LANGUAGE en_US.UTF-8

RUN apk add --update --no-cache build-base --quiet

WORKDIR /app

COPY Gemfile Gemfile.lock ./
COPY vendor/cache ./vendor/cache
RUN gem install bundler --no-document && \
    bundle config set deployment 'true' && \
    bundle config set without 'development test'
RUN bundle install --local --jobs 4

COPY . .

ENTRYPOINT [ "/bin/run" ]