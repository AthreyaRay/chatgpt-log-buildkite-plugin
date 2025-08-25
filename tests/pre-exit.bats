#!/usr/bin/env bats

# This is the main test file for the ChatGPT Log Buildkite Plugin
# Bats (Bash Automated Testing System) helps us test our shell scripts

# Load our custom test helper (comment out external helpers for now)
# load 'test_helper/bats-support/load'
# load 'test_helper/bats-assert/load'  
load 'test_helper'

# Setup function runs before each test
setup() {
  # Create a temporary directory for each test to avoid conflicts
  export BATS_TEST_TMPDIR="$(mktemp -d)"
  
  # Set up mock environment variables that the plugin expects
  export BUILDKITE_JOB_LOG_TMPFILE="${BATS_TEST_TMPDIR}/job.log"
  export BUILDKITE_JOB_ID="test-job-123"
  
  # Create a fake log file with test content
  echo "Sample build output" > "$BUILDKITE_JOB_LOG_TMPFILE"
  echo "Error: npm test failed" >> "$BUILDKITE_JOB_LOG_TMPFILE"
  echo "Exit code: 1" >> "$BUILDKITE_JOB_LOG_TMPFILE"
  
  # Copy the actual plugin script to our test directory so we can test it
  cp "${BATS_TEST_DIRNAME}/../hooks/pre-exit" "${BATS_TEST_TMPDIR}/pre-exit"
  chmod +x "${BATS_TEST_TMPDIR}/pre-exit"
}

# Teardown function runs after each test to clean up
teardown() {
  # Remove the temporary test directory
  rm -rf "$BATS_TEST_TMPDIR"
}

# TEST 1: Plugin should skip analysis for successful jobs (exit status 0)
@test "skips analysis when job succeeds (exit status 0)" {
  # Set the job exit status to 0 (success)
  export BUILDKITE_JOB_EXIT_STATUS="0"
  
  # Run the plugin script
  run "${BATS_TEST_TMPDIR}/pre-exit"
  
  # Verify the script succeeded and skipped analysis
  [ "$status" -eq 0 ]  # Script should exit with status 0
  [[ "$output" == *"Job succeeded, skipping ChatGPT analysis"* ]]  # Should contain this message
}

# TEST 2: Plugin should attempt analysis for failed jobs (exit status != 0)
@test "attempts analysis when job fails (exit status 1)" {
  # Set the job exit status to 1 (failure)
  export BUILDKITE_JOB_EXIT_STATUS="1"
  export BUILDKITE_PIPELINE_SLUG="test-pipeline"
  export BUILDKITE_BRANCH="main"
  export BUILDKITE_STEP_KEY="test-step"
  export BUILDKITE_JOB_ID="test-job-123"
  
  # Make sure all plugin environment variables are set
  export BUILDKITE_PLUGIN_CHATGPT_LOGS_MAX_TOKENS="1500"
  export BUILDKITE_PLUGIN_CHATGPT_LOGS_MODEL="gpt-4o-mini"
  export BUILDKITE_PLUGIN_CHATGPT_LOGS_MAX_LOG_LINES="600"
  export BUILDKITE_PLUGIN_CHATGPT_LOGS_TIMEOUT="30"
  
  # Create a sample failure log
  create_sample_log_file "$BUILDKITE_JOB_LOG_TMPFILE" "failure"
  
  # Mock system commands
  mock_system_commands
  
  # Mock additional commands that might be missing
  function grep() {
    case "$*" in
      *"error\|failed\|exception"*)
        echo "Error: npm test failed with exit code 1"
        echo "TypeError: Cannot read property 'map' of undefined"
        ;;
      *)
        command grep "$@" 2>/dev/null || true
        ;;
    esac
  }
  export -f grep
  
  function tail() {
    case "$*" in
      *"-n"*)
        echo "Sample build output"
        echo "Error: npm test failed"
        echo "Exit code: 1"
        ;;
      *)
        command tail "$@" 2>/dev/null || true
        ;;
    esac
  }
  export -f tail
  
  # Mock cp command
  function cp() {
    # Just succeed silently for cp operations
    return 0
  }
  export -f cp
  
  # Mock printf command
  function printf() {
    echo "$@"
  }
  export -f printf
  
  # Mock buildkite-agent secret command to return a fake API key
  # This creates a fake buildkite-agent command that returns our test key
  function buildkite-agent() {
    if [[ "$1" == "secret" && "$2" == "get" && "$3" == "open_ai_key" ]]; then
      echo "sk-test-api-key-12345"
    elif [[ "$1" == "annotate" ]]; then
      # Mock the annotate command to just echo what it receives
      cat > /dev/null
    else
      # For any other buildkite-agent command, just return success
      return 0
    fi
  }
  export -f buildkite-agent  # Make the function available to the script
  
  # Mock curl command to return a fake ChatGPT response
  function curl() {
    # Return a mock OpenAI API response in JSON format
    echo '{"choices":[{"message":{"content":"The test failed because npm test could not find the test files. Try running npm install first."}}]}'
  }
  export -f curl  # Make the function available to the script
  
  # Mock jq command to parse JSON (just return the content for simplicity)
  function jq() {
    if [[ "$1" == "-Rs" ]]; then
      # When escaping for JSON, just pass through with quotes
      sed 's/^/"/' | sed 's/$/"/'
    elif [[ "$1" == "-er" ]]; then
      # When extracting content, return our mock suggestion
      echo "The test failed because npm test could not find the test files. Try running npm install first."
    else
      # Default jq behavior
      command jq "$@" 2>/dev/null || echo "mock-jq-output"
    fi
  }
  export -f jq  # Make the function available to the script
  
  # Run the plugin script
  run "${BATS_TEST_TMPDIR}/pre-exit"
  
  # Verify the script ran the analysis process
  [ "$status" -eq 0 ]  # Script should complete successfully
  [[ "$output" == *"Job failed (exit status: 1), analyzing with ChatGPT"* ]]  # Should show it's analyzing
  [[ "$output" == *"Copying Buildkite job log"* ]]  # Should copy the log
  [[ "$output" == *"Sending log to ChatGPT for analysis"* ]]  # Should send to API
}

