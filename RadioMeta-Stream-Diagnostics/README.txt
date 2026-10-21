Radio Meta — Portable ICY + FFprobe Stream Diagnostic v1.2
=====================================================

PURPOSE
-------
Captures HTTP/ICY response headers and in-band StreamTitle changes, highlights each detected title in the console, creates a color-coded HTML title report, then runs FFprobe to report stream/format metadata and diagnostics. The tool is read-only;
it does not change Emby, Radio Meta, or station files.

PORTABLE USE
------------
1. Extract this entire folder anywhere you can write files (Desktop, Documents,
   or a writable USB folder). No installer or administrator rights are required.
2. Double-click Inspect-RadioStream.cmd.
3. Paste the full HTTP/HTTPS station stream URL.
4. Wait for the requested capture to finish (default: 120 seconds for ICY and
   20 seconds for FFprobe).
5. Open the timestamped result folder printed by the script.

The tool uses Windows PowerShell 5.1, included with supported Windows systems.
The results are written under a Results folder beside the script. If that folder
isn't writable, it falls back to a folder under Desktop (or TEMP if Desktop is
unavailable). You can also set an explicit output root by running PowerShell:

  .\Inspect-RadioStream.ps1 -OutputRoot "E:\RadioDiagnostics" 

FFPROBE OPTIONS
---------------
FFprobe is optional. The script looks for it in this order:
  - The ffprobe.exe path supplied when prompted or with -FfprobePath
  - The same folder as Inspect-RadioStream.ps1
  - The tools subfolder next to Inspect-RadioStream.ps1
  - PATH, common FFmpeg locations, and the Emby server system folder

This version includes the provided ffprobe.exe under tools\. If it does not run on
your Windows computer, place a trusted compatible ffprobe.exe and any required
runtime DLLs beside the executable. Without FFprobe, ICY capture still runs and the
two FFprobe files explain why that portion was skipped.

OUTPUT FILES
------------
  00-SUMMARY.txt
  01-icy-headers-and-metadata.txt
  02-ffprobe-output.json
  03-ffprobe-diagnostics.txt
  04-title-highlights.html

The files are created immediately after you enter a valid URL. During capture,
the summary says RUNNING and the ICY report is updated with response headers and
each observed metadata change. Detected titles are printed in green; likely station-break messages are printed in amber. Open 04-title-highlights.html to scan detected ICY/FFprobe title-like values, timestamps, source, and a cautious format-based classification. The classification is only a hint: a title such as “Please” is shown for review, not automatically called junk. On normal completion, the summary says COMPLETE.
If the script crashes or is interrupted, partial reports remain and the summary
or diagnostics should describe the failure. If the folder is empty, verify that
you opened the result folder printed in the console; with this version, an empty
folder after a valid URL usually means the script failed before it could create
the report files or the location was not writable.

WHAT IT TESTS / DOES NOT TEST
-----------------------------
The tool directly requests the URL you enter, with Icy-MetaData: 1. It does not
capture Emby's internal FFmpeg command line, Radio Meta logs, authenticated
headers or cookies used only by Emby, unless the URL works independently.
A stream that needs special authentication may fail here even if Emby can play it.

PRIVACY
-------
The entered stream URL is not printed as-is. Saved text reports also scrub HTTP(S) URLs, common token/key/password assignments, and Authorization header lines. ICY StreamUrl values are omitted. Station names and song titles remain because they are needed to diagnose metadata. Review reports before sharing; unusual/custom secret formats may still require manual review.
