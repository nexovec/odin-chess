@echo off
pushd %~dp0
@mkdir .\\build
@REM odin test src -warnings-as-errors -o:minimal -show-timings -microarch:native -thread-count:6 -collection:libs=libs

@REM odin build src -warnings-as-errors -debug -o:minimal -show-timings -microarch:native -thread-count:6 -pdb-name:build/chesst.pdb -out:build/chesst.exe -collection:libs=libs
odin test src -warnings-as-errors -debug -o:minimal -show-timings -microarch:native -thread-count:6 -pdb-name:test.pdb -collection:libs=libs
odin run src -warnings-as-errors -debug -o:minimal -show-timings -microarch:native -thread-count:6 -pdb-name:build/chesst.pdb -out:build/chesst.exe -collection:libs=libs
popd