## Menu Bar 2FA

A lightweight macOS menu bar app that generates time-based one-time passwords (TOTP) and copies them to the clipboard. Multiple 2FA accounts are supported, with their secrets stored securely in the macOS Keychain.

## Managing accounts

Click the menu bar lock icon to see configured accounts. Open an account's submenu to copy its current token, edit its name or secret, remove it, or change its position with **Move Up** and **Move Down**. The first account cannot move up, and the last account cannot move down. Account order is saved securely and restored when the app launches. Select **Add Account…** to configure another account. Each account can have a descriptive name, such as `GitHub – alice@example.com`.

The app accepts Base32 secrets extracted from an `otpauth://` URL. For example:

```
otpauth://totp/Example:alice@google.com?secret=JBSWY3DPEHPK3PXP&issuer=Example
```

In this example, the Base32 secret is `JBSWY3DPEHPK3PXP`. QR-code scanning and automatic `otpauth://` URL parsing are not currently supported.

Existing installations are migrated automatically: a previously saved single secret is imported as an account named **Default** the first time the updated app launches.

## Download

The compiled version of this app can be downloaded from the [releases page](https://github.com/scottmangiapane/menu-bar-2fa/releases). Version 1.0.1 and later is a universal binary that runs natively on Apple Silicon and Intel Macs (no Rosetta required) and requires macOS 12 or later.

It is not notarized (the Apple Developer Program is expensive), so macOS may require allowing execution in **System Settings > Privacy & Security**. To start the app automatically at login, add it under **System Settings > General > Login Items**.
