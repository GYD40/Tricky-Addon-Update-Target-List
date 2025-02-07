MODPATH=${0%/*}
HIDE_DIR="/data/adb/modules/.TA_utl"
TS="/data/adb/modules/tricky_store"
SCRIPT_DIR="/data/adb/tricky_store"
TSPA="/data/adb/modules/tsupport-advance"

aapt() { "$MODPATH/common/aapt" "$@"; }

add_denylist_to_target() {
    exclamation_target=$(grep '!' "/data/adb/tricky_store/target.txt" | sed 's/!$//')
    question_target=$(grep '?' "/data/adb/tricky_store/target.txt" | sed 's/?$//')
    target=$(sed 's/[!?]$//' /data/adb/tricky_store/target.txt)
    denylist=$(magisk --denylist ls 2>/dev/null | awk -F'|' '{print $1}' | grep -v "isolated")
    
    printf "%s\n" "$target" "$denylist" | sort -u > "/data/adb/tricky_store/target.txt"

    for target in $exclamation_target; do
        sed -i "s/^$target$/$target!/" "/data/adb/tricky_store/target.txt"
    done

    for target in $question_target; do
        sed -i "s/^$target$/$target?/" "/data/adb/tricky_store/target.txt"
    done
}

# Reset verified Boot Hash
hash_value=$(grep -v '^#' "/data/adb/boot_hash" | tr -d '[:space:]')
if [ -n "$hash_value" ]; then
    resetprop -n ro.boot.vbmeta.digest "$hash_value"
fi

# Reset vendor patch if different with security patch
security_patch=$(getprop ro.build.version.security_patch)
vendor_patch=$(getprop ro.vendor.build.security_patch)
if [ "$vendor_patch" != "$security_patch" ]; then
    resetprop ro.vendor.build.security_patch "$security_patch"
fi

# Disable TSupport-A auto update target to prevent overwrite
if [ -d "$TSPA" ]; then
    touch "/storage/emulated/0/stop-tspa-auto-target"
elif [ ! -d "$TSPA" ] && [ -f "/storage/emulated/0/stop-tspa-auto-target" ]; then
    rm -f "/storage/emulated/0/stop-tspa-auto-target"
fi

# Magisk operation
if [ -f "$MODPATH/action.sh" ]; then
    # Hide module from Magisk manager
    if [ "$MODPATH" != "$HIDE_DIR" ]; then
        rm -rf "$HIDE_DIR"
        mv "$MODPATH" "$HIDE_DIR"
    fi
    MODPATH="$HIDE_DIR"
    
    # Add target from denylist
    # To trigger this, choose "Select from DenyList" in WebUI once
    [ -f "/data/adb/tricky_store/target_from_denylist" ] && add_denylist_to_target
else
    [ -d "$HIDE_DIR" ] && rm -rf "$HIDE_DIR"
fi

# Hide module from APatch, KernelSU, KSUWebUIStandalone, MMRL
rm -f "$MODPATH/module.prop"

# Symlink tricky store
if [ -f "$MODPATH/action.sh" ] && [ ! -f "$TS/action.sh" ] && [ ! -L "$TS/action.sh" ]; then
    ln -s "$MODPATH/action.sh" "$TS/action.sh"
fi
if [ ! -d "$TS/webroot" ] && [ ! -L "$TS/webroot" ]; then
    ln -s "$MODPATH/webui" "$TS/webroot"
fi

# Optimization
OUTPUT_APP="$MODPATH/common/tmp/applist"
OUTPUT_SKIP="$MODPATH/common/tmp/skiplist"

until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 1
done

# Create temporary directory
mkdir -p "$MODPATH/common/tmp"

# Additional system apps
SYSTEM_APP="com.google.android.gms|com.google.android.gsf|com.android.vending"

# Initialize cache files to save app list and skip list
echo "# This file is generated from service.sh to speed up load time" > "$OUTPUT_APP"
echo "# This file is generated from service.sh to speed up load time" > "$OUTPUT_SKIP"

# Get list of third party apps and specific system apps, then cache app name
# Check Xposed module
{ 
    pm list packages -3 2>/dev/null
    pm list package -s | grep -E "$SYSTEM_APP"
} | awk -F: '{print $2}' | while read -r PACKAGE; do
    # Get APK path for the package
    APK_PATH=$(pm path "$PACKAGE" 2>/dev/null | grep "base.apk" | awk -F: '{print $2}' | tr -d '\r')
    [ -z "$APK_PATH" ] && APK_PATH=$(pm path "$PACKAGE" 2>/dev/null | grep ".apk" | awk -F: '{print $2}' | tr -d '\r')

    if [ -n "$APK_PATH" ]; then
        # Extract app name and save package info
        APP_NAME=$(aapt dump badging "$APK_PATH" 2>/dev/null | grep "application-label:" | sed "s/application-label://g; s/'//g")
        echo "app-name: $APP_NAME, package-name: $PACKAGE" >> "$OUTPUT_APP"
    else
        echo "app-name: Unknown App package-name: $PACKAGE" >> "$OUTPUT_APP"
    fi

    # Check if app is Xposed module and add to skip list if not
    if ! aapt dump xmltree "$APK_PATH" AndroidManifest.xml 2>/dev/null | grep -qE "xposed.category|xposeddescription"; then
        echo "$PACKAGE" >> "$OUTPUT_SKIP"
    fi
done
