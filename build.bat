@echo off
REM Run from the OSS CAD Suite shell.
REM   build.bat        -> build mp3.bin
REM   build.bat prog   -> build, then upload to the board
REM   build.bat sim    -> run the test bench
if /i "%1"=="sim" (
    iverilog -g2012 -s mp3_tb -o mp3_tb.vvp mp3_tb.sv mp3.sv || exit /b 1
    vvp mp3_tb.vvp -fst || exit /b 1
    exit /b 0
)
yosys -p "synth_ice40 -noabc -top top -json mp3.json" mp3.sv || exit /b 1
nextpnr-ice40 --up5k --package sg48 --json mp3.json --pcf iceBlinkPico.pcf --asc mp3.asc || exit /b 1
icepack mp3.asc mp3.bin || exit /b 1
if /i "%1"=="prog" dfu-util --device 1d50:6146 --alt 0 -D mp3.bin -R
