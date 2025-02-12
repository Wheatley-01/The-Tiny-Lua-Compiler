#!/bin/bash

# Test only Lua 5.1
lua_versions=("lua5.1")

# Loop through each version and run the tests
for version in "${lua_versions[@]}"; do
  # Check if the version is installed
  if command -v $version > /dev/null 2>&1; then
    echo "Running tests with $version..."
    $version tests/test.lua
    if [ $? -ne 0 ]; then
      echo "Tests failed with $version"
      exit 1
    fi
  else
    echo "$version is not installed"
  fi
done

echo "All tests passed!"