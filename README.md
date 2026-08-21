# utilShellScripts

A collection of small, reusable shell scripts for everyday automation and file management on Unix-like systems (macOS, Linux, WSL).

## 📚 Available Scripts

| Script | What it does |
| --- | --- |
| [`RenameEpisodeFileNames/rename_episodes.sh`](#-episode-renamer-renameepisodefilenamesrename_episodessh) | Batch rename TV episode files to `Show.Name.SxxExx.ext` |
| [`SpotifyMP3Downloader/download_songs.sh`](#-spotify-mp3-downloader-spotifymp3downloaderdownload_songssh) | Download a list of Spotify track URLs as MP3s via `spotdl` |
| [`TimeMachineIgnore/tmignore.sh`](#-time-machine-ignore-timemachineignoretmignoresh) | Exclude rebuildable dev-project artifacts from Time Machine backups |

*(More scripts coming soon...)*

## 📁 Repository Layout

```
utilShellScripts/
├── RenameEpisodeFileNames/
│   └── rename_episodes.sh
├── SpotifyMP3Downloader/
│   ├── download_songs.sh
│   └── pendingDownload.txt
└── TimeMachineIgnore/
    └── tmignore.sh
```

---

## 📄 Episode Renamer (`RenameEpisodeFileNames/rename_episodes.sh`)

Batch renames TV show episode files into a consistent format:

```
Show.Name.SxxExx.ext
```

For example:
```
Rick And Morty S06E01 - Solaricks.mp4   →   Rick.And.Morty.S06E01.mp4
Rick.And.Morty.S07E02.1080p.mkv         →   Rick.And.Morty.S07E02.mkv
The.Office.US.S03E14.HDTV.avi           →   The.Office.US.S03E14.avi
Show S01E06 (2019) [x265].mkv           →   Show.S01E06.mkv
```

### ✅ What It Does

- Takes everything before the episode code as the show name.
- Finds the episode code matching `SxxExx` (case-insensitive, exactly two digits each).
- Collapses spaces, underscores, and runs of dots into a single dot, and strips characters
  that are not letters, digits, or dots (so `(2019)` and `[x265]` disappear).
- Keeps the original file extension.
- Files with no `SxxExx` in the name are left alone and reported with a warning.
- Files that already match the target name are reported and left untouched, so the script
  is safe to run twice on the same folder.

### 🛠 Requirements

- macOS, Linux, or WSL
- Bash (the stock macOS Bash 3.2 is fine)
- Read/write permission in the target directory

### 🚀 How to Use

1. **Clone this repo** or copy the script to your machine.

2. **Run it with the target folder as the argument**:
   ```bash
   ./RenameEpisodeFileNames/rename_episodes.sh /path/to/your/episodes
   ```

   Example:
   ```bash
   ./RenameEpisodeFileNames/rename_episodes.sh ~/Downloads/TV_Shows/RickAndMorty
   ```

   The script is committed with its executable bit set, so a fresh clone can run it
   directly. If you copied the file by hand and get a `permission denied`, restore it with
   `chmod +x rename_episodes.sh` — or just run it as `bash rename_episodes.sh <folder>`.

3. Matching files are renamed in place, and each rename is printed as it happens.

### ⚠️ Before You Run It

The script renames in place with no backup and no undo. Read these first:

- **Same-name collisions overwrite silently.** `Show S01E01 720p.mkv` and
  `Show.S01E01.1080p.mkv` both become `Show.S01E01.mkv`, and the second one wins — the
  first file is gone. Keep one copy per episode in the folder.
- **Every file is fair game, not just video.** The script loops over all files in the
  folder, so `Show S01E05 subtitle.srt` is renamed to `Show.S01E05.srt` and loses the
  `subtitle` part. Subtitles that were matched to a video by filename may stop matching,
  and a language suffix like `.en.srt` is dropped.
- **Case is preserved, not normalized.** `breaking_bad_s01e03_720p.mkv` becomes
  `breaking.bad.s01e03.mkv` — lowercase in, lowercase out.

Try it on a copy of a folder first.

### 💡 Notes

- Works with any show name, as long as the filename contains an `SxxExx` pattern.
- Only the top level of the given folder is processed — subfolders are not touched and
  their contents are not renamed.
- Hidden files (starting with `.`) are skipped, and the script never creates one: a file
  named just `S04E09.mkv` has no show name, so it keeps that name as-is.
- Files with no extension are handled correctly — `NoExtensionFile.S02E02` is recognised
  as already-named rather than growing a repeated `.S02E02` suffix.

### 📂 Recommended Folder Structure

Point the script at a folder holding one show's episodes:
```
📁 TV_Shows/
   └── 📁 RickAndMorty/
       ├── Rick And Morty S07E01 - Some Title.mkv
       ├── Rick.And.Morty.S07E02.1080p.mkv
       └── ...
```

Because the show name comes from each filename individually, a folder mixing several
shows produces several different prefixes rather than one consistent name.

### 🧪 Sample Output

```
$ ./RenameEpisodeFileNames/rename_episodes.sh ~/Downloads/TV_Shows/RickAndMorty
Rick And Morty S07E01 - Some Title.mkv -> Rick.And.Morty.S07E01.mkv
Rick.And.Morty.S07E02.1080p.mkv -> Rick.And.Morty.S07E02.mkv
✅ Already named correctly: Rick.And.Morty.S07E03.mkv
⚠️  Episode code not found in: random-notes.txt
```

Resulting folder:
```
📁 RickAndMorty/
   ├── Rick.And.Morty.S07E01.mkv
   ├── Rick.And.Morty.S07E02.mkv
   ├── Rick.And.Morty.S07E03.mkv
   └── random-notes.txt
```

---

## 🎵 Spotify MP3 Downloader (`SpotifyMP3Downloader/download_songs.sh`)

Reads Spotify track URLs from `pendingDownload.txt`, one per line, and hands each one to
[`spotdl`](https://github.com/spotDL/spotify-downloader) to download as an MP3 named
`{artist} - {title}.mp3`. It waits 20 seconds between tracks.

> Note: `spotdl` reads track metadata from Spotify but fetches the audio from YouTube.
> Use it for material you have the right to download.

### 🛠 Requirements

- [`spotdl`](https://github.com/spotDL/spotify-downloader) on your `PATH`
  (tested with 4.4.3): `pip install spotdl`
- `ffmpeg`, which `spotdl` uses for MP3 conversion: `brew install ffmpeg`
- An internet connection

### 🚀 How to Use

1. **Add your track URLs** to `pendingDownload.txt`, one per line:
   ```
   https://open.spotify.com/track/1XulLUGJdrVNJqRjW0GW2z?si=c83c2d865c2f444d
   https://open.spotify.com/track/...
   ```

2. **Run the script from inside its own folder** — it reads `pendingDownload.txt` from the
   current directory, not from where the script lives:
   ```bash
   cd SpotifyMP3Downloader
   ./download_songs.sh
   ```

3. MP3s are written to the current directory as `Artist - Title.mp3`.

### 💡 Notes

- **End the file with a newline.** A last line with no trailing newline is silently
  skipped by the read loop.
- **No blank lines.** An empty line is passed to `spotdl` as an empty argument.
- The list is not consumed. Nothing is removed from `pendingDownload.txt` after a
  successful download, so re-running the script re-downloads everything — trim the file
  yourself between runs.
- The 20-second `sleep` between tracks is deliberate pacing; edit the script if you want
  it faster or slower.
- Running from any other directory fails with
  `pendingDownload.txt: No such file or directory`.

---

## 💾 Time Machine Ignore (`TimeMachineIgnore/tmignore.sh`)

A `.gitignore` for Time Machine. Point it at a folder, and it finds every dev project
underneath, works out which directories are rebuildable build output, shows you the list,
and — only after you confirm — hands them to `tmutil addexclusion` so Time Machine stops
backing them up.

```bash
./TimeMachineIgnore/tmignore.sh --dry-run ~/Projects   # show the list, change nothing
./TimeMachineIgnore/tmignore.sh ~/Projects             # list, prompt, then apply
./TimeMachineIgnore/tmignore.sh --yes ~/Projects       # skip the prompt (cron/LaunchAgent)
```

### ✅ What It Does

- Walks each folder you give it (default: the current directory) and detects projects by
  their marker files — `package.json`, `Cargo.toml`, `pubspec.yaml`, `go.mod`, and so on.
- Prints an inventory of everything it found, grouped by project type.
- Builds the full list of artifact directories it wants to exclude, and prints that too.
- Asks for `y/N` confirmation, and **only then** calls `tmutil addexclusion`.
- Skips directories that are already excluded, so re-running it is safe and cheap.

Each project is listed **once**, under the most specific type it matches. A Next.js app
also matches React and Node.js, but it is reported as Next.js, not all three. Genuinely
unrelated stacks are still listed separately — a Tauri app appears under both React and
Rust, because that is what it is. Pass `--all-types` to see every match instead.

This affects the inventory only. Artifact detection still uses **every** type a project
matched, so that Next.js app is still scanned for `node_modules` and `.next` alike.

### 🔍 Project Types Detected

Node.js · React · Next.js · Angular · Vue · Svelte · Nuxt · Astro · React Native / Expo ·
Flutter / Dart · Android / Gradle · Xcode / iOS · Python · Rust · Go · Java / Maven ·
PHP / Composer · Ruby · .NET

### 🛡 The Git Safety Net

This is the part worth understanding before you run it.

Inside a git repository, a directory is only excluded if `git check-ignore` agrees that git
ignores it. So a `build/` holding committed release scripts is left alone and reported as
tracked in git, while a `build/` holding compiler output is excluded. Pass `--no-git-check`
to turn this off and rely on the built-in lists alone.

It deliberately does **not** read your `.gitignore` wholesale. Those files typically list
`.env` and local config — exactly the things you *do* want in a backup.

`src/`, `lib/`, `assets/` and `.git` are never excluded. That check is made relative to each
project root, not anywhere in the path, so a project that happens to live under a folder
named `app/` is still scanned normally.

### 🛠 Requirements

- macOS, for `tmutil`, to actually apply exclusions. `--dry-run` and `--report-only` need
  no `tmutil` and work anywhere.
- Bash — written for the stock macOS `/bin/bash` 3.2.
- Write access to the directories being excluded. The script uses `tmutil`'s default
  "sticky" exclusion, which is stored as an extended attribute on the item itself, so it
  needs no root — unlike the `-p` and `-v` exclusion styles, which do.

### 🚀 How to Use

Start with a dry run. It changes nothing:

```bash
./TimeMachineIgnore/tmignore.sh --dry-run ~/Projects
```

When the list looks right, drop the flag and confirm at the prompt:

```bash
./TimeMachineIgnore/tmignore.sh ~/Projects
```

You can pass several folders at once:

```bash
./TimeMachineIgnore/tmignore.sh ~/Projects ~/Work
```

### 🎛 Flags

| Flag | Effect |
| --- | --- |
| `-n`, `--dry-run` | Show what would be excluded, change nothing |
| `-r`, `--report-only` | List projects only; never touch Time Machine |
| `-y`, `--yes` | Skip the confirmation prompt — for cron or a LaunchAgent |
| `-s`, `--size` | Show a size estimate per directory, and a total (slower) |
| `-d`, `--depth N` | How deep to search below each folder (default 6) |
| `-i`, `--ignore NAME` | Never descend into directories with this name (repeatable) |
| `-a`, `--all-types` | List a project under every type it matches, not just the most specific |
| `-e`, `--show-excluded` | List the directories Time Machine is already skipping |
| `--no-git-check` | Skip the "is it gitignored?" safety check |
| `-h`, `--help` | Show help |
| `-V`, `--version` | Print version |

### 💡 Notes

- **Depth is relative to each folder you pass.** `--depth 1` looks only at that folder's
  immediate children, so a nested monorepo member needs a larger depth to be seen.
- **The walk prunes the obvious junk** — `node_modules`, `target`, `Pods`, `.venv` and
  friends — but deliberately does *not* prune `packages/`, `dist/`, `build/`, `bin/` or
  `vendor/`. `packages/` is the standard monorepo layout, and pruning it would hide every
  workspace member.
- **Already-excluded directories are counted, not listed.** The summary reports how many
  were already being skipped; add `--show-excluded` to see which ones. Combine it with
  `--dry-run` for a read-only audit of what Time Machine is currently ignoring.
- **A failed exclusion does not abort the run.** The rest still get applied, failures are
  listed individually, and the script exits `1` if any failed.
- **Excluding a directory does not delete it.** It only tells Time Machine to stop copying
  it; existing backup copies are removed over time as old snapshots age out.
- **A sticky exclusion follows the directory.** Move it and the exclusion moves with it;
  copy it and the copy is excluded too. To undo one, use
  `tmutil removeexclusion /path/to/dir`.

### 🧪 Sample Output

```
$ ./TimeMachineIgnore/tmignore.sh --dry-run ~/Projects
tmignore 1.0.0 - a .gitignore for Time Machine

Scanning ~/Projects (depth 6)...

-- Project types found -------------------------------------
  Node.js                  5
  Rust                     2
  React                    2
  React Native / Expo      1
  Python                   1
  Nuxt                     1
  Next.js                  1
  Go                       1
  Flutter / Dart           1
  Android / Gradle         1

-- Projects ------------------------------------------------
  Node.js
    inner-proj                 ~/Projects/app/inner-proj
    git-node                   ~/Projects/git-node
    mono                       ~/Projects/mono
    api                        ~/Projects/mono/packages/api
    web                        ~/Projects/mono/packages/web
  React
    plain-node                 ~/Projects/plain-node
    tauri-app                  ~/Projects/tauri-app
  Next.js
    nextjs-app                 ~/Projects/nextjs-app
  Nuxt
    nuxt-app                   ~/Projects/nuxt-app
  React Native / Expo
    rn-app                     ~/Projects/rn-app
  Flutter / Dart
    flutter-app                ~/Projects/flutter-app
  Android / Gradle
    android                    ~/Projects/flutter-app/android
  Python
    py-app                     ~/Projects/py-app
  Rust
    rust-cli                   ~/Projects/rust-cli
    tauri-app                  ~/Projects/tauri-app
  Go
    go-svc                     ~/Projects/go-svc

-- Left alone (git tracks these, so they are not generated) --
  - node           ~/Projects/git-node/build

-- To be excluded ------------------------------------------
  + node           ~/Projects/app/inner-proj/dist
  + node           ~/Projects/app/inner-proj/node_modules
  + flutter        ~/Projects/flutter-app/.dart_tool
  + flutter        ~/Projects/flutter-app/android/.gradle
  + flutter        ~/Projects/flutter-app/android/app/build
  + flutter        ~/Projects/flutter-app/build
  + flutter        ~/Projects/flutter-app/ios/Pods
  + node           ~/Projects/git-node/dist
  + node           ~/Projects/git-node/node_modules
  + go             ~/Projects/go-svc/bin
  + node           ~/Projects/mono/packages/api/node_modules
  + node           ~/Projects/mono/packages/web/node_modules
  + nextjs         ~/Projects/nextjs-app/.next
  + node           ~/Projects/nextjs-app/node_modules
  + nuxt           ~/Projects/nuxt-app/.nuxt
  + node           ~/Projects/nuxt-app/node_modules
  + node           ~/Projects/plain-node/dist
  + node           ~/Projects/plain-node/node_modules
  + python         ~/Projects/py-app/.venv
  + python         ~/Projects/py-app/__pycache__
  + react_native   ~/Projects/rn-app/.expo
  + node           ~/Projects/rn-app/node_modules
  + rust           ~/Projects/rust-cli/target
  + node           ~/Projects/tauri-app/node_modules
  + rust           ~/Projects/tauri-app/target

-- Summary -------------------------------------------------
  Projects found        15
  To exclude            25
  Already excluded      0
  Left alone (in git)   1

Dry run - nothing was changed. Re-run without -n to apply.
```

### 🧷 Testing Changes to the Script

`tmutil` is resolved through the `TMIGNORE_TMUTIL` environment variable, so you can point
it at a stand-in binary and exercise the whole flow without touching real backup state:

```bash
TMIGNORE_TMUTIL=/path/to/fake-tmutil ./TimeMachineIgnore/tmignore.sh --yes ./fixtures
```

Two things to know if you write such a stand-in:

- `tmutil isexcluded` exits `0` for **both** states. You have to parse stdout for
  `[Excluded]` — the exit code tells you nothing.
- All of `/tmp` is already excluded by macOS, so fixtures created there always report as
  already excluded when run against the real `tmutil`.

Before committing, check both of these still pass:

```bash
bash -n TimeMachineIgnore/tmignore.sh && shellcheck TimeMachineIgnore/tmignore.sh
```

---

## 📬 Questions or Contributions?

If you have other naming styles or improvements, feel free to open an issue or PR.
Contributions are welcome!
