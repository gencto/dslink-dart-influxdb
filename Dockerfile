# Use latest stable channel SDK.
FROM dart:stable AS build

# Resolve app dependencies.
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

# Copy app source code (except anything in .dockerignore) and AOT compile app.
COPY . .
RUN dart compile exe bin/dslink.dart -o bin/dslink

# Build minimal serving image from AOT-compiled `/dslink`
# and the pre-built AOT-runtime in the `/runtime/` directory of the base image.
FROM scratch

ENV BROKER_URL=https://127.0.0.1:8443/conn
ENV LINK_TOKEN=""
ENV LINK_NAME="dslink-dart-influxdb"
ENV LINK_LOG_LEVEL="info"

COPY --from=build /runtime/ /
COPY --from=build /app/bin/dslink /app/bin/

CMD ["/app/bin/dslink", "--broker", "$BROKER_URL", "--name", "$LINK_NAME", "--log", "$LINK_LOG_LEVEL"]
