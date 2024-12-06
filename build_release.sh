#!/usr/bin/env bash

odin build . -out:bin/yume -strict-style -vet -no-bounds-check -o:speed
