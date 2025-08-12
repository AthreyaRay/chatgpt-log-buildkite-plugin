#!/usr/bin/env bats

# Simple test to verify Bats is working

@test "basic test functionality" {
  run echo "Hello World"
  [ "$status" -eq 0 ]
  [ "$output" = "Hello World" ]
}

@test "plugin script exists" {
  [ -f "${BATS_TEST_DIRNAME}/../hooks/pre-exit" ]
}

@test "plugin script is executable" {
  [ -x "${BATS_TEST_DIRNAME}/../hooks/pre-exit" ]
}