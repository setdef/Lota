LOTA WINDOWS KIT
================

This file is all you need to read. The kit asks everything else itself.


What this is
------------
This kit tests Lota games on your Windows PC, with its real graphics
card, screen, speakers and controllers, which the test computers Lota
builds on do not have. It runs two programs, writes down what they did,
asks you a few questions, and puts everything into one zip file for you
to send back.

  - Winkit, a small test app for Lota @LOTA_VERSION@. It opens a window
    with a spinning square for a few seconds, plays a short beep, and
    writes down what it found.
  - Dot Popper @DOT_POPPER_VERSION@, a real game made with Lota (built by
    Lota's CI run @DOT_POPPER_RUN@). It first plays itself; later, if you
    like, you play it.

Kit built @BUILT@ from Lota commit @COMMIT@.


How to run it (about 20 minutes, half of it hands-off)
------------------------------------------------------
1. Unzip the kit: right-click the zip file you downloaded, choose
   "Extract All...", and click "Extract". (Double-clicking inside the
   zip without extracting it does not work.) Any folder is fine,
   Downloads included.

2. In the new folder, double-click run-kit.cmd.
   If a blue "Windows protected your PC" box appears, click
   "More info", then "Run anyway". It appears because the kit is not
   signed. Remember what it said: the kit asks you about it at the end.

3. A black window opens and asks one question: whether to also try
   Dot Popper's installer. Type y and press Enter to try it (about 2
   more minutes; it installs Dot Popper for you only, starts it once,
   and uninstalls it again), or just press Enter to skip it.

4. HANDS OFF, about 6 minutes. Please do not touch the mouse or the
   keyboard until the black window says "The automatic part is done".
   Windows open and close by themselves: Winkit about ten times for a
   few seconds each and once for 45 seconds, then Dot Popper playing
   itself twice. You may hear short beeps and the game's sounds.

5. Optional input test, 1 minute. The kit asks whether to do it. If
   you say y, a window opens for 60 seconds: move the mouse, click,
   press some keys, and, if you have a controller, press its buttons
   and move its sticks.

6. Optional hand checks, about 10 minutes. The kit lists some things to
   try in Dot Popper, asks whether you have a controller, then starts
   Dot Popper for you (no longer playing itself). Play it, try the
   things on the list, and quit it with Escape. Then the black window
   asks about each thing, one at a time:
     - type y (yes), n (no), or just press Enter to skip;
     - where it asks for a number, type 1 to 5;
     - after each answer you may type a note, or press Enter for none;
     - for "Copy my result", paste it into the black window (Ctrl+V or
       right-click), then press Enter on an empty line.
   You can answer after you have quit the game. If you want to stop,
   just press Enter through the rest.

7. When it says "Done", an Explorer window opens with the results zip
   selected. Press any key to close the black window.


What to send back
-----------------
The one file it names at the end:

  results\lota-kit-results-DATE-TIME.zip   (inside the kit folder)

It holds results.txt (everything the kit measured, and your answers)
and screenshots. That is everything; there is nothing else to fill in.

The results hold facts about this PC (Windows version, graphics card
and driver, screens, sound devices, controllers, the path of your user
folder, which includes your Windows user name), screenshots of the
whole screen while the games run, and what the programs printed. Look
through the folder before you send it if you want to.


What it does NOT do
-------------------
- It changes no settings of your PC and needs no administrator.
  run-kit.cmd lets PowerShell run the kit's script for this one run
  only ("-ExecutionPolicy Bypass" applies to that process alone).
- It installs nothing, unless you answer y to the installer question;
  then it installs Dot Popper for your user only and uninstalls it a
  minute later.
- It writes only into the kit's folder, except: the games' own save
  folders (%APPDATA%\winkit and %APPDATA%\dot_popper), Windows' temp
  folder, and, with the installer, Dot Popper's install folder
  (%LOCALAPPDATA%\Programs\Dot Popper) and its Start menu shortcut,
  which the uninstall removes again.
- It removes the "downloaded from the internet" mark from the kit's
  own files (Unblock-File), after writing down which had it, so that
  Windows does not ask about each one.
- It sends nothing anywhere. You send the zip yourself.


How to remove everything
------------------------
1. Delete the kit's folder.
2. Delete these two folders (paste each into Explorer's address bar):
     %APPDATA%\winkit
     %APPDATA%\dot_popper
3. Only if you tried the installer and something went wrong: uninstall
   "Dot Popper" in Settings > Apps > Installed apps.


If something goes wrong
-----------------------
- Every step has a time limit: a program that hangs is closed after
  its limit and the kit goes on. If the kit seems stuck on one step for
  more than 5 minutes (outside the hand checks, where it waits for you
  up to 20 minutes), close the black window. The results folder
  (results\lota-kit-results-...) already holds results.txt up to that
  point: right-click the folder, choose "Send to" > "Compressed
  (zipped) folder", and send that zip.
- If unpacking fails, the kit folder may be too deep (a very long
  path): move it to Downloads and run it again.
- Running the kit again is safe: each run makes a new results folder.


What the kit checks, for the curious
------------------------------------
System facts (Windows build, graphics card and driver, screen size,
scale and refresh rate, sound devices, controllers, Defender, SmartScreen
and Smart App Control); that the kit's files arrived whole
(SHA256SUMS); that the kit itself stops a program that hangs; Winkit
started normally, with a minimal environment, with a Ruby programmer's
variables set, from a folder named with letters outside English, for 45
seconds to measure smoothness, the way Explorer starts programs, from
the Command Prompt, closed with its X button, ended as Task Manager ends
it, and through a junction and a symbolic link; Dot Popper playing
itself for 45 seconds with its frame-rate log on, and for 15 seconds
without its glow effects; where the games saved; and Windows' own
records of crashes and of Defender. The kit was tested on CI computers
with no graphics card and no sound. Never tried before on a real PC:
the real graphics card, sound device, controller, monitor scale, Smart
App Control, nvidia-smi, the SmartScreen prompt, and everything you do
by hand.
