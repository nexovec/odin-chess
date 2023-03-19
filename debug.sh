#!/bin/bash
sudo apt install libsdl2-image-dev libsdl2-ttf-dev
~/src/Odin/odin build src -warnings-as-errors -debug -lld -o:minimal -show-timings -microarch:native -thread-count:6 -out:build/chesst.exe -collection:libs=libs