param(
  [Parameter(Mandatory = $true)]
  [string]$ManifestPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "AndroidManifest.xml bulunamadi: $ManifestPath"
}

$xml = [System.IO.File]::ReadAllText($ManifestPath)
$xml = $xml.Replace('android:label="okeyx_mobile"', 'android:label="OkeyX"')
$xml = $xml.Replace('android:launchMode="singleTop"', 'android:launchMode="singleTask"')
if ($xml -notmatch 'android:screenOrientation="landscape"') {
  $xml = $xml.Replace('android:name=".MainActivity"', 'android:name=".MainActivity" android:screenOrientation="landscape" android:resizeableActivity="true"')
}
if ($xml -notmatch 'android:usesCleartextTraffic') {
  $xml = $xml.Replace('<application', '<application android:usesCleartextTraffic="false"')
}


# Release networking is HTTPS-only. Normalize old generated shells too.
$xml = $xml.Replace('android:usesCleartextTraffic="true"', 'android:usesCleartextTraffic="false"')

if ($xml -notmatch 'android.permission.INTERNET') {
  $xml = $xml.Replace(
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
    "<manifest xmlns:android=`"http://schemas.android.com/apk/res/android`">`r`n    <uses-permission android:name=`"android.permission.INTERNET`" />"
  )
}

foreach ($permission in @('android.permission.RECORD_AUDIO','android.permission.MODIFY_AUDIO_SETTINGS','android.permission.BLUETOOTH','android.permission.BLUETOOTH_ADMIN','android.permission.BLUETOOTH_CONNECT','android.permission.CAMERA')) {
  if ($xml -notmatch [regex]::Escape($permission)) {
    $xml = $xml.Replace(
      '<uses-permission android:name="android.permission.INTERNET" />',
      "<uses-permission android:name=`"android.permission.INTERNET`" />`r`n    <uses-permission android:name=`"$permission`" />"
    )
  }
}

if ($xml -notmatch 'android.hardware.microphone') {
  $xml = $xml.Replace(
    '<uses-permission android:name="android.permission.INTERNET" />',
    '<uses-permission android:name="android.permission.INTERNET" />' + "`r`n    <uses-feature android:name=`"android.hardware.microphone`" android:required=`"false`" />"
  )
}


# OKEYX_V1123_WORKMANAGER_STARTUP_FIX
# Release crash log showed AndroidX Startup killing the process before Flutter:
# "Failed to create an instance of androidx.work.impl.WorkDatabase".
# OkeyX does not call WorkManager directly, so prevent WorkManager's automatic
# ContentProvider startup. Other AndroidX Startup initializers remain untouched.
if ($xml -notmatch 'xmlns:tools="http://schemas.android.com/tools"') {
  $xml = $xml.Replace(
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
    '<manifest xmlns:android="http://schemas.android.com/apk/res/android" xmlns:tools="http://schemas.android.com/tools">'
  )
}
if ($xml -notmatch 'OKEYX_WORKMANAGER_AUTO_INIT_DISABLED') {
  $workManagerDisable = @'
        <!-- OKEYX_WORKMANAGER_AUTO_INIT_DISABLED -->
        <provider
            android:name="androidx.startup.InitializationProvider"
            android:authorities="${applicationId}.androidx-startup"
            android:exported="false"
            tools:node="merge">
            <meta-data
                android:name="androidx.work.WorkManagerInitializer"
                tools:node="remove" />
        </provider>
'@
  $xml = $xml.Replace('    </application>', "$workManagerDisable    </application>")
}

