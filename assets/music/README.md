SNOW official soundtrack directory. 
Claude must load soundtrack files from res://assets/music/ using the existing Music audio bus. 
The game must also work when no music files are present. 

How it works (scripts/music.gd): add or remove .mp3/.ogg files here; no playlist to edit.
The game always opens with "Alpine Shift (Take 2) (Remix).mp3" (falls back to a random
song if absent), then shuffles every other song, then reshuffles all songs, never
repeating a song back-to-back, with short crossfades on the Music bus.
