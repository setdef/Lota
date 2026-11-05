Dot Popper and the Lota spike on an Android phone (OnePlus Nord N30 5G, Android 13)
===================================================================================

Answer the questions in android-results.txt and send this file back
(android-results.txt, with the screenshots and the log described below).

What these files are
--------------------
DotPopper-debug.apk   Dot Popper (Lota from this branch, Fledge v0.5.0), signed
                      with the Android SDK's debug key. It holds code for
                      arm64-v8a (your phone) and x86_64 (the emulator CI ran).
LotaSpike-debug.apk   Lota's small test game: a colored background, a yellow
                      rectangle, a line of text, and a white square where you
                      touch. It quits by itself after 40 seconds.
SHA256SUMS            The SHA-256 of each APK. Check it before you install.
android-results.txt   The questions to answer, and send back.
emulator/             What CI's x86_64 emulator printed and showed, to compare.

Read this first
---------------
arm64-v8a has NEVER run anywhere. CI ran only the x86_64 build, on an
emulator. Your phone is the first arm64 run, so expect it may fail. If it
fails at launch you will see the app close at once, or "Dot Popper keeps
stopping". That is still useful: please send the log (below).

The 16 KB page-size alignment Android asks for is already handled: every
library in the APK is linked for 16 KB pages and the APK passes
`zipalign -c -P 16`. (Your phone uses 4 KB pages; both work.)

The first launch takes a few seconds longer: the app unpacks its Ruby and
the game into its own storage once per installed version.

Android's Back
--------------
In this Dot Popper build the game decides what Back does: its Android
project asks SDL to trap Back, with this line in AndroidManifest.xml,
inside <application>:

    <meta-data android:name="SDL_ENV.SDL_ANDROID_TRAP_BACK_BUTTON" android:value="1" />

Back then reaches the game as the key :escape (scancode :acback), as in
LÖVE, and nothing else happens; on the title, Dot Popper leaves the app
itself with Lota::Event.quit. Without that line, which is LÖVE's and
Lota's default, the game still gets :escape, and then Android closes the
app at once. LotaSpike keeps the default.

Way 1: install with adb from a computer (recommended, it gives you the log)
---------------------------------------------------------------------------
1. On the phone: Settings > About device > Version > tap "Build number"
   seven times, and enter your PIN. "You are now a developer" appears.
   (On some OxygenOS builds Build number is under Settings > About device.)
2. Settings > System settings > Developer options > turn on "USB debugging".
3. On the computer, install Android's platform tools (they contain adb):
   https://developer.android.com/tools/releases/platform-tools
4. Connect the phone by USB. On the phone, allow "USB debugging" for this
   computer when it asks (tick "Always allow").
5. Check that adb sees it:            adb devices
   It should list one device as "device" (not "unauthorized").
6. Check the files, then install:     shasum -a 256 -c SHA256SUMS
                                      adb install -r DotPopper-debug.apk
                                      adb install -r LotaSpike-debug.apk
   If adb says INSTALL_FAILED_UPDATE_INCOMPATIBLE, an earlier kit's app is
   installed (each CI run signs with a debug key of its own): run
   adb uninstall com.kerricklong.DotPopper, then install again.
   If Play Protect asks about an app from an unknown developer, choose
   "Install anyway" (or "More details" > "Install anyway").
7. Start the log before you open the app, in a second terminal:
     adb logcat -c
     adb logcat -v threadtime > lota-phone-log.txt
   then open "Dot Popper" (or "LotaSpike") from the app drawer, play a
   little, and press Ctrl-C in the log terminal.
   To watch only the game's own lines while it runs:
     adb logcat -s com.kerricklong.DotPopper:V SDL:V
     adb logcat -s com.kerricklong.lota.LotaSpike:V SDL:V

Way 2: copy the APK to the phone and open it
--------------------------------------------
1. Copy DotPopper-debug.apk to the phone (USB file transfer, or download it).
2. Open it in the Files app. Android asks to allow installs from that app:
   Settings opens; turn on "Allow from this source", go back, and Install.
3. If Play Protect warns, choose "Install anyway".
   This way gives no log unless you also connect adb as in Way 1.

Evidence to collect (with adb, Way 1)
-------------------------------------
- The game's own lines only, after playing:
    adb logcat -d -v threadtime -s com.kerricklong.DotPopper:V SDL:V > dot-popper-log.txt
- The first line the game prints, which says Ruby and Lota started:
    adb logcat -d -v raw -s com.kerricklong.DotPopper:V | head -3
- A screenshot from the computer while the game shows something:
    adb exec-out screencap -p > dot-popper-1.png
  (or press power + volume down on the phone).
- After a crash, everything:  adb logcat -d > lota-phone-log.txt
- The line "exited with status N" if the log has one.

What to send back
-----------------
- android-results.txt, filled in.
- The screenshots, dot-popper-log.txt, and lota-phone-log.txt if it crashed.

To remove the apps:  adb uninstall com.kerricklong.DotPopper
                     adb uninstall com.kerricklong.lota.LotaSpike
or long-press the app icon > App info > Uninstall.
