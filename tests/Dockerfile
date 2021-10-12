FROM alpine:latest

RUN apk update && apk add make lua moonscript mpv python3

COPY . /app
WORKDIR /app
RUN make

ENTRYPOINT ["/usr/bin/python3", "-m", "tests.run_tests"]
