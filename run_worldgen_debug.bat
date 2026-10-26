@echo off
rem World generation debugger: top-down map of any seed, layer by layer. Optional argument: seed.
start "" "%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "%~dp0." res://worldgen_debug.tscn -- %1