# Google Mobile Ads requires an application id in the manifest. Use Google's
# official sample id for local/test builds unless a real OkeyX id is supplied.
$admobAppId = if ($env:OKEYX_ADMOB_APP_ID) { $env:OKEYX_ADMOB_APP_ID } else { 'ca-app-pub-3940256099942544~3347511713' }
if ($xml -notmatch 'com.google.android.gms.ads.APPLICATION_ID') {
  $meta = "        <meta-data android:name=`"com.google.android.gms.ads.APPLICATION_ID`" android:value=`"$admobAppId`" />`r`n"
  $xml = $xml.Replace('    </application>', "$meta    </application>")
}
if ($xml -notmatch 'com.google.android.gms.permission.AD_ID') {
  $xml = $xml.Replace(
    '<uses-permission android:name="android.permission.INTERNET" />',
    "<uses-permission android:name=`"android.permission.INTERNET`" />`r`n    <uses-permission android:name=`"com.google.android.gms.permission.AD_ID`" />"
  )
}

# image_cropper 12.x: modern uCrop integration.
# v10+ no longer needs the Android 15 values-v35 workaround.
if ($xml -notmatch 'com\.yalantis\.ucrop\.UCropActivity') {
  $ucropActivity = @'
        <activity
            android:name="com.yalantis.ucrop.UCropActivity"
            android:screenOrientation="portrait"
            android:theme="@style/Theme.AppCompat.Light.NoActionBar" />
'@
  $xml = $xml.Replace('    </application>', "$ucropActivity    </application>")
} else {
  $xml = $xml.Replace('android:theme="@style/Ucrop.CropTheme"', 'android:theme="@style/Theme.AppCompat.Light.NoActionBar"')
}

if ($xml -notmatch 'android:scheme="okeyx"') {
  $intentFilter = @'
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="okeyx" android:host="auth" android:pathPrefix="/callback" />
            </intent-filter>
'@
  $xml = $xml.Replace('        </activity>', "$intentFilter        </activity>")
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ManifestPath, $xml, $utf8)

# Remove the obsolete v9 edge-to-edge workaround if it exists from an older shell.
$mobileDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$androidMain = Split-Path -Parent $ManifestPath
$resDir = Join-Path $androidMain 'res'
$values35Path = Join-Path (Join-Path $resDir 'values-v35') 'styles.xml'
if (Test-Path -LiteralPath $values35Path) {
  Remove-Item -LiteralPath $values35Path -Force -ErrorAction SilentlyContinue
}
$values35Dir = Join-Path $resDir 'values-v35'
if ((Test-Path -LiteralPath $values35Dir) -and -not (Get-ChildItem -LiteralPath $values35Dir -Force -ErrorAction SilentlyContinue)) {
  Remove-Item -LiteralPath $values35Dir -Force -ErrorAction SilentlyContinue
}

