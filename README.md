# dslink-dart-influxdb

This historical DSLink uses the InfluxDB client to write changes to monitored nodes directly to the InfluxDB database. This link integrates with DSA (Distributed Services Architecture) and can be used to stream historical data to platforms like DGLux5 for visualization and analysis.

## About

- **InfluxDB**: A time-series database designed for high-performance handling of time-stamped data, often used for monitoring metrics and IoT data storage. This link utilizes InfluxDB to store historical data and make it accessible for further analytics.
- **DSA (Distributed Services Architecture)**: A protocol and framework designed to enable efficient communication between distributed services in real-time, used for building IoT and other data-driven applications.
- **DGLux5**: A powerful visualization tool used in conjunction with DSA and InfluxDB for creating interactive dashboards and data visualizations. DGLux5 can access data stored in InfluxDB through DSLinks, making it a valuable tool for visualizing and analyzing historical data from InfluxDB.

## Distributions

The DSLink for InfluxDB can be distributed in several ways:

1. **Building from Source**: Clone the repository and build the DSLink manually. This allows for the latest code changes to be compiled and used directly.
2. **Fetching Artifacts from a Repository**: Artifacts are available in the central repository, which can be directly downloaded and deployed. This is convenient for those looking to avoid a manual build.
3. **Using a Docker Image**: A prebuilt Docker image is available, enabling quick deployment of the DSLink in a containerized environment. This is ideal for cloud or isolated environment deployment.

## Running with the Dart SDK

You can run the DSLink with the [Dart SDK](https://dart.dev/get-dart) like this:

```bash
$ dart run bin/dslink.dart -b https://localhost:443/conn
```

## Running with Docker

If you have [Docker Desktop](https://www.docker.com/get-started) installed, you
can build and run the DSLink with Docker:

```bash
# Build the Docker image
$ docker build . -t dslink-dart-influxdb

# Run the Docker container
$ docker run -it dslink-dart-influxdb
```

You can configure environment variables when running the Docker container to adjust the DSLink’s connection settings:

```bash
docker run -it -e BROKER_URL=https://localhost:443/conn \
               -e LINK_TOKEN="your_token" \
               -e LINK_NAME="dslink-dart-influxdb" \
               -e LINK_LOG_LEVEL="info" \
               dslink-dart-influxdb
```

This DSLink is a powerful component for integrating DSA-based solutions with InfluxDB, making it possible to manage and visualize historical data in platforms like DGLux5.