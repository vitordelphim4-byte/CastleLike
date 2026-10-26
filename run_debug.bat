@echo off
rem Opens the flat debug map: infinite resources, test area for every system, debug panel (F1).
start "" "%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe" --path "%~dp0." res://debug.tscn
