# John's Beer Run: Godot 4.3 port (v2.8, stage 7)

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
  - It starts empty. Buy a case at the Fuel Stop.
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
- **The Fuel Stop (stage 6):**
  - **Money:** John starts with $500.
  - **Dale the clerk:** greets John and keeps an eye on him.
  - **Buying beer:** grab a case of Lumberjack from the stack in the back and pay at the register ($18.99). Dale won't let you walk out without paying.
  - **Getting it home:** carry it home in both arms, or put it in the M1's trunk (E at the back of the car, the boot lid opens). Then stock the fridge for 12 more beers.
  - **The robbery:** aim the Glock at Dale and his hands go up. E at the register demands the cash ($380–720). Any gunfire in the store spooks him, and a 90-second Wanted timer starts with a siren building in the distance.
  - **Shooting Dale:** hits react by body part. An arm hit spins him, a leg hit drops him to one knee, body hits make him hunch and bleed. Three body hits or one headshot kills him.
  - **His death:** he goes into a real physics ragdoll and a blood pool spreads under him. Then John can walk behind the counter and rob the till himself.
  - **Stray bullets** in the store knock products off the shelves, and they bounce and roll on the floor.
- **The Pine Hollow police (stage 7):**
  - **Patrols:** one cruiser patrols Main Street and the cul-de-sac. Two wait in the station lot.
  - **Pathfinding:** when John is Wanted, all three light up and find their own way to him around houses, poles and buildings.
  - **Officers on foot:** near John, an officer jumps out and chases him on foot. Officers can follow John into the Fuel Stop.
  - **Line of sight:** the HUD shows SPOTTED while a cop can see John and SEARCHING when they've lost him. The Wanted clock only runs down while they can't see him.
  - **Searching:** they drive to where he was last seen and search the area, with roof spotlights sweeping the yards.
  - **Hiding in the cabin:** with the door shut, they surround the porch, call him out, and come in after about 6 seconds.
  - **In the car:** if a cruiser boxes in the M1 while it's going slowly, John is pulled out and arrested.
  - **Getting caught** means BUSTED.
  - **3D sirens:** every cruiser has its own siren that comes from its direction and doppler-shifts as it passes. The red and blue lights wash over the houses.
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

## Editing in the Godot editor
Open `scenes/main.tscn`. Everything is placed in the scene, so you can see it and move it:
- **World:** the cabin, the neighborhood, the town, the Fuel Stop and the terrain.
- **World → Streetlights:** 8 lamps. You can move, duplicate or delete them, and each one's light, fill and glow will follow. You can also change a lamp's brightness, color and range on its **Light** node.
- **John:** his starting spot. Where he spawns at the start of a night is set in code (in front of the recliner).
- **M1:** the car. Its parking spot is set in `car.gd`.
- **Visitor:** he's hidden until he walks up during the game.
- **Glock:** the gun on the side table.

A few things are still set up when the game starts and only show up when you press F5: materials and tints, collision, the wheel pivots, and the effects.

## Project layout
- `scripts/game.gd`: the game controller (states, actions, timing, camera, effects).
- `scripts/john.gd`: John's rig. It blends the drinking animation with procedural walking, reaching and bending, arm IK and the head droop.
- `scripts/world.gd`: loads the world, adds collision and tunes the lights.
- `scripts/hud.gd`, `scripts/menu.gd`, `scripts/tv.gd`, `scripts/post.gdshader`, `scripts/sfx.gd`: the HUD, menus, TV picture, screen effects and sound.
- `tools/synth.py`: renders the game's sound effects to the WAV files in `assets/sfx`.
- `tools/glb_jpeg.py`: shrinks the textures inside the world files.

## Test run
`godot -- --scenario=tour --shots=/tmp/t` (or `--scenario=visitor`, `--scenario=gun`, `--scenario=drive`, `--scenario=outside`, `--scenario=store`, `--scenario=rob`, `--scenario=police`, `--scenario=hide`) plays through the actions and saves screenshots.

## Next stages
8. The pause menu and a Windows export.
