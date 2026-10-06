# Crappy-Wheels

Just some game i made, because i was bored and wanted to make something like Happy-Wheels.

play it at https://toemmsen.ch/crappy-wheels

## Level Builder

Open **Level Builder** from the main menu to make your own levels: draw floors, place balls, and move the start and finish. **Test** plays the level straight away (Esc → "Back to Level Builder" returns), and **Save** stores it in `user://levels/<id>.json`. Saved levels show up under **Your Levels** in the level selector, where they can be played, edited or deleted.

## Sharing Levels

Community levels live in [crappy-wheels-levels](https://github.com/Toemmsen96/crappy-wheels-levels). To share one of your levels, press **Share** next to it in the level selector: the [backend](https://github.com/Toemmsen96/crappy-wheels-backend) adds it to the `Community/` folder right away. A level can be shared once; changes made to it afterwards can't be shared yet. You can also press **Export** to get its `.json` file and open a pull request adding it to `Community/`.

**Browse Online Levels** in the level selector lists every `.json` file directly inside `Base/` and `Community/` of that repository's `main` branch, and downloads them into `user://downloads/`. Downloaded levels show up under **Downloaded Levels**. Downloading one again updates it. The repository must be public for this to work.

## Leaderboards

Level 1 and every downloaded level have a leaderboard, kept by the backend. When you finish one, the finish screen shows the ten fastest times (five at a time, the list scrolls) and submits yours under your name, which you enter the first time and which is remembered in `user://settings.cfg`. Only each name's best time is kept. Your own levels have no leaderboard, since they can still be edited, and neither do test runs from the Level Builder.

**Leaderboards** in the main menu shows the fastest times (up to 100) of Level 1 and of each downloaded level, starting with the level you played last.

A downloaded level's leaderboard is named after its place in the level repository, e.g. `Community-loop` for `Community/loop.json`, so it is the same for every player. Times are whatever the game reports; there are no accounts.

`BackendClient` (`scripts/backend_client.gd`) talks to the backend. The backend's address is not in this repository: the game reads it from `backend.cfg` in the project folder, which git ignores. Copy `backend.cfg.example` to `backend.cfg` and put in the address, e.g. `http://127.0.0.1:8080` for a backend running on your machine. The deploy workflow writes the file from the repository secret `BACKEND_URL` (Settings > Secrets and variables > Actions) and fails if the secret is missing. Without the file the game still runs, and the leaderboards and Share report that no server is set up.

## Level Files

Levels are plain JSON rather than Godot scenes, because loading a scene or resource can run scripts inside it. Every level, local or downloaded, goes through `LevelData.from_json()`, which rejects malformed files and clamps out-of-range values. Raise `LevelData.FORMAT_VERSION` when the format changes; older versions of the game skip levels with a newer version.

## Look

Text is set in [Gochi Hand](https://fonts.google.com/specimen/Gochi+Hand); [Patrick Hand](https://fonts.google.com/specimen/Patrick+Hand) fills in letters Gochi Hand lacks, such as č or ł, and Godot's built-in font takes over for other alphabets (`GameState._ready()` adds it). Both fonts are under the SIL Open Font License; the licence texts are next to them in `assets/fonts/`.

Other UI was hand drawn by me (obviously).
