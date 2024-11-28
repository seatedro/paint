#!/usr/bin/env bash

odin build . -out:bin/paint -strict-style -vet -no-bounds-check -o:speed
