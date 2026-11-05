// SPDX-FileCopyrightText: 2026 Kerrick Long <me@kerricklong.com>
// SPDX-License-Identifier: AGPL-3.0-or-later

package org.setdef.fledge.host;

import android.Manifest;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Rect;
import android.media.AudioManager;
import android.os.Build;
import android.os.Bundle;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.system.ErrnoException;
import android.system.Os;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.DisplayCutout;
import android.view.WindowManager;
import android.window.OnBackInvokedDispatcher;
import org.libsdl.app.SDLActivity;
import org.setdef.fledge.FledgeRuby;

/**
 * A Lota game's screen on Android: Fledge's SDL host (examples/sdl_phone,
 * its ADR 025), which loads libSDL3.so first, whose JNI_OnLoad registers
 * SDL's Java methods, then OpenAL Soft, Ruby, and the app's extensions,
 * and runs the app's Ruby program from SDL's main on a thread with
 * FledgeRuby's 64 MB stack, which SDLThread waits for, so the game ends
 * when Ruby does; with the methods of love-android's GameActivity that
 * LÖVE's engine calls through JNI (vendor/love/src/common/android.cpp)
 * without checking that they exist: setImmersiveMode from every
 * love.window.setMode, getDPIScale for the window's scale, and the rest.
 *
 * In a debuggable build only, each string extra of the launching intent
 * named lota.env.NAME sets the environment variable NAME before Ruby
 * starts, so a test can pass a game its settings with am start --es.
 */
public class MainActivity extends SDLActivity {
    private static final String ENV_PREFIX = "lota.env.";

    private Vibrator vibrator;
    private boolean shortEdgesMode;

    @Override
    protected String[] getLibraries() {
        return new String[] {"SDL3", "openal", "fledgeruby", "fledgeext"};
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        if (checkSelfPermission(Manifest.permission.VIBRATE) == PackageManager.PERMISSION_GRANTED) {
            vibrator = (Vibrator) getSystemService(Context.VIBRATOR_SERVICE);
        }
        super.onCreate(savedInstanceState);
        trapPredictiveBack();
        // SPDX-SnippetBegin
        // SPDX-SnippetCopyrightText: 2006-2024 LOVE Development Team
        // SPDX-License-Identifier: Zlib
        // love-android's GameActivity.onCreate (app/src/main/java/org/love2d/android/GameActivity.java at
        // 1c89bb0b2e, lines 117-121).
        if (Build.VERSION.SDK_INT >= 28) {
            WindowManager.LayoutParams attr = getWindow().getAttributes();
            attr.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_NEVER;
            shortEdgesMode = false;
        }
        // SPDX-SnippetEnd
    }

    @Override
    protected void main() {
        String tag = getPackageName();
        CharSequence name = getApplicationInfo().loadLabel(getPackageManager());
        setEnvironmentFromIntent(tag);
        Thread ruby = FledgeRuby.startApp(this, "fledge.zip", new String[0], status -> Log.i(tag, name + " exited with status " + status));
        try {
            ruby.join();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /**
     * SDL traps Back in onBackPressed when the manifest sets
     * SDL_ENV.SDL_ANDROID_TRAP_BACK_BUTTON, but an app that targets API 36
     * gets predictive back, where the system's own callback takes Back and
     * closes the activity without calling onBackPressed (an emulator of API
     * 36 did, after the game had its escape key). So when the manifest asks
     * for the trap, a callback that does nothing takes Back's place, and the
     * game alone decides, from the key SDL still sends. Before Android 16,
     * without android:enableOnBackInvokedCallback, the system ignores the
     * callback and calls onBackPressed, where SDL traps Back itself.
     * Whether a back gesture on Android 16, rather than a Back key, still
     * sends the game its key was not tried.
     */
    private void trapPredictiveBack() {
        if (Build.VERSION.SDK_INT < 33) {
            return;
        }
        try {
            Bundle meta = getPackageManager().getApplicationInfo(getPackageName(), PackageManager.GET_META_DATA).metaData;
            if (meta == null || !"1".equals(String.valueOf(meta.get("SDL_ENV.SDL_ANDROID_TRAP_BACK_BUTTON")))) {
                return;
            }
        } catch (PackageManager.NameNotFoundException e) {
            return;
        }
        getOnBackInvokedDispatcher().registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT, () -> {});
    }

    private void setEnvironmentFromIntent(String tag) {
        Bundle extras = getIntent().getExtras();
        if (extras == null || (getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) == 0) {
            return;
        }
        for (String key : extras.keySet()) {
            Object value = extras.get(key);
            if (!key.startsWith(ENV_PREFIX) || !(value instanceof String)) {
                continue;
            }
            String variable = key.substring(ENV_PREFIX.length());
            try {
                Os.setenv(variable, (String) value, true);
                Log.i(tag, "environment " + variable + "=" + value);
            } catch (ErrnoException e) {
                Log.e(tag, "could not set " + variable, e);
            }
        }
    }

    // SPDX-SnippetBegin
    // SPDX-SnippetCopyrightText: 2006-2024 LOVE Development Team
    // SPDX-License-Identifier: Zlib
    // love-android's GameActivity (app/src/main/java/org/love2d/android/GameActivity.java at 1c89bb0b2e,
    // lines 203-303), the methods src/common/android.cpp calls, without androidx: vibrate,
    // hasBackgroundMusic, getDPIScale, getSafeArea, setImmersiveMode, getImmersiveMode, and
    // hasRecordAudioPermission.
    public void vibrate(double seconds) {
        if (vibrator != null) {
            long duration = (long) (seconds * 1000.);
            vibrator.vibrate(VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE));
        }
    }

    public boolean hasBackgroundMusic() {
        AudioManager audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);
        return audioManager.isMusicActive();
    }

    public float getDPIScale() {
        DisplayMetrics metrics = getResources().getDisplayMetrics();
        return metrics.density;
    }

    public Rect getSafeArea() {
        Rect rect = null;

        if (Build.VERSION.SDK_INT >= 28) {
            DisplayCutout cutout = getWindow().getDecorView().getRootWindowInsets().getDisplayCutout();

            if (cutout != null) {
                rect = new Rect();
                rect.set(
                    cutout.getSafeInsetLeft(),
                    cutout.getSafeInsetTop(),
                    cutout.getSafeInsetRight(),
                    cutout.getSafeInsetBottom()
                );
            }
        }

        return rect;
    }

    public void setImmersiveMode(boolean enable) {
        if (Build.VERSION.SDK_INT >= 28) {
            WindowManager.LayoutParams attr = getWindow().getAttributes();

            if (enable) {
                attr.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
            } else {
                attr.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_NEVER;
            }
        }

        shortEdgesMode = enable;
    }

    public boolean getImmersiveMode() {
        return shortEdgesMode;
    }

    public boolean hasRecordAudioPermission() {
        return checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
    }
    // SPDX-SnippetEnd
}
