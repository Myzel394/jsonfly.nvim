#!/usr/bin/env just --justfile

set dotenv-load := true

_default:
  just --list -u

lint:
    stylua lua

