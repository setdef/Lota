LOTA WINDOWS KIT
================

This file is all you need to read. The kit asks everything else itself.


What this is
------------
This kit checks Lota on your Windows PC, with its real graphics card,
screen, speakers and controllers, which the test computers Lota builds
on do not have. It runs Winkit, Lota's own small test app for Lota
@LOTA_VERSION@, many times and in many ways, writes down what it did,
asks you a few questions, and puts everything into one zip file for
you to send back. Winkit opens a window with a spinning square for a
few seconds, plays a short beep, and writes down what it found. The kit
holds no game made with Lota.

Kit built @BUILT@ from Lota commit @COMMIT@.


How to run it (about 8 minutes, most of it hands-off)
-----------------------------------------------------
1. Unzip the kit: right-click the zip file you downloaded, choose
   "Extract All...", and click "Extract". (Double-clicking inside the
   zip without extracting it does not work.) Any folder is fine,
   Downloads included.

2. In the new folder, double-click run-kit.cmd.
   The first time, Windows shows a "The publisher could not be
   verified" prompt for run-kit.cmd (Publisher: Unknown, because the
   file has no valid digital signature). That is expected: the kit's
   scripts are not signed, and you can read them, since they are plain
   text. Choose "Run". If you untick "Always ask before opening this
   file" first, Windows stops asking for this copy of the kit.
   If instead a blue "Windows protected your PC" box appears, click
   "More info", then "Run anyway". The kit asks you at the end which
   of these you saw.

3. A black window opens and asks whether to start. Type y and press
   Enter (n stops without running anything). Whenever the kit asks a
   y/n question it takes only y or n, and asks again after anything
   else, so a stray key does not answer for you.

4. HANDS OFF, about 4 minutes. Please do not touch the mouse or the
   keyboard until the black window says "The automatic part is done".
   Winkit's window opens and closes by itself about ten times, for a
   few seconds each and once for 45 seconds. You may hear short beeps.

5. Optional input test, 1 minute. The kit asks whether to do it. If
   you say y, a window opens for 60 seconds: move the mouse, click,
   press some keys, and, if you have a controller, press its buttons
   and move its sticks. Then drag the window around by its title bar
   for a few seconds, and drag its edge to resize it, watching whether
   the white square keeps spinning.

6. Three questions, about 1 minute: which warnings Windows showed, and
   what the square did while you dragged the window. For each, type y
   (yes) or n (no), or just press Enter to skip it; then you may type a
   note, or press Enter for none.

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
whole screen while Winkit runs, and what the programs printed. Look
through the folder before you send it if you want to.


What it does NOT do
-------------------
- It changes no settings of your PC, installs nothing, and needs no
  administrator. run-kit.cmd lets PowerShell run the kit's script for
  this one run only ("-ExecutionPolicy Bypass" applies to that process
  alone).
- It writes only into the kit's folder, except Winkit's own save
  folder (%APPDATA%\winkit) and Windows' temp folder.
- It removes the "downloaded from the internet" mark from the kit's
  own files (Unblock-File), after writing down which had it, so that
  Windows does not ask about each one.
- It sends nothing anywhere. You send the zip yourself.


How to remove everything
------------------------
1. Delete the kit's folder.
2. Delete Winkit's save folder (paste this into Explorer's address
   bar): %APPDATA%\winkit


If something goes wrong
-----------------------
- Every step has a time limit: a program that hangs is closed after
  its limit and the kit goes on. If the kit seems stuck on one step for
  more than 5 minutes, close the black window. The results folder
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
it, and through a junction and a symbolic link, each time reading back
pixels of its own frame; where Winkit saved; and Windows' own records
of crashes and of Defender. The kit was tested on CI computers with no
graphics card and no sound. Never tried there: the real graphics card,
sound device, controller, monitor scale, Smart App Control, nvidia-smi,
the publisher and SmartScreen prompts, and everything you do by hand.
