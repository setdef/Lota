LOTA WINDOWS KIT
================

What this is
------------
This kit tests Lota games on your Windows PC, with its real graphics
card, screen, speakers and controllers, which the test computers Lota
builds on do not have. It runs two small programs, writes down what
they did, and puts everything in one zip file for you to send back.

  - Winkit, a test app for Lota @LOTA_VERSION@. It opens a small window
    with a spinning square for a few seconds, plays a short beep, and
    writes down what it found.
  - Dot Popper @DOT_POPPER_VERSION@ (from Lota's CI run @DOT_POPPER_RUN@),
    a real game made with Lota. It plays itself for 45 seconds.

Kit built @BUILT@ from Lota commit @COMMIT@.


How to run it
-------------
1. Unzip the kit: right-click the zip file you downloaded, choose
   "Extract All...", and click "Extract". (Double-clicking inside the
   zip without extracting it does not work.) Any folder is fine,
   Downloads included.
2. In the new folder, double-click run-kit.cmd.
3. If a blue "Windows protected your PC" box appears, click
   "More info", then "Run anyway". This happens because the kit is not
   signed; it is expected. Write down that it happened in CHECKLIST.txt
   (question 1).
4. A black window asks one question: whether to also try Dot Popper's
   installer. Type y and press Enter to try it (it adds about 2
   minutes, installs Dot Popper for you only, and removes it again), or
   just press Enter to skip it.
5. Then, for about 6 minutes, please do not touch the mouse or the
   keyboard. Windows will open and close by themselves: Winkit about ten
   times for a few seconds each, once for 45 seconds, Dot Popper twice.
   You may hear short beeps and the game's sounds. The black window
   shows each step as it goes.
6. At the end it asks whether to do the hands-on test. If you have a
   minute, type y and press Enter: a window opens for 60 seconds, in
   which you move the mouse, click, press some keys, and, if you have a
   controller, press its buttons and move its sticks. Otherwise press
   Enter.
7. When it says "Done", an Explorer window opens with the results zip
   selected.


What to send back
-----------------
The one file it names at the end:

  results\lota-kit-results-DATE-TIME.zip   (inside the kit folder)

If you also went through CHECKLIST.txt (optional, about 5 minutes,
some questions need you to look and listen), send CHECKLIST.txt too.
You can type your answers straight into it with Notepad.

The results hold facts about this PC (Windows version, graphics card
and driver, screens, sound devices, controllers, the path of your user
folder, your Windows user name as part of that path), screenshots of
the whole screen while the games run, and what the programs printed.
Look through the folder before you send it if you want to.


What it does NOT do
-------------------
- It changes no settings of your PC, and needs no administrator.
  run-kit.cmd lets PowerShell run the kit's script for that one run
  only ("-ExecutionPolicy Bypass" applies to that process alone).
- It installs nothing, unless you answer y to the installer question;
  then it installs Dot Popper for your user only and uninstalls it a
  minute later.
- It writes only into the kit's folder, except: the games' own save
  folders (%APPDATA%\winkit and %APPDATA%\dot_popper), Windows' temp
  folder, and, with the installer, Dot Popper's install folder
  (%LOCALAPPDATA%\Programs\Dot Popper) and its Start menu shortcut,
  which the uninstall removes.
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
3. If you tried the installer and something went wrong, uninstall
   "Dot Popper" in Settings > Apps > Installed apps.


If something goes wrong
-----------------------
- Every step has a time limit: a program that hangs is closed after
  its limit and the kit goes on. If the whole kit seems stuck for more
  than 5 minutes on one step, close the black window; the results
  folder (results\lota-kit-results-...) holds results.txt up to that
  point: zip that folder and send it.
- If the kit folder is very deep (a long path), unpacking may fail;
  move the kit folder to Downloads and run it again.
- Running the kit again is safe: each run makes a new results folder.


What the kit checks, for the curious
------------------------------------
System facts (Windows build, graphics card and driver, screen size,
scale and refresh rate, sound devices, controllers, Defender and
SmartScreen state); that the kit's files arrived whole (SHA256SUMS);
that the kit itself stops a program that hangs; Winkit started
normally, with a minimal environment, with a Ruby programmer's
variables set, from a folder named with letters outside English, for
45 seconds to measure smoothness, through Explorer's way of starting
programs, from the Command Prompt, closed with its X button, ended as Task Manager ends it, and
through a junction and a symbolic link; Dot Popper playing itself with
and without its glow effects; where the games saved; and Windows'
own records of crashes and of Defender. Steps never tested on a real
PC before (only on CI computers with no graphics card or sound): the
real graphics card, sound device, controller, monitor scale, Smart App
Control, nvidia-smi, the SmartScreen prompt, and the hands-on test
with you at the keyboard.
