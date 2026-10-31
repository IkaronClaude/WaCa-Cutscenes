# WaCa Cutscenes

Cutscenes from plain text, for **Warrior Cats: Clans of the Forest**: the cats of a scene set out in a premade shape
at a place, then a timeline - cats walk in, turn to each other, hiss, sit, speak their lines, and the camera cuts and
moves between named shots. No coordinates, no 3D work: the game's own cats, animations and camera.

**Experimental (0.1).** Tell us what your stories need.

## A cutscene
In `config\cutscenes.ini` - or, better, in your own mod's `content\cutscenes.ini` (a folder with `enabled.txt` and a
`content` folder; no code):

```ini
[Cutscene.Standoff]
Place = Here
Shape = Facing
A = Player, Deputy
B = Nearest, Nearest
Beat1 = 0 WalkIn: B
Beat2 = 0 Camera: Wide
Beat3 = 4 Camera: Two = A1 & B1 ~2
Beat4 = 6 Say: B1 = You took your time.
Beat5 = 9 Pose: A2 = Growl
Beat6 = 9 Camera: Portrait = A2
Beat7 = 10 Say: A2 = Mind your tongue.
Beat8 = 13 Camera: Over = A1 > B1 ~1.5
Beat9 = 16 End
```

- **Place** - where it plays: `Here` (in front of your cat), `Pile` (the fresh-kill pile), a place from
  `config\places.ini` (or your mod's `content\places.ini`), or `X Y Z [yaw]`. The shape is fitted to the ground: turned
  (and for `Here` brought nearer) until every cat's mark has open ground with nothing in the way - a rock, a den wall;
  a place with its own yaw stays as it is.
- **Shape** - how the cats stand (`config\shapes.ini`): `Facing` (two sides, A and B, face each other), `Circle` (C),
  `Line` (L, looking at the camera), `Pair` (P1, P2 face to face), `Meeting` (a speaker S1 before the clan C),
  `Ceremony` (leader L1, the cat being named K1, its mentor M1, the clan C). Make your own: a mark per line
  (`A1 = <forward> <side>` in cm) and which way each group looks (`FaceA = B`).
- **The cast** - each group's cats in order (`A = Player, Deputy` -> A1, A2): `Player`; a part in your clan (`Leader`,
  `Deputy`, `MedicineCat`, `Queen`, `Kit`, `Elder`, `Apprentice`, `Warrior`, `Mentor` - your own cat when it holds
  that rank: `Deputy` is you when you are the deputy); a story role exactly
  (`E:RiverClanDeputy`); a mod's own role (`S:herbalist` - cast in WaCa Clan Life's `events.ini [Cast]`); a cat's
  name (`Lionstar`); `Nearest` (the nearest clanmate not cast yet). A part nobody plays
  is left out - the cutscene still plays.
- **Beats** - `BeatN = <seconds from the start> <Action>: <who> [= <what>]`. Who is a mark (`A1`), a group (`B`), `All`
  or `Player`.

| Action | |
|---|---|
| `WalkIn: <who>` | the cats walk onto their marks (they start a few metres out) |
| `Walk: <who> = <who>` | walk up to another cat (or `Middle`), facing it |
| `Place: <who>` | onto their marks at once |
| `Look: <who> = <who>` | turn to a cat (or `Middle`, `Camera`) |
| `Pose: <who> = <pose>` | `Sit`, `Lie`, `Sleep`, `Eat`, `Sniff`, `Meow`, `Play`, `Dig`, `Groom`, `Win`, `Hit`, `Hiss`, `Growl`, `TailUp`, `Stop` - or a montage's path |
| `Say: <who> = <line>` | the line on screen with the cat's name; `{PLAYER}` / `{P1}`, `{P2}` ... = those cats' names |
| `Card: <text>` | a line on screen without a name |
| `Camera: <shot> [= <who>]` | `Wide`, `High`, `Orbit [= <who>]`, `Portrait = <who>`, `Over = <who> > <who>`, `Two = <who> & <who>`, `Game` (the game's own camera); add `~<seconds>` to move there instead of cutting |
| `Fade: <s>` / `FadeIn: <s>` | to black / back |
| `Emit: <event>` | another mod's code runs here |
| `End` | over now (else 2 s after the last beat) |

While a cutscene plays your keys and the HUD are off (SkipKey - `SpaceBar` by default - skips it;
`WaCa.Emit("SkipCutscene")` from a mod); at the end the cats go back where they were and the game's
camera comes back (your cat stays where the cutscene left it - `PutPlayerBack = 1` changes that).

### The game's own scenes, with your cast
A cutscene can instead play one of the game's own cinematics - placed, framed and animated the game's way - with its
cats dressed as the cats you name:
```ini
[Cutscene.Ceremony]
Scene = RankUp          ; the rank-up ceremony in your camp (RankUp.Leader: the leader's at the Moonpool;
                        ; Prophecy.Closure: StarClan's cats at a prophecy's end)
Leader = MedicineCat    ; who plays the clan's leader in it
Warrior.2 = Mossfeather ; the scene's second warrior
```
Every key besides `Scene` names one of the scene's cats by its clan job (`Leader`, `Deputy`, `MedicineCat`,
`Warrior.<n>` ...) and who it is - any cast (a name, a part, `E:` / `S:` roles). If a job you name isn't in the scene,
the log lists the jobs it has (the prophecy's end: `StarClanAncestor`, `Manifestation.<n>`). A job comes from your
clan's cats in the scene, else from StarClan's. `Music = <event>` plays another music than the scene's own. Your cat
plays your cat. Only the scene plays: nobody's rank changes. The game's own
HOLD SKIP skips it.

**Writing one:** set `PreviewKey` (and `Preview = <your cutscene>`) in `cutscenes.ini` to play it with a key, and
`WhereKey` to log where your cat stands as a ready `places.ini` line.

## Playing one
- From a **WaCa Clan Life** scene (clan events, story days ...): the step `Cutscene: <Name>` - the scene goes on when
  it's over.
- From any mod: `WaCa.Emit("PlayCutscene", "<Name>")` - one at a time; asked for while another plays, it waits.
  Events: `CutsceneStarted(name)`, `CutsceneEnded(name, why)`; the sticky topic `cutscene` ({ playing, name }).
  Clan Life's camp cats hold still while one plays, and its cards wait.
- **A line without a cutscene**: `WaCa.Emit("ShowLine", "<who>: <line>" [, seconds])` - the cutscenes' subtitle (Clan
  Life's hunt comments use it).

## Install
Needs **UE4SS for Warrior Cats** ([Nexus](https://www.nexusmods.com/warriorcatsclansoftheforest/mods/2)) and
**[WaCa Core](https://github.com/IkaronClaude/WaCa-Core)**. Extract the zip into the game's folder so that
`Wrc\Binaries\Win64\ue4ss\Mods\WaCaCutscenes` exists - it turns itself on. Uninstall: delete that folder.

## Contributing
Shapes, places, cutscenes, bug reports and pull requests are very welcome - see [CONTRIBUTING.md](CONTRIBUTING.md).

## AI disclosure
Much of this code and documentation was written with AI assistance (Claude, by Anthropic), directed, play-tested and
released by the author. It reuses the game's own animations; no assets of its own.

## License
Apache License 2.0 (see LICENSE).
