#!/usr/bin/env bash
find . -type f -name "*.go" | grep -v "./vendor*" | xargs gofmt -s -w
