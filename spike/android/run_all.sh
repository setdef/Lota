#!/usr/bin/env bash
# The emulator job's runs, one after another, each into a folder of its
# own under OUT; the job fails if any run did, after all have run.
#
#   run_all.sh APKS OUT
set -uo pipefail
apks=$1
out=$2
here=$(cd "$(dirname "$0")" && pwd)
status=0

ruby "$here/emulator.rb" "$apks/LotaSpike-debug.apk" com.kerricklong.lota.LotaSpike "$out/spike" \
  --env LOTA_SPIKE_SECONDS=30 --ready "LotaSpike drew frame 1 " --shot 3 --shot 12 --tap 6:0.5:0.6 --tap 9:0.25:0.3 \
  --shell "11:input keyevent KEYCODE_HOME" --shot 13 \
  --shell "16:am start -n PACKAGE/org.setdef.fledge.host.MainActivity" --shot 19 \
  --shell "22:input keyevent KEYCODE_BACK" --shot 24 --timeout 300 \
  --expect "LotaSpike loaded on" --expect "LotaSpike another thread: ThreadError" \
  --expect "LotaSpike touchpressed" --expect "LotaSpike keypressed key=:escape scancode=:acback" \
  --expect "exited with status" || status=1

ruby "$here/emulator.rb" "$apks/DotPopper-debug.apk" com.kerricklong.DotPopper "$out/dot-popper-autoplay" \
  --env DOT_POPPER_AUTOPLAY=1 --env DOT_POPPER_SEED=7 --env DOT_POPPER_QUIT_AFTER=45 \
  --env DOT_POPPER_SHOTS=3,12,25,38 --env DOT_POPPER_KIT_PROBE=1 --ready "Dot Popper: " \
  --shot 5 --shot 20 --timeout 300 --pull "Dot Popper: screenshot (\\S+)" \
  --expect "Dot Popper: screenshot" --expect "exited with status 0" || status=1

ruby "$here/emulator.rb" "$apks/DotPopper-debug.apk" com.kerricklong.DotPopper "$out/dot-popper-tap" \
  --env DOT_POPPER_SEED=7 --env DOT_POPPER_QUIT_AFTER=40 --env DOT_POPPER_SAVE_AS=tap_test \
  --env DOT_POPPER_SHOTS=2,10,30 --env DOT_POPPER_KIT_PROBE=1 --ready "kit probe: subscribed" \
  --tap 6:0.5:0.5 --pop --shot 4 --shot 15 --shell "18:input keyevent KEYCODE_BACK" --shot 21 \
  --timeout 300 --pull "Dot Popper: screenshot (\\S+)" \
  --expect "kit probe: touchpressed" --expect "kit probe: event Popped" \
  --expect "kit probe: keypressed :escape, :acback, false in (Playing|GameOver)" --expect "exited with status 0" || status=1

# Back on the title: Dot Popper quits itself (Lota::Event.quit).
ruby "$here/emulator.rb" "$apks/DotPopper-debug.apk" com.kerricklong.DotPopper "$out/dot-popper-back-title" \
  --env DOT_POPPER_SAVE_AS=back_test --env DOT_POPPER_KIT_PROBE=1 --ready "kit probe: subscribed" \
  --shot 4 --shell "6:input keyevent KEYCODE_BACK" --timeout 120 \
  --expect "kit probe: keypressed :escape, :acback, false in Title" --expect "exited with status 0" || status=1

exit $status
