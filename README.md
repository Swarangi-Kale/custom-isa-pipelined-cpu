## Toolchain / Dependencies

- **Vivado 2025.2** (installed via AMD Unified Web Installer)
- Microsoft Visual C++ Redistributable for Visual Studio 2015-2022 (x64)

## Known Issue: Vivado fails to launch via desktop shortcut

**Symptom:** Default desktop shortcut (`vvgl.exe`) throws `MSVCP140.dll` / `VCRUNTIME140_1.dll` not found errors on launch.

**Cause:** Vivado ships its own bundled VC++ runtime DLLs, but only `vivado.bat` sets up the PATH to use them. Launching `vvgl.exe` directly skips this setup.

**Fix:**
1. Locate the VC++ redistributable installer bundled with Vivado (`vcredist_x64.exe`) — if only `xvcredist.exe` is present in that location, rename it (e.g. prepend `hide_`) so it's not picked up, then manually install the standard **VC++ Redistributable for Visual Studio 2015-2022 (x64)** from Microsoft.
2. Launch Vivado via `vivado.bat` (found in `Vivado\bin`) instead of `vvgl.exe`.
3. Create your desktop shortcut pointing to `vivado.bat`, not the default `vvgl.exe` shortcut.