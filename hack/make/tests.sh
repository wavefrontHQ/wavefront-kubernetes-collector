#!/usr/bin/env bash
go clean -testcache
go test -timeout 30s -race ./...
