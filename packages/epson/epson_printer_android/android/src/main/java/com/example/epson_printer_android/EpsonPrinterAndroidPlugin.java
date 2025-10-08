package com.example.epson_printer_android;

import android.app.Activity;
import android.content.Context;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import androidx.annotation.NonNull;
import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

// Epson SDK imports
import com.epson.epos2.Epos2Exception;
import com.epson.epos2.discovery.DeviceInfo;
import com.epson.epos2.discovery.Discovery;
import com.epson.epos2.discovery.DiscoveryListener;
import com.epson.epos2.discovery.FilterOption;
import com.epson.epos2.printer.Printer;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

/** EpsonPrinterAndroidPlugin */
public class EpsonPrinterAndroidPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
  private MethodChannel channel;
  private Context context;
  private Activity activity;

  // Connection state
  private Printer mPrinter;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "epson_printer");
    channel.setMethodCallHandler(this);
    context = flutterPluginBinding.getApplicationContext();
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "discoverPrinters":
        discoverLanPrinters(result);
        break;
      case "discoverBluetoothPrinters":
        discoverBluetoothPrinters(result);
        break;
      case "discoverUsbPrinters":
        discoverUsbPrinters(result);
        break;
      case "pairBluetoothDevice":
        pairBluetoothDevice(result);
        break;
      case "connect":
        connectPrinter(call, result);
        break;
      case "disconnect":
        disconnectPrinter(result);
        break;
      case "printReceipt":
        printReceipt(call, result);
        break;
      case "getStatus":
        // Minimal status until full mapping is implemented
        java.util.Map<String, Object> status = new java.util.HashMap<>();
        status.put("isOnline", mPrinter != null);
        status.put("status", mPrinter != null ? "connected" : "disconnected");
        result.success(status);
        break;
      case "openCashDrawer":
        openCashDrawer(result);
        break;
      case "isConnected":
        result.success(mPrinter != null);
        break;
      default:
        result.notImplemented();
    }
  }

  private void discoverLanPrinters(@NonNull Result result) {
    final List<String> found = new ArrayList<>();
    final FilterOption filter = new FilterOption();
    filter.setDeviceType(Discovery.TYPE_PRINTER);
    filter.setPortType(Discovery.PORTTYPE_TCP);
    filter.setEpsonFilter(Discovery.FILTER_NAME);

    final DiscoveryListener listener = new DiscoveryListener() {
      @Override
      public void onDiscovery(final DeviceInfo deviceInfo) {
        synchronized (found) {
          String target = deviceInfo.getTarget();
          String ip = deviceInfo.getIpAddress();
          String name = deviceInfo.getDeviceName();
          String prefixTarget;
          if (target != null && target.startsWith("TCP:")) {
            prefixTarget = target;
          } else if (ip != null && !ip.isEmpty()) {
            prefixTarget = "TCP:" + ip;
          } else if (target != null && !target.isEmpty()) {
            prefixTarget = target.startsWith("TCP:") ? target : ("TCP:" + target);
          } else {
            return;
          }
          String entry = prefixTarget + ":" + (name != null ? name : "Printer");
          if (!found.contains(entry)) {
            found.add(entry);
          }
        }
      }
    };

    try {
      Discovery.start(context, filter, listener);
    } catch (Exception e) {
      result.success(Collections.emptyList());
      return;
    }

    // Stop after a short window and return results
    new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
      while (true) {
        try {
          Discovery.stop();
          break;
        } catch (Epos2Exception e) {
          if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) {
            break;
          }
        }
      }
      synchronized (found) {
        result.success(new ArrayList<>(found));
      }
    }, 5000);
  }

  // Bluetooth discovery (Classic only) + include bonded devices to handle Settings-paired printers
  private void discoverBluetoothPrinters(@NonNull Result result) {
    final List<String> found = new ArrayList<>();

    // 1) Seed with bonded devices
    for (String entry : getBondedBtPrinters()) {
      if (!found.contains(entry)) found.add(entry);
    }

    // 2) Active discovery via Epson SDK (may find additional devices)
    final FilterOption filter = new FilterOption();
    filter.setDeviceType(Discovery.TYPE_PRINTER);
    filter.setPortType(Discovery.PORTTYPE_BLUETOOTH);
    filter.setEpsonFilter(Discovery.FILTER_NAME);

    final DiscoveryListener listener = new DiscoveryListener() {
      @Override
      public void onDiscovery(final DeviceInfo deviceInfo) {
        synchronized (found) {
          String target = deviceInfo.getTarget();
          String name = deviceInfo.getDeviceName();
          String btAddr = deviceInfo.getBdAddress();
          String prefixTarget = null;

          if (target != null && target.startsWith("BT:")) {
            prefixTarget = target;
          } else if (btAddr != null && !btAddr.isEmpty()) {
            prefixTarget = "BT:" + btAddr;
          } else if (target != null && !target.isEmpty()) {
            prefixTarget = target.startsWith("BT:") ? target : ("BT:" + target);
          }

          if (prefixTarget == null) return;

          String entry = prefixTarget + ":" + (name != null ? name : "Printer");
          if (!found.contains(entry)) {
            found.add(entry);
          }
        }
      }
    };

    try {
      Discovery.start(context, filter, listener);
    } catch (Exception e) {
      // If discovery fails (permissions, BT off), still return bonded list
      result.success(new ArrayList<>(found));
      return;
    }

    new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
      while (true) {
        try {
          Discovery.stop();
          break;
        } catch (Epos2Exception e) {
          if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) {
            break;
          }
        }
      }
      synchronized (found) {
        result.success(new ArrayList<>(found));
      }
    }, 4000);
  }

  // Return bonded devices formatted as BT:MAC:Name (filter to likely Epson names)
  private List<String> getBondedBtPrinters() {
    List<String> result = new ArrayList<>();
    try {
      BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
      if (adapter == null) return result;
      Set<BluetoothDevice> bonded = adapter.getBondedDevices();
      if (bonded == null) return result;
      for (BluetoothDevice d : bonded) {
        String name = d.getName();
        String mac = d.getAddress();
        if (mac == null || mac.isEmpty()) continue;
        // Heuristic: Epson names often contain "TM" or "EPSON"
        if (name == null || name.isEmpty() ||
            !(name.toUpperCase().contains("TM") || name.toUpperCase().contains("EPSON"))) {
          // Still include; user may rename device
        }
        String entry = "BT:" + mac + ":" + (name != null ? name : "Printer");
        if (!result.contains(entry)) result.add(entry);
      }
    } catch (Throwable t) {
      // ignore and return what we have
    }
    return result;
  }

  private void connectPrinter(@NonNull MethodCall call, @NonNull Result result) {
    try {
      @SuppressWarnings("unchecked")
      Map<String, Object> args = (Map<String, Object>) call.arguments;
      if (args == null) {
        result.error("INVALID_ARGS", "Missing connection settings", null);
        return;
      }

      // Determine target
      String target = (String) args.get("targetString");
      if (target == null || target.isEmpty()) {
        String identifier = (String) args.get("identifier");
        Number portTypeNum = (Number) args.get("portType");
        int portType = portTypeNum != null ? portTypeNum.intValue() : 1; // default tcp
        String prefix;
        switch (portType) {
          case 1: prefix = "TCP:"; break; // tcp
          case 2: prefix = "BT:"; break;  // bluetooth classic
          case 3: prefix = "USB:"; break; // usb
          case 4: prefix = "BLE:"; break; // ble (not used here)
          default: prefix = "TCP:"; break;
        }
        target = (identifier != null && (identifier.startsWith("TCP:") || identifier.startsWith("BT:") || identifier.startsWith("BLE:") || identifier.startsWith("USB:")))
            ? identifier
            : (prefix + identifier);
      }

      // Support TCP, Bluetooth (Classic), and USB
      if (!(target.startsWith("TCP:") || target.startsWith("BT:") || target.startsWith("USB:"))) {
        result.error("UNSUPPORTED", "Only TCP/BT/USB connection is supported on Android right now", null);
        return;
      }

      // If attempting BT while an Epson USB device is attached, return a clear error
      if (target.startsWith("BT:") && isEpsonUsbAttached()) {
        result.error("USB_ATTACHED", "USB connection detected. Unplug USB to use Bluetooth.", null);
        return;
      }

      // Timeout from args (ms), default 15000
      int timeout = 15000;
      Object tObj = args.get("timeout");
      if (tObj instanceof Number) {
        timeout = ((Number) tObj).intValue();
      } else if (tObj != null) {
        try { timeout = Integer.parseInt(String.valueOf(tObj)); } catch (Exception ignored) {}
      }
      if (timeout <= 0) timeout = 15000;

      // Disconnect any existing connection
      safeDisposePrinter();

      // Map series/lang (fallback to TM_M30III + ANK if not provided)
      int seriesIdx = getInt(args.get("printerSeries"), 29);
      int langIdx = getInt(args.get("modelLang"), 0);
      int seriesConst = mapSeries(seriesIdx);
      int langConst = mapLang(langIdx);

      mPrinter = new Printer(seriesConst, langConst, context);

      // Connect with explicit timeout
      mPrinter.connect(target, timeout);

      result.success(null);
    } catch (Epos2Exception e) {
      safeDisposePrinter();
      result.error("CONNECT_FAILED", "Epson SDK error: " + e.getMessage(), e.getErrorStatus());
    } catch (Exception ex) {
      safeDisposePrinter();
      result.error("CONNECT_FAILED", ex.getMessage(), null);
    }
  }

  private boolean isEpsonUsbAttached() {
    try {
      UsbManager usbManager = (UsbManager) context.getSystemService(Context.USB_SERVICE);
      if (usbManager == null) return false;
      Map<String, UsbDevice> devices = usbManager.getDeviceList();
      if (devices == null || devices.isEmpty()) return false;
      for (UsbDevice dev : devices.values()) {
        // Epson Vendor ID
        if (dev.getVendorId() == 0x04B8) return true;
        // Or any interface that presents as Printer class
        int ifaceCount = dev.getInterfaceCount();
        for (int i = 0; i < ifaceCount; i++) {
          UsbInterface iface = dev.getInterface(i);
          if (iface != null && iface.getInterfaceClass() == android.hardware.usb.UsbConstants.USB_CLASS_PRINTER) {
            return true;
          }
        }
      }
    } catch (Throwable ignored) {}
    return false;
  }

  private void disconnectPrinter(@NonNull Result result) {
    try {
      if (mPrinter != null) {
        try { mPrinter.disconnect(); } catch (Exception ignored) {}
        try { mPrinter.clearCommandBuffer(); } catch (Exception ignored) {}
        try { mPrinter.setReceiveEventListener(null); } catch (Exception ignored) {}
      }
      mPrinter = null;
      result.success(null);
    } catch (Exception e) {
      mPrinter = null;
      result.success(null);
    }
  }

  // Build commands and send print job
  private void printReceipt(@NonNull MethodCall call, @NonNull Result result) {
    if (mPrinter == null) {
      result.error("NOT_CONNECTED", "Printer is not connected", null);
      return;
    }

    @SuppressWarnings("unchecked")
    Map<String, Object> args = (Map<String, Object>) call.arguments;
    if (args == null) {
      result.error("INVALID_ARGS", "Missing print job", null);
      return;
    }

    @SuppressWarnings("unchecked")
    List<Object> commands = (List<Object>) args.get("commands");
    if (commands == null) {
      result.error("INVALID_ARGS", "Missing commands", null);
      return;
    }

    // Run on a background thread to avoid blocking the platform channel
    new Thread(() -> {
      try {
        synchronized (EpsonPrinterAndroidPlugin.this) {
          mPrinter.clearCommandBuffer();

          for (Object item : commands) {
            if (!(item instanceof Map)) continue;
            @SuppressWarnings("unchecked")
            Map<String, Object> cmd = (Map<String, Object>) item;
            String type = String.valueOf(cmd.get("type"));
            @SuppressWarnings("unchecked")
            Map<String, Object> params = (Map<String, Object>) cmd.get("parameters");
            if (params == null) params = new HashMap<>();

            switch (type) {
              case "text":
              case "addText": {
                String data = String.valueOf(params.getOrDefault("data", ""));
                if (data != null) {
                  mPrinter.addText(data);
                }
                break;
              }
              case "image": {
                // Parameters: imagePath plus optional width & flags
                String imagePath = (String) params.get("imagePath");
                boolean debug = false; // debug markers suppressed unless explicitly enabled in params
                try { Object dbg = params.get("debug"); if (dbg != null) debug = Boolean.parseBoolean(String.valueOf(dbg)); } catch (Exception ignored) {}
                boolean advancedProcessing = false;
                try { Object ap = params.get("advancedProcessing"); if (ap != null) advancedProcessing = Boolean.parseBoolean(String.valueOf(ap)); } catch (Exception ignored) {}
                String align = null; try { Object al = params.get("align"); if (al != null) align = String.valueOf(al); } catch (Exception ignored) {}
                if (imagePath != null && !imagePath.isEmpty()) {
                  Bitmap bmp = BitmapFactory.decodeFile(imagePath);
                  if (bmp != null) {
                    int origW = bmp.getWidth();
                    int origH = bmp.getHeight();
                    int targetW = getInt(params.get("targetWidth"), origW);
                    int printerWidth = getInt(params.get("printerWidth"), 0);
                    if (targetW > 0 && targetW < origW) {
                      try {
                        float ratio = (float) targetW / (float) origW;
                        bmp = Bitmap.createScaledBitmap(bmp, targetW, Math.max(1,(int)(origH*ratio)), true);
                      } catch (Throwable ignored) {}
                    }
                    int width = bmp.getWidth();
                    int height = bmp.getHeight();
                    boolean centerRequest = align != null && align.equalsIgnoreCase("center");
                    if (debug) { try { mPrinter.addText("[IMG_START w="+width+" h="+height+"]\n"); } catch (Exception ignored) {} }
                    if (centerRequest) { try { mPrinter.addTextAlign(Printer.ALIGN_CENTER); } catch (Exception ignored) {} }
                    int color = Printer.PARAM_DEFAULT;
                    int mode = Printer.MODE_MONO;
                    int halftone = Printer.HALFTONE_DITHER;
                    double brightness = 1.0;
                    int compress = Printer.COMPRESS_AUTO;
                    // Advanced processing: optional threshold + histogram (lightweight)
                    if (advancedProcessing) {
                      int bwThreshold = -1; try { Object th = params.get("bwThreshold"); if (th != null) bwThreshold = Integer.parseInt(String.valueOf(th)); } catch (Exception ignored) {}
                      if (bwThreshold >= 0 && bwThreshold <= 255) {
                        try {
                          Bitmap mutable = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
                          int[] pixels = new int[width*height]; bmp.getPixels(pixels,0,width,0,0,width,height);
                          int blacks=0; for(int i=0;i<pixels.length;i++){int c=pixels[i];int r=(c>>16)&0xFF,g=(c>>8)&0xFF,b=c&0xFF;int lum=(r*30+g*59+b*11)/100;boolean isB=lum<bwThreshold; if(isB) blacks++; pixels[i]= isB?0xFF000000:0xFFFFFFFF;}
                          double ratio = (double)blacks/(double)pixels.length; boolean collapsed = ratio>0.98||ratio<0.02; if(!collapsed){mutable.setPixels(pixels,0,width,0,0,width,height); bmp=mutable; if(debug){try{mPrinter.addText("[IMG_THRESH "+String.format("%.2f",ratio)+"]\n");}catch(Exception ignored){}}}
                        } catch (Throwable ignored) {}
                      }
                    }
                    try {
                      mPrinter.addImage(bmp, 0, 0, width, height, color, mode, halftone, brightness, compress);
                    } catch (Epos2Exception eImg) {
                      if (advancedProcessing) {
                        // Fallback: scale to 384 then retry once
                        try {
                          int fallbackW = Math.min(384,width);
                          if (fallbackW < width) {
                            float r = (float)fallbackW/width; Bitmap scaled = Bitmap.createScaledBitmap(bmp, fallbackW, Math.max(1,(int)(height*r)), true);
                            mPrinter.addImage(scaled,0,0,scaled.getWidth(), scaled.getHeight(), color, mode, halftone, brightness, compress);
                          }
                        } catch (Exception ignored) {}
                      }
                    }
                    if (centerRequest) { try { mPrinter.addTextAlign(Printer.ALIGN_LEFT); } catch (Exception ignored) {} }
                    if (debug) { try { mPrinter.addText("[IMG_END w="+width+" h="+height+"]\n"); } catch (Exception ignored) {} }
                  } else if (debug) {
                    try { mPrinter.addText("[IMG_DECODE_FAILED]\n"); } catch (Exception ignored) {}
                  }
                }
                break;
              }
              case "feed": {
                int line = getInt(params.get("line"), getInt(params.get("lines"), 1));
                if (line < 1) line = 1;
                mPrinter.addFeedLine(line);
                break;
              }
              case "cut": {
                mPrinter.addCut(Printer.CUT_FEED);
                break;
              }
              // Additional commands (barcode/qrCode/image/pulse/beep/layout) can be added later
              default:
                // Ignore unknown commands for now
                break;
            }
          }

          // Send data
          mPrinter.sendData(Printer.PARAM_DEFAULT);
        }
        runOnMain(() -> result.success(null));
      } catch (Epos2Exception e) {
        runOnMain(() -> result.error("PRINT_FAILED", "Epson SDK error: " + e.getMessage(), e.getErrorStatus()));
      } catch (Exception ex) {
        runOnMain(() -> result.error("PRINT_FAILED", ex.getMessage(), null));
      }
    }).start();
  }

  // Pairing helper: prefer active Epson discovery result; fallback to bonded
  private void pairBluetoothDevice(@NonNull Result result) {
    final List<String> found = new ArrayList<>();

    final FilterOption filter = new FilterOption();
    filter.setDeviceType(Discovery.TYPE_PRINTER);
    filter.setPortType(Discovery.PORTTYPE_BLUETOOTH);
    filter.setEpsonFilter(Discovery.FILTER_NAME);

    final DiscoveryListener listener = new DiscoveryListener() {
      @Override
      public void onDiscovery(DeviceInfo deviceInfo) {
        String target = deviceInfo.getTarget();
        String name = deviceInfo.getDeviceName();
        String btAddr = deviceInfo.getBdAddress();
        String prefixTarget = null;
        if (target != null && target.startsWith("BT:")) {
          prefixTarget = target;
        } else if (btAddr != null && !btAddr.isEmpty()) {
          prefixTarget = "BT:" + btAddr;
        }
        if (prefixTarget == null) return;
        String entry = prefixTarget + ":" + (name != null ? name : "Printer");
        synchronized (found) {
          if (!found.contains(entry)) found.add(entry);
        }
      }
    };

    boolean started = false;
    try {
      Discovery.start(context, filter, listener);
      started = true;
    } catch (Exception e) {
      // ignore, will fallback
    }

    final boolean startedFinal = started;
    new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
      if (startedFinal) {
        while (true) {
          try {
            Discovery.stop();
            break;
          } catch (Epos2Exception e) {
            if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) {
              break;
            }
          }
        }
      }

      String cleaned = null;
      synchronized (found) {
        if (!found.isEmpty()) {
          String entry = found.get(0); // e.g., BT:AA:BB:CC:DD:EE:FF:TM-m30III
          int last = entry.lastIndexOf(":");
          if (last > 0) cleaned = entry.substring(0, last); // BT:AA:BB:CC:DD:EE:FF
        }
      }

      if (cleaned == null) {
        // Fallback to bonded list
        List<String> bonded = getBondedBtPrinters();
        if (!bonded.isEmpty()) {
          String entry = bonded.get(0); // e.g., BT:AA:BB:CC:DD:EE:FF:Name
          int last = entry.lastIndexOf(":");
          if (last > 0) cleaned = entry.substring(0, last); // BT:AA:BB:CC:DD:EE:FF
        }
      }

      Map<String, Object> payload = new HashMap<>();
      payload.put("target", cleaned);
      payload.put("resultCode", cleaned != null ? 0 : -1);
      result.success(payload);
    }, 3500);
  }

  // Discover USB printers using Epson Discovery
  private void discoverUsbPrinters(@NonNull Result result) {
    final List<String> found = new ArrayList<>();

    final FilterOption filter = new FilterOption();
    filter.setDeviceType(Discovery.TYPE_PRINTER);
    filter.setPortType(Discovery.PORTTYPE_USB);
    filter.setEpsonFilter(Discovery.FILTER_NAME);

    final DiscoveryListener listener = new DiscoveryListener() {
      @Override
      public void onDiscovery(final DeviceInfo deviceInfo) {
        synchronized (found) {
          String target = deviceInfo.getTarget();
          String name = deviceInfo.getDeviceName();
          if (target == null || target.isEmpty()) return;
          if (!target.startsWith("USB:")) target = "USB:" + target;
          String entry = target + ":" + (name != null ? name : "USB Printer");
          if (!found.contains(entry)) found.add(entry);
        }
      }
    };

    try {
      Discovery.start(context, filter, listener);
    } catch (Exception e) {
      result.success(Collections.emptyList());
      return;
    }

    new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
      while (true) {
        try {
          Discovery.stop();
          break;
        } catch (Epos2Exception e) {
          if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) {
            break;
          }
        }
      }
      synchronized (found) {
        result.success(new ArrayList<>(found));
      }
    }, 4000);
  }

  private void openCashDrawer(@NonNull Result result) {
    if (mPrinter == null) {
      result.error("NOT_CONNECTED", "Printer is not connected", null);
      return;
    }

    new Thread(() -> {
      Epos2Exception lastEpson = null;
      Exception lastEx = null;
      try {
        synchronized (EpsonPrinterAndroidPlugin.this) {
          // Try defined combinations: 2-pin/5-pin with 100ms then 200ms using SDK constants
          int[] drawers = new int[] { Printer.DRAWER_2PIN, Printer.DRAWER_5PIN };
          int[] pulses = new int[] { Printer.PULSE_100, Printer.PULSE_200 };
          boolean success = false;

          // First try Epson SDK addPulse
          for (int d : drawers) {
            for (int p : pulses) {
              try {
                mPrinter.clearCommandBuffer();
                mPrinter.addPulse(d, p);
                mPrinter.sendData(Printer.PARAM_DEFAULT);
                success = true;
                break;
              } catch (Epos2Exception ee) {
                lastEpson = ee;
              } catch (Exception ex) {
                lastEx = ex;
              }
            }
            if (success) break;
          }

          // Fallback: raw ESC/POS command (ESC p m t1 t2) if addPulse failed (some SDK builds validate and reject)
          if (!success) {
            // m: 0(pin2),1(pin5); t1/t2 are 2ms units
            int[] mVals = new int[] { 0, 1 };
            int[][] timings = new int[][] { {50, 50}, {100, 100} }; // 100ms/200ms
            for (int m : mVals) {
              for (int[] tt : timings) {
                try {
                  byte[] cmd = new byte[] { 0x1B, 0x70, (byte)m, (byte)tt[0], (byte)tt[1] };
                  mPrinter.clearCommandBuffer();
                  mPrinter.addCommand(cmd);
                  mPrinter.sendData(Printer.PARAM_DEFAULT);
                  success = true;
                  break;
                } catch (Epos2Exception ee) {
                  lastEpson = ee;
                } catch (Exception ex) {
                  lastEx = ex;
                }
              }
              if (success) break;
            }
          }

          if (!success) {
            if (lastEpson != null) throw lastEpson;
            if (lastEx != null) throw lastEx;
            throw new RuntimeException("Unknown drawer failure");
          }
        }
        runOnMain(() -> result.success(null));
      } catch (Epos2Exception e) {
        int code = e.getErrorStatus();
        String friendly = mapEposError(code);
        runOnMain(() -> result.error("DRAWER_FAILED", "Epson SDK error (" + friendly + "): " + e.getMessage(), code));
      } catch (Exception ex) {
        runOnMain(() -> result.error("DRAWER_FAILED", ex.getMessage(), null));
      }
    }).start();
  }

  private String mapEposError(int code) {
    switch (code) {
      case 1: return "ERR_PARAM";
      case 2: return "ERR_ILLEGAL";
      case 3: return "ERR_MEMORY";
      case 4: return "ERR_PROCESSING";
      case 5: return "ERR_NOT_FOUND";
      case 6: return "ERR_SYSTEM";
      case 7: return "ERR_CONNECT";
      case 8: return "ERR_TIMEOUT";
      case 9: return "ERR_IN_USE";
      case 10: return "ERR_TYPE_INVALID";
      case 11: return "ERR_DISCONNECT";
      default: return "ERR_" + code;
    }
  }

  private void safeDisposePrinter() {
    if (mPrinter != null) {
      try { mPrinter.disconnect(); } catch (Exception ignored) {}
      try { mPrinter.clearCommandBuffer(); } catch (Exception ignored) {}
      try { mPrinter.setReceiveEventListener(null); } catch (Exception ignored) {}
      mPrinter = null;
    }
  }

  private int getInt(Object obj, int def) {
    if (obj instanceof Number) return ((Number) obj).intValue();
    try { return Integer.parseInt(String.valueOf(obj)); } catch (Exception ignored) {}
    return def;
  }

  private void runOnMain(Runnable r) {
    new android.os.Handler(android.os.Looper.getMainLooper()).post(r);
  }

  // Map platform enum EpsonPrinterSeries -> Epson Android Printer series constant
  private int mapSeries(int idx) {
    switch (idx) {
      case 1:  return Printer.TM_M30;      // tmM30
      case 21: return Printer.TM_M30II;    // tmM30II
      case 29: return Printer.TM_M30III;   // tmM30III
      case 12: return Printer.TM_T88;      // tmT88 (generic)
      case 24: return Printer.TM_T88VII;   // tmT88VII
      case 15: return Printer.TM_U220;     // tmU220
      case 23: return Printer.TM_M50;      // tmM50
      case 30: return Printer.TM_M50II;    // tmM50II
      default: return Printer.TM_M30III;   // sensible default for modern models
    }
  }

  // Map platform enum EpsonModelLang -> Epson Android Printer language constant
  private int mapLang(int idx) {
    switch (idx) {
      case 0:  return Printer.MODEL_ANK;       // ank
      case 1:  return Printer.MODEL_JAPANESE;  // japanese
      case 2:  return Printer.MODEL_CHINESE;   // chinese
      case 3:  return Printer.MODEL_TAIWAN;    // taiwan
      case 4:  return Printer.MODEL_KOREAN;    // korean
      case 5:  return Printer.MODEL_THAI;      // thai
      case 6:  return Printer.MODEL_SOUTHASIA; // southasia
      default: return Printer.MODEL_ANK;
    }
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    channel.setMethodCallHandler(null);
    channel = null;
  }

  // ActivityAware implementations
  @Override
  public void onAttachedToActivity(ActivityPluginBinding binding) {
    this.activity = binding.getActivity();
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    this.activity = null;
  }

  @Override
  public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
    this.activity = binding.getActivity();
  }

  @Override
  public void onDetachedFromActivity() {
    this.activity = null;
  }
}
