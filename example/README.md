# Examples Structure

This directory contains examples demonstrating how to use `pro_mpack` effectively in various scenarios.

## 1. [Basic Usage](basic/)

A simple overview showing how to use the core API:

* **Simple Serialization**: How to encode and decode standard types.
* **Collections**: Working with Lists and Maps.
* **Reusable Instance**: High-performance caching with a `MessagePack` instance.
* **One-off Extensions**: Using `encodeExt` and `decodeExt` for quick custom types without a registry.

## 2. [Extensions in Depth](extensions/)

A focused example on how to build and register custom extensions for complex, nested data types and external classes:

* **Polymorphic Extensions**: How to register external types like `BigInt` which have internal implementations (`_BigIntImpl`).
* **Nested Groups**: Organizing relational structures (`User`, `Address`, `Product`) using `registerGroup` and `subId` to bypass the 256-ID limit.
* **Type-Safe Collections**: Decoding nested arrays of specific models efficiently using `unpackArrayOf<T>()` and `unpackAs<T>()`.
* **High Performance**: Using the `MessagePack` instance for optimized `O(1)` extension lookups.

## 3. [Incremental Codecs](incremental/)

A focused example on the low-level field-by-field primitives added in 3.1 — the shape a schema-driven code generator emits:

* **Field-by-Field Encoding**: Framing a struct as `{ fieldId: value }` with `packMapLength`/`packArrayLength` and the typed packers — no intermediate `Map`/`List` is allocated.
* **Forward Compatibility**: An old reader decoding a newer payload, dropping unknown fields with `Unpacker.skip()`.
* **Typed Decoding**: Reading a map directly into `Map<K, V>` via `unpackMapOf<K, V>()`.

## 4. [Advanced Network Streaming](network_streaming/)

A multi-file architectural example simulating a real-world IoT/Telemetry protocol:

* **Custom Models**: Encoding/decoding complex nested structures (`TelemetryPacket`, `SensorData`) using custom MessagePack extensions.
* **Fragmentation Resilience**: Proving that the `streamDecoder` can reconstruct nested packets from tiny network chunks (e.g. 5 bytes at a time) without extra allocations.
* **Zero-Allocation**: Uses `streamDecoder` to avoid GC overhead for incomplete packets.

## 5. [File Streaming (Big Data)](file_streaming/)

A high-performance example demonstrating how to process large binary files:

* **Real-world File Structure**: Demonstrates how to write and parse files with custom headers (Magic Bytes, Version) and MessagePack metadata blocks.
* **Incremental Processing**: Using `File.openRead()` and `streamDecoder` to process data without loading the entire file into RAM.
* **Market Data Simulation**: Packing and parsing 500,000 trade records (Market Ticks) on-the-fly using `Packer` batching (`takeBytes(dispose: false)`).
* **Memory Efficiency**: Maintaining a constant memory footprint regardless of file size.

---

## How to Run

You can run any example directly using the Dart CLI:

```bash
# Run the basic overview
dart example/basic/main.dart

# Run the extensions example
dart example/extensions/main.dart

# Run the incremental (field-by-field) codec example
dart example/incremental/main.dart

# Run the advanced telemetry simulation
dart example/network_streaming/main.dart

# Run the big data file streaming example
dart example/file_streaming/main.dart
```
