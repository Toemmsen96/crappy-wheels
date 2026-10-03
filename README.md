# Crappy-Wheels

Just some game i made, because i was bored and wanted to make something like Happy-Wheels.

play it at https://toemmsen.ch/crappy-wheels

## Level Builder

Open **Level Builder** from the main menu to make your own levels: draw floors, place balls, and move the start and finish. **Test** plays the level straight away (Esc → "Back to Level Builder" returns), and **Save** stores it in `user://levels/<id>.json`. Saved levels show up under **Your Levels** in the level selector, where they can be played, edited or deleted.

Levels are saved as plain JSON instead of Godot scenes, because loading a scene or resource can run scripts inside it. That keeps levels from other players safe to load once uploading is added. To support it:

- Upload the JSON from `LevelData.to_json()`. The level's `id` identifies it across uploads.
- Load downloaded levels with `LevelData.from_json()`, which rejects malformed data and clamps out-of-range values, then save them with `LevelLibrary.save_level()` so they appear in the level selector.
- Raise `LevelData.FORMAT_VERSION` when the format changes. Older games refuse levels with a newer version.