# OkeyX production launcher icon. Android shell is generated on the user's PC,
# so copy the bundled density-specific icons after the shell exists.
$iconRoot = Join-Path $mobileDir 'android_icons'
foreach ($density in @('mdpi','hdpi','xhdpi','xxhdpi','xxxhdpi')) {
  $source = Join-Path $iconRoot ("mipmap-" + $density + "\\ic_launcher.png")
  $targetDir = Join-Path $resDir ("mipmap-" + $density)
  if (Test-Path -LiteralPath $source) {
    if (-not (Test-Path -LiteralPath $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    Copy-Item -LiteralPath $source -Destination (Join-Path $targetDir 'ic_launcher.png') -Force
  }
}


# V11.0.3: A few Flutter plugins still hard-code an old Android compileSdk
# inside their own cached Gradle projects. New AndroidX artifacts require API
# 34+, even when the OkeyX app itself already targets a modern SDK. Patch the
# resolved plugin Gradle files after `flutter pub get`. This changes compileSdk
# only; it does NOT raise minSdk or the Android version required on the phone.
$packageConfig = Join-Path $mobileDir '.dart_tool\package_config.json'
if (Test-Path -LiteralPath $packageConfig) {
  try {
    $pkg = Get-Content -LiteralPath $packageConfig -Raw | ConvertFrom-Json
    $pluginsToPatch = @('flutter_webrtc', 'image_cropper')
    foreach ($pluginName in $pluginsToPatch) {
      $plugin = $pkg.packages | Where-Object { $_.name -eq $pluginName } | Select-Object -First 1
      if ($null -eq $plugin) { continue }

      $rootUri = [System.Uri]::new($plugin.rootUri)
      if ($rootUri.IsFile) {
        $pluginRoot = $rootUri.LocalPath
      } else {
        $pluginRoot = Join-Path $mobileDir $plugin.rootUri
      }
      $pluginRoot = [System.IO.Path]::GetFullPath($pluginRoot)

      foreach ($gradleName in @('android\build.gradle','android\build.gradle.kts')) {
        $gradlePath = Join-Path $pluginRoot $gradleName
        if (-not (Test-Path -LiteralPath $gradlePath)) { continue }

        $gradle = [System.IO.File]::ReadAllText($gradlePath)
        $original = $gradle
        # Groovy: compileSdkVersion 31 / compileSdk 33
        $gradle = [regex]::Replace($gradle, '(?m)(compileSdkVersion\s+)(\d+)', '${1}36')
        $gradle = [regex]::Replace($gradle, '(?m)(compileSdk\s+)(\d+)', '${1}36')
        # Kotlin DSL: compileSdk = 33
        $gradle = [regex]::Replace($gradle, '(?m)(compileSdk\s*=\s*)(\d+)', '${1}36')

        if ($gradle -ne $original) {
          [System.IO.File]::WriteAllText($gradlePath, $gradle, $utf8)
          # Patched silently; release builder keeps successful output clean.
        }
      }
    }
  } catch {
    throw "Plugin compileSdk otomatik duzeltmesi basarisiz: $($_.Exception.Message)"
  }
}

# V11.0.18 release hygiene:
# - modernize Java/Kotlin target for resolved native plugins
# - REMOVE keepDebugSymbols. Flutter 3.32+ can fail AAB post-processing when
#   jniLibs.keepDebugSymbols is present, and keeping every .so symbol also
#   bloats the APK dramatically.
if (Test-Path -LiteralPath $packageConfig) {
  try {
    $pkg = Get-Content -LiteralPath $packageConfig -Raw | ConvertFrom-Json
    foreach ($pluginName in @('flutter_webrtc','image_cropper')) {
      $plugin = $pkg.packages | Where-Object { $_.name -eq $pluginName } | Select-Object -First 1
      if ($null -eq $plugin) { continue }
      $rootUri = [System.Uri]::new($plugin.rootUri)
      $pluginRoot = if ($rootUri.IsFile) { $rootUri.LocalPath } else { Join-Path $mobileDir $plugin.rootUri }
      $pluginRoot = [System.IO.Path]::GetFullPath($pluginRoot)
      foreach ($gradleName in @('android\build.gradle','android\build.gradle.kts')) {
        $gradlePath = Join-Path $pluginRoot $gradleName
        if (-not (Test-Path -LiteralPath $gradlePath)) { continue }
        $g = [System.IO.File]::ReadAllText($gradlePath)
        $before = $g
        $g = $g.Replace('JavaVersion.VERSION_1_8','JavaVersion.VERSION_17')
        $g = $g.Replace("jvmTarget = '1.8'", "jvmTarget = '17'")
        $g = $g.Replace('jvmTarget = "1.8"', 'jvmTarget = "17"')
        $g = $g.Replace('jvmTarget = JvmTarget.JVM_1_8', 'jvmTarget = JvmTarget.JVM_17')
        if ($g -ne $before) { [System.IO.File]::WriteAllText($gradlePath, $g, $utf8) }
      }
    }
  } catch { }
}

$androidDir = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $androidMain))
$gradleProps = Join-Path $androidDir 'gradle.properties'
$props = if (Test-Path -LiteralPath $gradleProps) { [System.IO.File]::ReadAllText($gradleProps) } else { '' }
if ($props -notmatch '(?m)^org\.gradle\.warning\.mode=') { $props += "`r`norg.gradle.warning.mode=none`r`n" }
[System.IO.File]::WriteAllText($gradleProps, $props, $utf8)

