#!/bin/sh
# Test runner script for the ChatGPT Log Buildkite Plugin

set -e

echo "--- Installing test dependencies"
apk add --no-cache curl jq git

echo "--- Setting up Bats test helpers"
mkdir -p tests/test_helper
git clone --depth 1 https://github.com/bats-core/bats-support tests/test_helper/bats-support
git clone --depth 1 https://github.com/bats-core/bats-assert tests/test_helper/bats-assert

echo "--- Running Bats tests"
bats --tap tests/