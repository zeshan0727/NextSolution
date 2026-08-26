# PhoneAura

PhoneAura is a RootHide-compatible visual redesign for Apple's stock Phone app on iOS 16.

## Version 0.1 features

- Floating glass tab dock for Favorites, Recents, Contacts, Keypad and Voicemail
- Dynamic Ocean, Aurora, Emerald and Sunset atmospheres
- Redesigned translucent list cards, navigation bars, search bars and keypad buttons
- Spring animations and optional haptic feedback
- Built-in quick settings by long-pressing the floating dock
- Full Settings preference pane with live Darwin notifications
- Stock Phone controllers and call handling remain intact underneath the theme

## Compatibility

- Target device: iPhone 14 Pro Max
- Target firmware: iOS 16.0
- Target jailbreak/bootstrap: RootHide
- Process filter: `com.apple.mobilephone`

## Build

Use RootHide's Theos fork:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/roothide/theos/master/bin/install-theos)"
export THEOS="$HOME/theos"
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

The package will be created under `packages/`.

A GitHub Actions workflow is included. Push the project to GitHub and run **Build PhoneAura** from the Actions tab. Download the `PhoneAura-RootHide` artifact and install the `.deb` using Sileo or Filza.

## Usage

1. Install the package.
2. Force-close and reopen Phone.
3. Long-press the floating dock to open quick settings.
4. Additional controls are available in Settings → PhoneAura.

## Safety

This first release changes presentation only. It intentionally does not hook telephony, call routing, call history databases, contacts databases or voicemail services.
