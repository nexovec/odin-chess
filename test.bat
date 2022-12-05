@echo off
pushd %~dp0
@mkdir .\\build
odin test src -warnings-as-errors -debug -o:minimal -show-timings -microarch:native -thread-count:6 -pdb-name:test.pdb -collection:libs=libs
popd