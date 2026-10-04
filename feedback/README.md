# Feedback inbox

Problem reports from the app's feedback button (the speech-bubble icon) go here.

1. On the phone: Setup → Feedback → Send. Send them to yourself (Mail, Drive, Files…).
2. Put the `kt-feedback-*.json` files in this folder.
3. `cd ios/KTEngine && swift run kt-feedback`

Each report holds the note, where you were in the app, the whole game log (so the state
replays exactly), the screen as text, view state, the app's commit and recent log lines,
and optionally a screenshot. The tool prints all of it, writes the screenshot beside the
report as a `.jpg`, and replays the game on today's rules and code with a diff.

Reports are git-ignored, because screenshots can show your own operative photos. Once a
report is dealt with, move it to `done/` rather than deleting it. The tool only reads this
folder's top level.
