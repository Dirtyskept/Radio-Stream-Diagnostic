# Radio Meta — Stream Diagnostic (Windows)

A portable tool that shows what a radio stream really sends: its HTTP/ICY headers, every song-title change during the capture, and FFprobe's view of the format. Use it when Radio Meta shows the wrong song, or none. It only reads the stream and changes nothing in Emby or Radio Meta.

## Use
1. Download the `RadioMeta-Stream-Diagnostics` folder and put it anywhere you can write files. No installer or admin rights are needed.
2. Double-click `Inspect-RadioStream.cmd` and paste the station's full stream link.
3. Wait for the capture to finish: 120 seconds of ICY by default, then 20 seconds of FFprobe. Titles are shown as they arrive (green for songs, amber for likely station breaks).
4. Open the result folder it prints. It's under `Results` next to the script, or on the Desktop if that folder isn't writable.

Options, from PowerShell: `.\Inspect-RadioStream.ps1 -IcySeconds 300 -ProbeSeconds 30 -FfprobePath "C:\ffmpeg\ffprobe.exe" -OutputRoot "E:\RadioDiagnostics"`

## What you get
- `00-SUMMARY.txt`: the overview (RUNNING while it works, COMPLETE when done).
- `01-icy-headers-and-metadata.txt`: headers and each metadata block.
- `02-ffprobe-output.json` and `03-ffprobe-diagnostics.txt`: FFprobe's findings.
- `04-title-highlights.html`: every title with its time and source, and a cautious guess at whether it's a song. It's a hint only; nothing is blocked automatically.

## Privacy
Saved reports remove links, common key/token/password values and Authorization headers. Station names and song titles stay, because they're what's being diagnosed. Check reports before sharing.

## Limits
- The tool asks for the link directly, like any player. A stream that needs Emby's own login or cookies may fail here even if Emby plays it.
- FFprobe is optional. A copy is included under `tools/`, and the script also looks next to itself, on PATH and in Emby's folder. Without it, the ICY capture still runs.

## Licence of the included ffprobe
`tools/ffprobe.exe` is FFmpeg 5.1 as built by Emby, licensed under the GNU GPL version 3. See [FFPROBE-NOTICE.txt](RadioMeta-Stream-Diagnostics/tools/FFPROBE-NOTICE.txt) for its version and where to get its source code, and [FFPROBE-LICENSE-GPLv3.txt](RadioMeta-Stream-Diagnostics/tools/FFPROBE-LICENSE-GPLv3.txt) for the licence.

Requires Windows PowerShell 5.1 (included with Windows). Full details: [README.txt](RadioMeta-Stream-Diagnostics/README.txt) · [CHANGES.txt](RadioMeta-Stream-Diagnostics/CHANGES.txt)

## Licence
Copyright (C) 2026 Dirtyskept. The diagnostic scripts are free software under the [GNU General Public License, version 3](LICENSE): you may use, change and share them, and a changed version you share must also be under GPL-3.0. They come with no warranty. The included `ffprobe.exe` is a separate program, also under GPL-3.0; see its notice above.
