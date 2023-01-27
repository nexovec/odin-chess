@echo off
pushd %~dp0
@mkdir .\\build
odin test src -vet -debug -o:speed -show-timings -microarch:native -thread-count:6 -pdb-name:test.pdb -collection:libs=libs
odin run src -warnings-as-errors -debug -o:speed -show-timings -microarch:native -thread-count:6 -pdb-name:build/chesst.pdb -out:build/chesst.exe -collection:libs=libs
popd