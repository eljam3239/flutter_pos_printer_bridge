# flutter_pos_printer_bridge

Flutter wrapper for Star Micronics, Epson and Zebra POS printers. 

For those looking to use Flutter for POS receipt printinig with a specific printer company, see my other work:
1. [Flutter Star](https://github.com/eljam3239/flutter_star)
2. [Flutter Epson](https://github.com/eljam3239/flutter_epson)

Installation and dependency instructions can be found in the above pages. Those projects are basically proof of concept Flutter wrappers for the iOS and Android SDKs of those companies, following [federated plugin architecture](https://docs.flutter.dev/packages-and-plugins/developing-packages#federated-plugins). This project aims to bundle such wrappers into a single point, with a single set of dependencies and build files.

## Tested Devices

STAR MICRONICS

| Device      | TSP100iv | TSP100ivsk | mPop | mC-Label2 | TSP100iii | mC_Print3 (MCP31LB) |
|-------------|--------|----------|------|-----------|---------|--------|
| iOS         |   LAN     | LAN, Bluetooth         | Bluetooth     | LAN, Bluetooth, usb-C | LAN | LAN, Bluetooth, usb-a-usb-c |
| Android     |  LAN      |  LAN, Bluetooth, usb-a        |  Bluetooth , usb-b   | LAN, Bluetooth, usb-C | LAN | LAN, Bluetooth, usb-b |

Exceptions (also seen in Star Quick Setup Utility App):
+ After connecting the mC-Label2 or mC_Print3 printers to an iPad over USB, users must remove the USB cable from the iPad, reconnect to the printer in the iPad settings, then rediscover printers in the app to find, conenct to or print from that printer over Bluetooth. 
+ After connecting the TSP100ivsk to an Android tablet over USB, Bluetooth discovery/connection/printing works straight from the app.
+ After connecting the mPop to an Android tablet over Bluetooth, a powercycle must be performed to discover/connect/print to the mPop over USB
+ After connecting the mPop to an Android tablet over USB, a powercucle must be performed to connect/print to the mPop over USB, even though the Bluetooth interface for the mPop might be discoverable. 
+ As described in the [mC-Label2 online manual](https://star-m.jp/products/s_print/oml/mclabel2/manual/en/installing/connectingUSBCable.htm#step2), although USB discovery will work on Android after a bluetooth connection/print, the USB connection will timeout in the app. To connect to and print from the mC-Label2 using an Android tablet connected via USB, turn the printer off, connect the printer to the tablet via USB, then turn the printer power on. USB discovery/connection/printing will work now from Android. 


Epson 

| Device      | TM-m30III | Cash Drawer |
|-------------|--------|--------|
| iOS         |   LAN, Bluetooth (pre-connected, in-app pairing), usb     | yes |
| Android     |  LAN, Bluetooth (pre-connected), usb   | yes |

Zebra (in progress)

| Device | |
|--------|- |
| iOS    | |
| Android| |

## Contributing
Contributions are appreciated and encouraged! I'll be prioritizing keeping the Flutter-facing API intact. The core loop of discovering, connecting to and printing from receipt printers from the same Flutter app is the core objective of this package.
Criticism is also appreciated. If you have feedback or advice about how to better handle the build system, implementation or documentation, please take a run at it yourself or ask me to. Thanks!