# Remove any keepDebugSymbols block inserted by older OkeyX builders.
foreach ($appGradle in @(
  (Join-Path $androidDir 'app\build.gradle.kts'),
  (Join-Path $androidDir 'app\build.gradle')
)) {
  if (-not (Test-Path -LiteralPath $appGradle)) { continue }
  $g = [System.IO.File]::ReadAllText($appGradle)

  # Remove the exact legacy OkeyX block.
  $g = [regex]::Replace(
    $g,
    '(?s)\r?\n// OKEYX_KEEP_NATIVE_SYMBOLS\r?\nandroid\s*\{\s*packaging(?:Options)?\s*\{\s*jniLibs\s*\{\s*keepDebugSymbols.*?\}\s*\}\s*\}\s*',
    "`r`n"
  )
  # Also remove stray keepDebugSymbols lines if an older generated shell has them.
  $g = [regex]::Replace($g, '(?m)^\s*keepDebugSymbols.*\r?\n?', '')
  [System.IO.File]::WriteAllText($appGradle, $g, $utf8)
}

# Release ABI policy: ship arm64-v8a only for the RC.
# This strips x86/x64/32-bit native WebRTC payloads from APK/AAB and avoids
# packaging hundreds of MB of unused native libraries.
$appKts = Join-Path $androidDir 'app\build.gradle.kts'
if (Test-Path -LiteralPath $appKts) {
  $g = [System.IO.File]::ReadAllText($appKts)
  if ($g -notmatch 'OKEYX_ARM64_RELEASE') {
    $g = [regex]::Replace(
      $g,
      '(?s)(defaultConfig\s*\{)',
      '$1' + "`r`n        // OKEYX_ARM64_RELEASE`r`n        ndk { abiFilters += setOf(`"arm64-v8a`") }",
      1
    )
    [System.IO.File]::WriteAllText($appKts, $g, $utf8)
  }
} else {
  $appGroovy = Join-Path $androidDir 'app\build.gradle'
  if (Test-Path -LiteralPath $appGroovy) {
    $g = [System.IO.File]::ReadAllText($appGroovy)
    if ($g -notmatch 'OKEYX_ARM64_RELEASE') {
      $g = [regex]::Replace(
        $g,
        '(?s)(defaultConfig\s*\{)',
        '$1' + "`r`n        // OKEYX_ARM64_RELEASE`r`n        ndk { abiFilters `"arm64-v8a`" }",
        1
      )
      [System.IO.File]::WriteAllText($appGroovy, $g, $utf8)
    }
  }
}

# OKEYX_ZERO_NOISE_COMPILERS
# Third-party plugins can still compile old Java sources. Treat their deprecated
# API chatter as dependency-internal noise while keeping actual compiler errors fatal.
$rootBuildKts = Join-Path $androidDir 'build.gradle.kts'
$rootBuildGroovy = Join-Path $androidDir 'build.gradle'
if (Test-Path -LiteralPath $rootBuildKts) {
  $g = [System.IO.File]::ReadAllText($rootBuildKts)
  if ($g -notmatch 'OKEYX_ZERO_NOISE_COMPILERS') {
    $g += @'

// OKEYX_ZERO_NOISE_COMPILERS
subprojects {
    tasks.withType<org.gradle.api.tasks.compile.JavaCompile>().configureEach {
        options.compilerArgs.addAll(listOf("-Xlint:none", "-nowarn"))
    }
}
'@
    [System.IO.File]::WriteAllText($rootBuildKts, $g, $utf8)
  }
} elseif (Test-Path -LiteralPath $rootBuildGroovy) {
  $g = [System.IO.File]::ReadAllText($rootBuildGroovy)
  if ($g -notmatch 'OKEYX_ZERO_NOISE_COMPILERS') {
    $g += @'

// OKEYX_ZERO_NOISE_COMPILERS
subprojects {
    tasks.withType(JavaCompile).configureEach {
        options.compilerArgs += ['-Xlint:none', '-nowarn']
    }
}
'@
    [System.IO.File]::WriteAllText($rootBuildGroovy, $g, $utf8)
  }
}


