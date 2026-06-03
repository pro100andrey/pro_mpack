# Examples Structure

This directory contains examples demonstrating how to use `pro_mpack` effectively in various scenarios.

## 1. [Basic Usage](basic/)

A simple overview showing how to use the core API:

* **Simple Serialization**: How to encode and decode standard types.
* **Collections**: Working with Lists and Maps.
* **Basic Extension**: A quick look at custom extensions.

## 2. [Extensions in Depth](extensions/)

A focused example on how to build and register custom extensions for complex data types:

* **Data Classes**: Encoding custom objects like `Point` or `Color`.
* **High Performance**: Using the `MessagePack` instance for optimized `O(1)` extension lookups.

## 3. [Advanced Network Streaming](network_streaming/)

A multi-file architectural example simulating a real-world IoT/Telemetry protocol:

* **Custom Models**: Encoding/decoding complex nested structures (`TelemetryPacket`, `SensorData`) using custom MessagePack extensions.
* **Fragmentation Resilience**: Proving that the `streamDecoder` can reconstruct nested packets from tiny network chunks (e.g. 5 bytes at a time) without extra allocations.
* **Zero-Allocation**: Uses `streamDecoder` to avoid GC overhead for incomplete packets.

## 4. [File Streaming (Big Data)](file_streaming/)

A high-performance example demonstrating how to process large binary files:

* **Incremental Processing**: Using `File.openRead()` and `streamDecoder` to process data without loading the entire file into RAM.
* **Market Data Simulation**: Packing and parsing 250,000+ trade records (Market Ticks) on-the-fly.
* **Memory Efficiency**: Maintaining a constant memory footprint regardless of file size.

---

## How to Run

You can run any example directly using the Dart CLI:

```bash
# Run the basic overview
dart example/basic/main.dart

# Run the extensions example
dart example/extensions/main.dart

# Run the advanced telemetry simulation
dart example/network_streaming/main.dart

# Run the big data file streaming example
dart example/file_streaming/main.dart
```
