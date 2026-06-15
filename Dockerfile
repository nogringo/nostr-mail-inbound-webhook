# Use latest stable channel SDK.
FROM dart:stable AS build

# NDK ships a native Rust code asset. The Dart build hook expects rustup to
# install/use the pinned toolchain from the package.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        pkg-config \
    && rm -rf /var/lib/apt/lists/*
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

# Resolve app dependencies.
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get

# Copy app source code (except anything in .dockerignore) and AOT compile app.
COPY . .
RUN dart build cli --target bin/server.dart -o output

# Build a small runtime image from the AOT-compiled `/server`.
# `idb_sqflite` uses SQLite through FFI, so the final image needs libsqlite3.
FROM debian:trixie-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        libsqlite3-0 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/output/bundle/ /app/

# Start server.
EXPOSE 8080
CMD ["/app/bin/server"]