# OKEYX_V1119_JVM17_HARDENING
# Hard-fix Java/Kotlin target mismatch in native plugins.
# This edits the resolved pub-cache plugin Gradle files after flutter pub get.
$packageConfig = Join-Path $mobileDir '.dart_tool\package_config.json'
if (Test-Path -LiteralPath $packageConfig) {
  try {
    $pkg = Get-Content -LiteralPath $packageConfig -Raw | ConvertFrom-Json
    foreach ($pluginName in @('flutter_webrtc','image_cropper')) {
      $plugin = $pkg.packages | Where-Object { $_.name -eq $pluginName } | Select-Object -First 1
      if ($null -eq $plugin) { continue }

      $rootUri = [System.Uri]::new($plugin.rootUri)
      $pluginRoot = if ($rootUri.IsFile) { $rootUri.LocalPath } else { Join-Path $mobileDir $plugin.rootUri }
      $pluginRoot = [System.IO.Path]::GetFullPath($pluginRoot)

      foreach ($gradleName in @('android\build.gradle','android\build.gradle.kts')) {
        $gradlePath = Join-Path $pluginRoot $gradleName
        if (-not (Test-Path -LiteralPath $gradlePath)) { continue }

        $g = [System.IO.File]::ReadAllText($gradlePath)
        $before = $g

        # Java compatibility -> 17
        $g = $g.Replace('JavaVersion.VERSION_1_8','JavaVersion.VERSION_17')
        $g = $g.Replace('JavaVersion.VERSION_11','JavaVersion.VERSION_17')

        # Kotlin compatibility -> 17, covering both old and new DSL forms.
        $g = $g.Replace("jvmTarget = '1.8'", "jvmTarget = '17'")
        $g = $g.Replace('jvmTarget = "1.8"', 'jvmTarget = "17"')
        $g = $g.Replace("jvmTarget = '11'", "jvmTarget = '17'")
        $g = $g.Replace('jvmTarget = "11"', 'jvmTarget = "17"')
        $g = $g.Replace('JvmTarget.JVM_1_8', 'JvmTarget.JVM_17')
        $g = $g.Replace('JvmTarget.JVM_11', 'JvmTarget.JVM_17')

        # If a kotlinOptions block exists but no jvmTarget is set, inject it.
        if ($g -match 'kotlinOptions\s*\{' -and $g -notmatch 'jvmTarget\s*=') {
          $g = [regex]::Replace(
            $g,
            'kotlinOptions\s*\{',
            "kotlinOptions {`r`n        jvmTarget = `"17`"",
            1
          )
        }

        # If compileOptions exists but no explicit 17 values are present, normalize.
        if ($g -match 'compileOptions\s*\{') {
          $g = [regex]::Replace($g, 'sourceCompatibility\s*=\s*JavaVersion\.VERSION_[A-Z0-9_]+', 'sourceCompatibility = JavaVersion.VERSION_17')
          $g = [regex]::Replace($g, 'targetCompatibility\s*=\s*JavaVersion\.VERSION_[A-Z0-9_]+', 'targetCompatibility = JavaVersion.VERSION_17')
        }

        if ($g -ne $before) {
          [System.IO.File]::WriteAllText($gradlePath, $g, $utf8)
        }
      }
    }
  } catch {
    Write-Host "JVM17 plugin patch uyarisi: $($_.Exception.Message)"
  }
}

# Force app Java/Kotlin toolchain to 17.
$androidDir = Join-Path $mobileDir 'android'
foreach ($appGradle in @(
  (Join-Path $androidDir 'app\build.gradle.kts'),
  (Join-Path $androidDir 'app\build.gradle')
)) {
  if (-not (Test-Path -LiteralPath $appGradle)) { continue }
  $g = [System.IO.File]::ReadAllText($appGradle)
  $before = $g
  $g = $g.Replace('JavaVersion.VERSION_1_8','JavaVersion.VERSION_17')
  $g = $g.Replace('JavaVersion.VERSION_11','JavaVersion.VERSION_17')
  $g = $g.Replace("jvmTarget = '1.8'", "jvmTarget = '17'")
  $g = $g.Replace('jvmTarget = "1.8"', 'jvmTarget = "17"')
  $g = $g.Replace("jvmTarget = '11'", "jvmTarget = '17'")
  $g = $g.Replace('jvmTarget = "11"', 'jvmTarget = "17"')
  if ($g -ne $before) { [System.IO.File]::WriteAllText($appGradle, $g, $utf8) }
}

# Also harden Gradle properties.
$gradleProps = Join-Path $androidDir 'gradle.properties'
$props = if (Test-Path -LiteralPath $gradleProps) { [System.IO.File]::ReadAllText($gradleProps) } else { '' }
if ($props -notmatch '(?m)^org\.gradle\.warning\.mode=') { $props += "`r`norg.gradle.warning.mode=none`r`n" }
[System.IO.File]::WriteAllText($gradleProps, $props, $utf8)


# OKEYX_V1122_STABLE_GRADLE
# The previous release daemon crashed after hours of reuse with an 8 GiB heap.
# Keep the release builder conservative and reproducible on a 16 GiB Windows PC.
$androidDir = Join-Path $mobileDir 'android'
$gradleProps = Join-Path $androidDir 'gradle.properties'
$props = if (Test-Path -LiteralPath $gradleProps) {
  [System.IO.File]::ReadAllText($gradleProps)
} else {
  ''
}

function Set-GradleProp([string]$text, [string]$name, [string]$value) {
  $escaped = [regex]::Escape($name)
  if ($text -match "(?m)^$escaped=") {
    return [regex]::Replace($text, "(?m)^$escaped=.*$", "$name=$value")
  }
  return ($text.TrimEnd() + "`r`n$name=$value`r`n")
}

$props = Set-GradleProp $props 'org.gradle.jvmargs' '-Xmx3072m -XX:MaxMetaspaceSize=1024m -XX:ReservedCodeCacheSize=256m -Dfile.encoding=UTF-8'
$props = Set-GradleProp $props 'org.gradle.daemon' 'false'
$props = Set-GradleProp $props 'org.gradle.workers.max' '2'
$props = Set-GradleProp $props 'org.gradle.parallel' 'false'
$props = Set-GradleProp $props 'org.gradle.configureondemand' 'false'
$props = Set-GradleProp $props 'kotlin.compiler.execution.strategy' 'in-process'
$props = Set-GradleProp $props 'org.gradle.warning.mode' 'none'

[System.IO.File]::WriteAllText(
  $gradleProps,
  $props,
  (New-Object System.Text.UTF8Encoding($false))
)


# OKEYX_V1123_RELEASE_RUNTIME_SAFE
# Keep RC release builds runtime-safe while AndroidX/WorkManager is stabilized:
# disable code/resource shrinking so reflection-generated AndroidX classes are
# not rewritten/removed in the APK used for device testing.
$androidDir = Join-Path $mobileDir 'android'
$appKts = Join-Path $androidDir 'app\build.gradle.kts'
$appGroovy = Join-Path $androidDir 'app\build.gradle'
$utf8 = New-Object System.Text.UTF8Encoding($false)

if (Test-Path -LiteralPath $appKts) {
  $g = [System.IO.File]::ReadAllText($appKts)
  if ($g -match 'getByName\("release"\)\s*\{') {
    $g = [regex]::Replace(
      $g,
      '(getByName\("release"\)\s*\{)',
      '$1' + "`r`n            isMinifyEnabled = false`r`n            isShrinkResources = false",
      1
    )
  } elseif ($g -match 'release\s*\{') {
    $g = [regex]::Replace(
      $g,
      '(release\s*\{)',
      '$1' + "`r`n            isMinifyEnabled = false`r`n            isShrinkResources = false",
      1
    )
  }
  [System.IO.File]::WriteAllText($appKts, $g, $utf8)
}
elseif (Test-Path -LiteralPath $appGroovy) {
  $g = [System.IO.File]::ReadAllText($appGroovy)
  if ($g -match 'release\s*\{') {
    $g = [regex]::Replace(
      $g,
      '(release\s*\{)',
      '$1' + "`r`n            minifyEnabled false`r`n            shrinkResources false",
      1
    )
  }
  [System.IO.File]::WriteAllText($appGroovy, $g, $utf8)
}


# OKEYX_V1207_NATIVE_SHARE
# share_plus was removed because the newest plugin's Built-in Kotlin sources can
# fail to compile on generated Flutter Android shells. OkeyX only needs one
# simple Android share action, so keep it native and dependency-free.
$shareXmlDir = Join-Path $resDir 'xml'
if (-not (Test-Path -LiteralPath $shareXmlDir)) { New-Item -ItemType Directory -Path $shareXmlDir -Force | Out-Null }
$sharePaths = Join-Path $shareXmlDir 'okeyx_share_paths.xml'
$sharePathsContent = @'
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <cache-path name="okeyx_cache" path="." />
</paths>
'@
[System.IO.File]::WriteAllText($sharePaths, $sharePathsContent, $utf8)

# FileProvider lets ACTION_SEND expose the generated result PNG safely.
$xml = [System.IO.File]::ReadAllText($ManifestPath)
if ($xml -notmatch 'OKEYX_NATIVE_SHARE_FILE_PROVIDER') {
  $shareProvider = @'
        <!-- OKEYX_NATIVE_SHARE_FILE_PROVIDER -->
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/okeyx_share_paths" />
        </provider>
'@
  $xml = $xml.Replace('    </application>', "$shareProvider    </application>")
  [System.IO.File]::WriteAllText($ManifestPath, $xml, $utf8)
}

# Patch the generated MainActivity with a tiny MethodChannel. This is applied
# after `flutter create`, so a clean checkout and an existing Android shell both
# get the same implementation.
$androidSrcMain = Split-Path -Parent $ManifestPath
$kotlinRoot = Join-Path $androidSrcMain 'kotlin'
$mainActivity = Get-ChildItem -LiteralPath $kotlinRoot -Filter 'MainActivity.kt' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $mainActivity) {
  $mainActivityContent = @'
package com.senshilabs.okeyx_mobile

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val shareChannel = "com.senshilabs.okeyx_mobile/share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannel).setMethodCallHandler { call, result ->
            if (call.method != "shareImage") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("missing_path", "Paylaşılacak dosya yolu boş.", null)
                    return@setMethodCallHandler
                }
                val file = File(path)
                if (!file.exists()) {
                    result.error("missing_file", "Paylaşım görseli bulunamadı.", null)
                    return@setMethodCallHandler
                }
                val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
                val sendIntent = Intent(Intent.ACTION_SEND).apply {
                    type = "image/png"
                    putExtra(Intent.EXTRA_STREAM, uri)
                    putExtra(Intent.EXTRA_TEXT, call.argument<String>("text") ?: "OkeyX 101")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                val chooserTitle = call.argument<String>("chooserTitle") ?: "OkeyX ile paylaş"
                startActivity(Intent.createChooser(sendIntent, chooserTitle))
                result.success(true)
            } catch (e: Exception) {
                result.error("share_failed", e.message ?: "Paylaşım başlatılamadı.", null)
            }
        }
    }
}
'@
  [System.IO.File]::WriteAllText($mainActivity.FullName, $mainActivityContent, $utf8)
} else {
  throw 'MainActivity.kt bulunamadi; OkeyX native paylaşım kanalı kurulamadı.'
}
