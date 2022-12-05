@echo off
pushd %~dp0
@mkdir .\\build
odin check src -vet -warnings-as-errors -thread-count:6 -collection:libs=libs
popd