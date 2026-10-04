# John's Beer Run: Godot 4.3 port (v2.5, stage 5)

To run it, open this folder in **Godot 4.3 or newer**: in the Project Manager, choose Import and select `project.godot`. The first time, Godot spends a minute or two importing the assets. Then press F5.

## What works
- **Title screen:** the logo, Start the Night, How to Play and Credits.
- **End card:** "John's out cold", shown after five beers.
- **The recliner:**
  - E gets John up.
  - Bring a beer back to the chair to sit and drink. This plays the original drinking animation from the model.
  - Each beer adds 22 minutes to the clock.
  - At five beers John passes out, with snoring and floating Zzz.
- **The fridge:** the door swings open, the light comes on, John reaches in and takes a can. The can count drops as he drinks.
  - It starts with 6 beers until the Fuel Stop run is ported.
- **The kitchen table:** three lines. Doing one makes John "wired" for 30 seconds: he moves faster, you hear a heartbeat and the screen gets the high effect.
- **The bong:** lighter, flame, bubbles, smoke and a cough. About five seconds later the trip starts: flying rainbow cats, the kaleidoscope effect and a drone sound.
- **Getting drunk:** the screen wobbles, doubles and blurs, the vignette closes in, and John's walk sways and lurches more with every beer.
- **The TV:** three channels (football, fishing, local news) with static in between. The TV light changes colour to match the channel.
- **Around the cabin:**
  - The fireplace light flickers and crackles.
  - The bathroom door opens and closes, and the toilet flushes.
  - The front door opens, so John can go outside.
- **HUD:** the beer cans, cash, the clock, Wired and Tripping timers, John's lines and the E prompts.

- **The visitor (stage 3):**
  - About 30 seconds in, a man in a hat and suit walks up the street and around the cul-de-sac to John's porch.
  - He knocks up to five times, and John reacts.
  - Press U at the front door to look through the peephole (fisheye view; the mouse looks around). Press E to open the door.
  - Open the door, or walk out to him, and he steps up and asks for number 14. John's directions are slurred if he's had 3 or more beers. Then he waves and heads across the circle.
  - If nobody answers, or John has passed out, he gives up and leaves.
  - He is invincible and is never a target for the gun.
- **The Glock (stage 4):**
  - It sits on the side table by the recliner. Press E to pick it up; John bends down and racks the slide.
  - Hold the right mouse button to aim: over-the-shoulder camera, crosshair, slower walk, and John's arm tracks the crosshair with the gun held upright.
  - Left-click to shoot: muzzle flash and light, tracer, recoil, sparks, dust and bullet holes (the holes stay on doors as they swing).
  - The magazine holds 15. Press R to reload, and it reloads by itself when empty.
  - Shooting the bathroom mirror shatters it into falling shards.
  - Shooting the TV shatters the screen with sparks and ends in MISSION FAILED.
  - The gun is put away while John does a line or hits the bong.
- **Driving the M1 (stage 5):**
  - The red BMW M1 is parked in the cul-de-sac. Press E next to it to get in, and E again to get out (you have to stop first).
  - W is gas, S is brake and then reverse, A/D steer, Space is the handbrake (slides), H is the horn.
  - Steering tightens up at speed. While "wired" the top speed goes up. When drunk the steering wanders and reacts late.
  - Crashes thump, shake the camera and bounce the car back. The visitor is solid to the car and still can't be hurt.
  - Headlights come on when you get in, and the brake lights glow when braking. The engine note revs through 4 gears.
  - The chase camera pulls back and widens with speed, and there's a speedometer on the HUD.
- **Character models:** the visitor, Dale the clerk and the officer are exported from the web game (`assets/chars`). The clerk and officer are already in place for stages 6 and 7.

## Controls
- **WASD:** walk. Hold Shift to walk faster.
- **Mouse:** look around. Use the mouse wheel to zoom.
- **E:** interact.
- **U:** look through the front door peephole.
- **Right mouse button:** aim (once John has the gun).
- **Left mouse button:** shoot.
- **R:** reload.
- **In the car:** W gas, S brake/reverse, A/D steer, Space handbrake, H horn, E get out.
- **Esc:** free the mouse. Click to capture it again.

## Project layout
- `scripts/game.gd`: the game controller (states, actions, timing, camera, effects).
- `scripts/john.gd`: John's rig. It blends the drinking animation with procedural walking, reaching and bending, arm IK and the head droop.
- `scripts/world.gd`: loads the world, adds collision and tunes the lights.
- `scripts/hud.gd`, `scripts/menu.gd`, `scripts/tv.gd`, `scripts/post.gdshader`, `scripts/sfx.gd`: the HUD, menus, TV picture, screen effects and sound.
- `tools/synth.py`: renders the game's sound effects to the WAV files in `assets/sfx`.
- `tools/glb_jpeg.py`: shrinks the textures inside the world files.

## Test run
`godot -- --scenario=tour --shots=/tmp/t` (or `--scenario=visitor`, `--scenario=gun`, `--scenario=drive`, `--scenario=outside`) plays through the actions and saves screenshots.

## Next stages
6. The Fuel Stop: the clerk, buying beer, money, the trunk, stocking the fridge and the robbery.
7. The police.
8. The pause menu and a Windows export.
