#!/bin/bash

# File to append the results to
AUDIT_FILE="benchmark.md"

echo "🚀 Running AOT benchmarks..."

# 1. Run deserialization benchmark
echo "--- Deserializer Benchmark ---"
DESERIALIZE_OUT=$(dart run benchmark_harness:bench --flavor aot --target benchmark/deserializer_benchmark.dart)
# echo "$DESERIALIZE_OUT"

# 2. Run serialization benchmark
echo "--- Serializer Benchmark ---"
SERIALIZE_OUT=$(dart run benchmark_harness:bench --flavor aot --target benchmark/serializer_benchmark.dart)
# echo "$SERIALIZE_OUT"

# Extracting values (Parsing microseconds using awk/grep)
D_GEN=$(echo "$DESERIALIZE_OUT" | grep "deserialize(RunTime):" | awk '{print $4}')
D_MOD=$(echo "$DESERIALIZE_OUT" | grep "deserialize models(RunTime):" | awk '{print $5}')
S_GEN=$(echo "$SERIALIZE_OUT" | grep "serialize(RunTime):" | awk '{print $4}')
S_MOD=$(echo "$SERIALIZE_OUT" | grep "serialize models(RunTime):" | awk '{print $5}')

# Current timestamp
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

# Formatting the markdown table
echo -e "\n## Benchmark Results ($TIMESTAMP)\n" >>"$AUDIT_FILE"
echo "| Metric | Result (µs) |" >>"$AUDIT_FILE"
echo "| :--- | :--- |" >>"$AUDIT_FILE"
echo "| Deserialize (Generic) | $D_GEN |" >>"$AUDIT_FILE"
echo "| Deserialize (Models) | $D_MOD |" >>"$AUDIT_FILE"
echo "| Serialize (Generic) | $S_GEN |" >>"$AUDIT_FILE"
echo "| Serialize (Models) | $S_MOD |" >>"$AUDIT_FILE"
echo -e "\n---\n" >>"$AUDIT_FILE"

echo "✅ Results successfully appended to $AUDIT_FILE"