# TEST 3: Plugin should handle missing log file gracefully
@test "handles missing job log file" {
  # Set up a failed job but remove the log file
  export BUILDKITE_JOB_EXIT_STATUS="1"
  rm "$BUILDKITE_JOB_LOG_TMPFILE"  # Remove the log file
  
  # Run the plugin script
  run "${BATS_TEST_TMPDIR}/pre-exit"
  
  # The script should fail because it can't find the log file
  [ "$status" -ne 0 ]  # Script should exit with non-zero status
  # The exact error message depends on how the script handles missing files
}

# TEST 4: Plugin should handle API key retrieval failure
@test "handles missing API key gracefully" {
  export BUILDKITE_JOB_EXIT_STATUS="1"
  
  # Mock buildkite-agent to fail when getting the secret
  function buildkite-agent() {
    if [[ "$1" == "secret" && "$2" == "get" && "$3" == "open_ai_key" ]]; then
      echo "Error: Secret not found" >&2
      return 1  # Fail the secret retrieval
    else
      return 0
    fi
  }
  export -f buildkite-agent
  
  # Run the plugin script
  run "${BATS_TEST_TMPDIR}/pre-exit"
  
  # The script should fail because it can't get the API key
  [ "$status" -ne 0 ]  # Script should exit with non-zero status
}

# TEST 5: Plugin should clean up temporary files
@test "cleans up temporary log file" {
  export BUILDKITE_JOB_EXIT_STATUS="1"
  export BUILDKITE_PIPELINE_SLUG="test-pipeline"
  export BUILDKITE_BRANCH="main"
  export BUILDKITE_STEP_KEY="test-step"
  export BUILDKITE_JOB_ID="test-job-123"
  
  # Create a sample failure log
  create_sample_log_file "$BUILDKITE_JOB_LOG_TMPFILE" "failure"
  
  # Mock system commands
  mock_system_commands
  
  # Mock all the external commands to succeed
  function buildkite-agent() {
    if [[ "$1" == "secret" && "$2" == "get" && "$3" == "open_ai_key" ]]; then
      echo "sk-test-key"
    elif [[ "$1" == "annotate" ]]; then
      cat > /dev/null  # Ignore annotation content
    fi
    return 0
  }
  export -f buildkite-agent
  
  function curl() {
    echo '{"choices":[{"message":{"content":"Test suggestion"}}]}'
  }
  export -f curl
  
  function jq() {
    if [[ "$1" == "-Rs" ]]; then
      sed 's/^/"/' | sed 's/$/"/'
    elif [[ "$1" == "-er" ]]; then
      echo "Test suggestion"
    else
      command jq "$@" 2>/dev/null || echo "mock-jq-output"
    fi
  }
  export -f jq
  
  # Run the plugin script
  run "${BATS_TEST_TMPDIR}/pre-exit"
  
  # Verify the script succeeded
  [ "$status" -eq 0 ]
  
  # Check that the temporary log file was cleaned up
  # The script creates ./buildkite-job.log and should remove it
  [ ! -f "${BATS_TEST_TMPDIR}/buildkite-job.log" ]
}

# TEST 6: Plugin should handle different exit statuses correctly
@test "handles various non-zero exit statuses" {
  # Test with exit status 2 (another common failure code)
  export BUILDKITE_JOB_EXIT_STATUS="2"
  
  # Mock the commands minimally
  function buildkite-agent() { return 0; }
  function curl() { echo '{"choices":[{"message":{"content":"test"}}]}'; }
  function jq() { 
    if [[ "$1" == "-Rs" ]]; then cat; 
    elif [[ "$1" == "-er" ]]; then echo "test"; 
    fi
  }
  export -f buildkite-agent curl jq
  
  # Run the plugin script
  run "${BATS_TEST_TMPDIR}/pre-exit"
  
  # Should still attempt analysis for non-zero exit status
  [[ "$output" == *"Job failed (exit status: 2), analyzing with ChatGPT"* ]]
}