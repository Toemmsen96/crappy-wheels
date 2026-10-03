# Crappy-Wheels

Just some game i made, because i was bored and wanted to make something like Happy-Wheels.

play it at https://toemmsen.ch/crappy-wheels

## Level Builder

Open **Level Builder** from the main menu to make your own levels: draw floors, place balls, and move the start and finish. **Test** plays the level straight away (Esc → "Back to Level Builder" returns), and **Save** stores it in `user://levels/<id>.json`. Saved levels show up under **Your Levels** in the level selector, where they can be played, edited or deleted.

## Sharing Levels

Community levels live in [crappy-wheels-levels](https://github.com/Toemmsen96/crappy-wheels-levels). To submit one, press **Export** next to it in the level selector to get its `.json` file, then open a pull request adding it to the `Community/` folder.

**Browse Online Levels** in the level selector lists every `.json` file directly inside `Base/` and `Community/` of that repository's `main` branch, and downloads them into `user://downloads/`. Downloaded levels show up under **Downloaded Levels**. Downloading one again updates it. The repository must be public for this to work.

Levels are plain JSON rather than Godot scenes, because loading a scene or resource can run scripts inside it. Every level, local or downloaded, goes through `LevelData.from_json()`, which rejects malformed files and clamps out-of-range values. Raise `LevelData.FORMAT_VERSION` when the format changes; older versions of the game skip levels with a newer version.
