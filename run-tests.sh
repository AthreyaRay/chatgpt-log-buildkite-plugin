#!/bin/sh
# Test runner script for the ChatGPT Log Buildkite Plugin

set -e

echo "--- Installing test dependencies"
apk add --no-cache curl jq

echo "--- Running Bats tests"
bats --tap tests/