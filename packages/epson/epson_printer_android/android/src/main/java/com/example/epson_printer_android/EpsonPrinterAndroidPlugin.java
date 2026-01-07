package com.example.epson_printer_android;

import android.app.Activity;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;
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
import com.epson.epos2.printer.PrinterSettingListener;
import com.epson.epos2.printer.PrinterStatusInfo;
import com.epson.epos2.printer.ReceiveListener;

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

  // Discovery/state machine metadata (parity with iOS)
  private final Object stateLock = new Object();
  private String discoveryState = "idle"; // idle | discoveringLan | discoveringBluetooth | discoveringUsb | cleaningUp | suspendedAfterUsbDisconnect
  private int discoverySessionId = 0;
  private boolean usbWasConnectedThisSession = false;
  private boolean pendingWorkQueued = false;
  private long suspendedUntilMs = 0L;
  private Handler mainHandler;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
    channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "epson_printer");
    channel.setMethodCallHandler(this);
    context = flutterPluginBinding.getApplicationContext();
    mainHandler = new Handler(Looper.getMainLooper());
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    switch (call.method) {
      case "discoverPrinters":
        if (isSuspended()) { result.success(java.util.Collections.emptyList()); } else { discoverLanPrinters(result); }
        break;
      case "discoverBluetoothPrinters":
        if (isSuspended()) { result.success(java.util.Collections.emptyList()); } else { discoverBluetoothPrinters(result); }
        break;
      case "discoverUsbPrinters":
        if (isSuspended()) { result.success(java.util.Collections.emptyList()); } else { discoverUsbPrinters(result); }
        break;
      case "discoverAllPrinters":
        if (isSuspended()) {
          result.success(java.util.Collections.emptyList());
        } else {
          discoverAllPrinters(result);
        }
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
      case "getDiscoveryState": {
        java.util.Map<String, Object> st = new java.util.HashMap<>();
        synchronized (stateLock) {
          st.put("state", discoveryState);
          st.put("sessionId", discoverySessionId);
          st.put("usbWasConnectedThisSession", usbWasConnectedThisSession);
          st.put("pendingWorkQueued", pendingWorkQueued);
        }
        result.success(st);
        break;
      }
      case "abortDiscovery": {
        abortDiscovery(result);
        break;
      }
      case "detectPaperWidth": {
        detectPaperWidth(result);
        break;
      }
      default:
        result.notImplemented();
    }
  }

  // --- State helpers ---
  private void setState(String s) {
    synchronized (stateLock) {
      discoveryState = s;
    }
  }

  private boolean isSuspended() {
    synchronized (stateLock) {
      long now = System.currentTimeMillis();
      if ("cleaningUp".equals(discoveryState)) return true;
      if ("suspendedAfterUsbDisconnect".equals(discoveryState) && now < suspendedUntilMs) return true;
      if (now < suspendedUntilMs) return true;
    }
    return false;
  }

  private void suspendShort(long millis) {
    synchronized (stateLock) {
      discoveryState = "suspendedAfterUsbDisconnect";
      suspendedUntilMs = System.currentTimeMillis() + Math.max(0, millis);
    }
    mainHandler.postDelayed(() -> {
      synchronized (stateLock) {
        if (System.currentTimeMillis() >= suspendedUntilMs && "suspendedAfterUsbDisconnect".equals(discoveryState)) {
          discoveryState = "idle";
        }
      }
    }, Math.max(0, millis) + 50);
  }

  private void cleanupDiscoveryAsync(@NonNull Runnable onDone) {
    setState("cleaningUp");
    new Thread(() -> {
      for (int i = 0; i < 20; i++) {
        try {
          Discovery.stop();
          break;
        } catch (Epos2Exception e) {
          if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) {
            break;
          }
          try { Thread.sleep(100); } catch (InterruptedException ignored) {}
        } catch (Throwable t) {
          break;
        }
      }
      try { Thread.sleep(100); } catch (InterruptedException ignored) {}
      mainHandler.post(() -> {
        setState("idle");
        onDone.run();
      });
    }).start();
  }

  private void abortDiscovery(@NonNull Result result) {
    cleanupDiscoveryAsync(() -> {
      synchronized (stateLock) {
        discoverySessionId++;
      }
      suspendShort(250);
      result.success(null);
    });
  }

  // --- Orchestrated unified discovery ---
  private interface ListCallback { void onResult(java.util.List<String> list); }

  private String stripName(String entry) {
    if (entry == null) return null;
    int idx = entry.lastIndexOf(":");
    if (idx > 0) return entry.substring(0, idx);
    return entry;
  }

  private void discoverAllPrinters(@NonNull Result result) {
    synchronized (stateLock) { discoverySessionId++; }
    final java.util.Set<String> dedup = new java.util.HashSet<>();
    final java.util.List<String> agg = new java.util.ArrayList<>();

    setState("discoveringLan");
    runLanDiscovery(5000, lan -> {
      for (String s : lan) {
        String key = stripName(s);
        if (!dedup.contains(key)) { dedup.add(key); agg.add(s); }
      }

      // If USB is attached, prioritize USB path next
      if (isEpsonUsbAttached()) {
        setState("discoveringUsb");
        runUsbDiscovery(4000, usb -> {
          for (String s : usb) {
            String key = stripName(s);
            if (!dedup.contains(key)) { dedup.add(key); agg.add(s); }
          }
          setState("idle");
          result.success(new java.util.ArrayList<>(agg));
        });
        return;
      }

      setState("discoveringBluetooth");
      runBtDiscovery(4000, bt -> {
        for (String s : bt) {
          String key = stripName(s);
          if (!dedup.contains(key)) { dedup.add(key); agg.add(s); }
        }
        setState("discoveringUsb");
        runUsbDiscovery(4000, usb -> {
          for (String s : usb) {
            String key = stripName(s);
            if (!dedup.contains(key)) { dedup.add(key); agg.add(s); }
          }
          setState("idle");
          result.success(new java.util.ArrayList<>(agg));
        });
      });
    });
  }

  // Internal helpers that mirror existing public methods but return via callback
  private void runLanDiscovery(int timeoutMs, @NonNull ListCallback cb) {
    // Stop any existing discovery
    for (int i = 0; i < 10; i++) {
      try { Discovery.stop(); break; }
      catch (Epos2Exception e) { if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) break; try { Thread.sleep(50);} catch (InterruptedException ignored) {} }
      catch (Throwable t) { break; }
    }

    final java.util.List<String> found = new java.util.ArrayList<>();
    final FilterOption filter = new FilterOption();
    filter.setDeviceType(Discovery.TYPE_PRINTER);
    filter.setPortType(Discovery.PORTTYPE_TCP);
    filter.setEpsonFilter(Discovery.FILTER_NAME);

    final DiscoveryListener listener = new DiscoveryListener() {
      @Override public void onDiscovery(final DeviceInfo deviceInfo) {
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
          if (!found.contains(entry)) found.add(entry);
        }
      }
    };

    boolean started = false;
    try { Discovery.start(context, filter, listener); started = true; }
    catch (Exception e) { /* ignore */ }

    final boolean startedFinal = started;
    mainHandler.postDelayed(() -> {
      if (startedFinal) {
        while (true) {
          try { Discovery.stop(); break; }
          catch (Epos2Exception e) { if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) break; }
          catch (Throwable t) { break; }
        }
      }
      synchronized (found) { cb.onResult(new java.util.ArrayList<>(found)); }
    }, Math.max(500, timeoutMs));
  }

  private void runBtDiscovery(int timeoutMs, @NonNull ListCallback cb) {
    // Stop any existing discovery
    for (int i = 0; i < 10; i++) {
      try { Discovery.stop(); break; }
      catch (Epos2Exception e) { if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) break; try { Thread.sleep(50);} catch (InterruptedException ignored) {} }
      catch (Throwable t) { break; }
    }

    final java.util.List<String> found = new java.util.ArrayList<>();
    // Seed with bonded
    for (String entry : getBondedBtPrinters()) { if (!found.contains(entry)) found.add(entry); }

    final FilterOption filter = new FilterOption();
    filter.setDeviceType(Discovery.TYPE_PRINTER);
    filter.setPortType(Discovery.PORTTYPE_BLUETOOTH); // Classic only (BLE not used)
    filter.setEpsonFilter(Discovery.FILTER_NAME);

    final DiscoveryListener listener = new DiscoveryListener() {
      @Override public void onDiscovery(final DeviceInfo deviceInfo) {
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
          if (!found.contains(entry)) found.add(entry);
        }
      }
    };

    boolean started = false;
    try { Discovery.start(context, filter, listener); started = true; }
    catch (Exception e) { /* ignore */ }

    final boolean startedFinal = started;
    mainHandler.postDelayed(() -> {
      if (startedFinal) {
        while (true) {
          try { Discovery.stop(); break; }
          catch (Epos2Exception e) { if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) break; }
          catch (Throwable t) { break; }
        }
      }
      synchronized (found) { cb.onResult(new java.util.ArrayList<>(found)); }
    }, Math.max(500, timeoutMs));
  }

  private void runUsbDiscovery(int timeoutMs, @NonNull ListCallback cb) {
    // Stop any existing discovery
    for (int i = 0; i < 10; i++) {
      try { Discovery.stop(); break; }
      catch (Epos2Exception e) { if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) break; try { Thread.sleep(50);} catch (InterruptedException ignored) {} }
      catch (Throwable t) { break; }
    }

    final java.util.List<String> found = new java.util.ArrayList<>();

    final FilterOption filter = new FilterOption();
    filter.setDeviceType(Discovery.TYPE_PRINTER);
    filter.setPortType(Discovery.PORTTYPE_USB);
    filter.setEpsonFilter(Discovery.FILTER_NAME);

    final DiscoveryListener listener = new DiscoveryListener() {
      @Override public void onDiscovery(final DeviceInfo deviceInfo) {
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

    boolean started = false;
    try { Discovery.start(context, filter, listener); started = true; }
    catch (Exception e) { /* ignore */ }

    final boolean startedFinal = started;
    mainHandler.postDelayed(() -> {
      if (startedFinal) {
        while (true) {
          try { Discovery.stop(); break; }
          catch (Epos2Exception e) { if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) break; }
          catch (Throwable t) { break; }
        }
      }
      // Post USB extra cleanup to avoid internal discovery overlap
      mainHandler.postDelayed(() -> {
        for (int i = 0; i < 10; i++) {
          try { Discovery.stop(); break; }
          catch (Epos2Exception e) { if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) break; }
          catch (Throwable t) { break; }
        }
      }, 500);

      synchronized (found) { cb.onResult(new java.util.ArrayList<>(found)); }
    }, Math.max(500, timeoutMs));
  }

  private void discoverLanPrinters(@NonNull Result result) {
    // CRITICAL: Force stop any existing discovery before starting new one
    // This handles USB disconnect and other hardware state changes
    for (int i = 0; i < 10; i++) {
      try {
        Discovery.stop();
        break;
      } catch (Epos2Exception e) {
        if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) {
          break;
        }
        try { Thread.sleep(50); } catch (InterruptedException ignored) {}
      }
    }
    
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
    // CRITICAL: Force stop any existing discovery before starting new one
    // This handles USB disconnect and other hardware state changes
    for (int i = 0; i < 10; i++) {
      try {
        Discovery.stop();
        break;
      } catch (Epos2Exception e) {
        if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) {
          break;
        }
        try { Thread.sleep(50); } catch (InterruptedException ignored) {}
      }
    }
    
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
    // CRITICAL: Ensure discovery is stopped before ANY connection attempt
    // Do this synchronously with retries to guarantee BT stack is clear
    for (int i = 0; i < 30; i++) {
      try {
        Discovery.stop();
        break; // Success
      } catch (Epos2Exception e) {
        if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) {
          break; // Already stopped or other error
        }
        // Still processing, wait and retry
        try {
          Thread.sleep(100);
        } catch (InterruptedException ie) {
          break;
        }
      } catch (Exception e) {
        break; // Unexpected error, continue anyway
      }
    }
    
    // Additional settling delay for BT stack
    try {
      Thread.sleep(500);
    } catch (InterruptedException e) {
      // Continue
    }
    
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

      // Mark session USB if applicable
      if (target != null && target.startsWith("USB:")) {
        synchronized (stateLock) { usbWasConnectedThisSession = true; }
      }

      result.success(null);
    } catch (Epos2Exception e) {
      safeDisposePrinter();
      String errorMsg = "Connection failed. ";
      if (e.getErrorStatus() == Epos2Exception.ERR_CONNECT) {
        errorMsg += "Make sure your printer isn't connected to any other device via Bluetooth and try again.";
      } else {
        errorMsg += "Epson SDK error: " + e.getMessage();
      }
      result.error("CONNECT_FAILED", errorMsg, e.getErrorStatus());
    } catch (Exception ex) {
      safeDisposePrinter();
      result.error("CONNECT_FAILED", "Connection failed: " + ex.getMessage(), null);
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
      
      // CRITICAL: After disconnecting (especially from USB), synchronously clean up discovery state
      // Wait for disconnect to fully complete, then aggressively stop discovery
      try {
        Thread.sleep(200); // Let disconnect fully complete
      } catch (InterruptedException ignored) {}
      
      android.util.Log.d("EpsonPrinter", "Post-disconnect: starting aggressive discovery cleanup...");
      for (int i = 0; i < 15; i++) {
        try {
          Discovery.stop();
          android.util.Log.d("EpsonPrinter", "Post-disconnect discovery stop succeeded on attempt " + (i + 1));
          break;
        } catch (Epos2Exception e) {
          if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) {
            android.util.Log.d("EpsonPrinter", "Post-disconnect discovery stop: non-processing error, done");
            break;
          }
          android.util.Log.d("EpsonPrinter", "Post-disconnect discovery still processing, retry " + (i + 1));
          try { Thread.sleep(100); } catch (InterruptedException ignored) {}
        }
      }
      
      // Additional settling time after USB disconnect specifically
      try {
        Thread.sleep(300);
      } catch (InterruptedException ignored) {}
      
      // Enter short suspension window to prevent immediate discovery restarts during USB stack settle
      suspendShort(800);

      android.util.Log.d("EpsonPrinter", "Post-disconnect cleanup complete");
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
                String data = (String) params.get("data");
                String align = (String) params.get("align");
                
                // Set alignment if specified
                if (align != null) {
                  if (align.equalsIgnoreCase("center")) {
                    try { mPrinter.addTextAlign(Printer.ALIGN_CENTER); } catch (Exception ignored) {}
                  } else if (align.equalsIgnoreCase("right")) {
                    try { mPrinter.addTextAlign(Printer.ALIGN_RIGHT); } catch (Exception ignored) {}
                  } else {
                    try { mPrinter.addTextAlign(Printer.ALIGN_LEFT); } catch (Exception ignored) {}
                  }
                }
                
                if (data != null && !data.isEmpty()) {
                  mPrinter.addText(data);
                }
                break;
              }
              case "textStyle": {
                // Parse parameters with defaults
                boolean reverse = "true".equals(String.valueOf(params.get("reverse")));
                boolean underline = "true".equals(String.valueOf(params.get("underline")));
                boolean bold = "true".equals(String.valueOf(params.get("bold")));
                
                // Parse color (default to first color)
                int color = Printer.COLOR_1;
                String colorStr = (String) params.get("color");
                if ("none".equals(colorStr)) {
                  color = Printer.COLOR_NONE;
                } else if ("2".equals(colorStr)) {
                  color = Printer.COLOR_2;
                } else if ("3".equals(colorStr)) {
                  color = Printer.COLOR_3;
                } else if ("4".equals(colorStr)) {
                  color = Printer.COLOR_4;
                }
                
                try {
                  mPrinter.addTextStyle(
                    reverse ? Printer.TRUE : Printer.FALSE,
                    underline ? Printer.TRUE : Printer.FALSE,
                    bold ? Printer.TRUE : Printer.FALSE,
                    color
                  );
                } catch (Exception ignored) {}
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
                  System.out.println("DEBUG: Attempting to decode image from path: " + imagePath);
                  Bitmap bmp = BitmapFactory.decodeFile(imagePath);
                  if (bmp != null) {
                    System.out.println("DEBUG: Image decoded successfully - width: " + bmp.getWidth() + ", height: " + bmp.getHeight());
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
                  } else {
                    System.out.println("ERROR: Failed to decode image from path: " + imagePath);
                    // Check if file exists
                    java.io.File imageFile = new java.io.File(imagePath);
                    System.out.println("DEBUG: File exists: " + imageFile.exists() + ", canRead: " + imageFile.canRead() + ", size: " + imageFile.length());
                    if (debug) {
                      try { mPrinter.addText("[IMG_DECODE_FAILED]\n"); } catch (Exception ignored) {}
                    }
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
                String cutType = (String) params.get("cutType");
                if ("no_feed".equalsIgnoreCase(cutType)) {
                  mPrinter.addCut(Printer.CUT_NO_FEED);
                } else if ("reserve".equalsIgnoreCase(cutType)) {
                  mPrinter.addCut(Printer.CUT_RESERVE);
                } else if ("full_cut_feed".equalsIgnoreCase(cutType)) {
                  mPrinter.addCut(Printer.FULL_CUT_FEED);
                } else if ("full_cut_no_feed".equalsIgnoreCase(cutType)) {
                  mPrinter.addCut(Printer.FULL_CUT_NO_FEED);
                } else {
                  mPrinter.addCut(Printer.CUT_FEED);
                }
                break;
              }
              case "feedPosition": {
                String position = (String) params.get("position");
                if ("peeling".equalsIgnoreCase(position)) {
                  mPrinter.addFeedPosition(Printer.FEED_PEELING);
                } else if ("current_tof".equalsIgnoreCase(position)) {
                  mPrinter.addFeedPosition(Printer.FEED_CURRENT_TOF);
                } else {
                  mPrinter.addFeedPosition(Printer.FEED_CUTTING);
                }
                break;
              }
              case "barcode": {
                String data = (String) params.get("data");
                String typeStr = (String) params.get("type");
                String hriStr = (String) params.get("hri");
                String fontStr = (String) params.get("font");
                Object widthObj = params.get("width");
                Object heightObj = params.get("height");
                
                if (data == null || data.isEmpty()) {
                  break; // Skip if no data
                }
                
                // Map barcode type
                int barcodeType = Printer.BARCODE_CODE128_AUTO; // Default
                if ("CODE128_AUTO".equals(typeStr)) {
                  barcodeType = Printer.BARCODE_CODE128_AUTO;
                } else if ("CODE128".equals(typeStr)) {
                  barcodeType = Printer.BARCODE_CODE128;
                } else if ("UPC_A".equals(typeStr)) {
                  barcodeType = Printer.BARCODE_UPC_A;
                } else if ("UPC_E".equals(typeStr)) {
                  barcodeType = Printer.BARCODE_UPC_E;
                } else if ("EAN13".equals(typeStr)) {
                  barcodeType = Printer.BARCODE_EAN13;
                } else if ("EAN8".equals(typeStr)) {
                  barcodeType = Printer.BARCODE_EAN8;
                } else if ("CODE39".equals(typeStr)) {
                  barcodeType = Printer.BARCODE_CODE39;
                }
                
                // Map HRI position
                int hri = Printer.HRI_NONE; // Default
                if ("below".equals(hriStr)) {
                  hri = Printer.HRI_BELOW;
                } else if ("above".equals(hriStr)) {
                  hri = Printer.HRI_ABOVE;
                } else if ("both".equals(hriStr)) {
                  hri = Printer.HRI_BOTH;
                }
                
                // Map font
                int font = Printer.FONT_A; // Default
                if ("B".equals(fontStr)) {
                  font = Printer.FONT_B;
                } else if ("C".equals(fontStr)) {
                  font = Printer.FONT_C;
                } else if ("D".equals(fontStr)) {
                  font = Printer.FONT_D;
                } else if ("E".equals(fontStr)) {
                  font = Printer.FONT_E;
                }
                
                // Parse width and height
                int width = 2; // Default
                if (widthObj instanceof Number) {
                  width = ((Number) widthObj).intValue();
                  if (width < 2 || width > 6) width = 2;
                }
                
                int height = 60; // Default
                if (heightObj instanceof Number) {
                  height = ((Number) heightObj).intValue();
                  if (height < 1 || height > 255) height = 60;
                }
                
                try {
                  mPrinter.addBarcode(data, barcodeType, hri, font, width, height);
                } catch (Exception ignored) {}
                break;
              }
              // Additional commands (qrCode/image/pulse/beep/layout) can be added later
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
    // CRITICAL: Force stop any existing discovery before starting new one
    // This handles USB disconnect and other hardware state changes
    for (int i = 0; i < 10; i++) {
      try {
        Discovery.stop();
        break;
      } catch (Epos2Exception e) {
        if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) {
          break;
        }
        try { Thread.sleep(50); } catch (InterruptedException ignored) {}
      }
    }
    
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
      
      // CRITICAL: For USB discovery, add delayed cleanup stop to ensure BLE/BT is fully terminated
      // This prevents thread priority inversion on subsequent discoveries (matches iOS fix)
      new android.os.Handler(android.os.Looper.getMainLooper()).postDelayed(() -> {
        android.util.Log.d("EpsonPrinter", "USB discovery: forcing additional stop to clean up internal discovery state...");
        while (true) {
          try {
            Discovery.stop();
            android.util.Log.d("EpsonPrinter", "USB discovery cleanup stop completed");
            break;
          } catch (Epos2Exception e) {
            if (e.getErrorStatus() != Epos2Exception.ERR_PROCESSING) {
              break;
            }
          }
        }
      }, 500);
      
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

  private void detectPaperWidth(@NonNull Result result) {
    if (mPrinter == null) {
      result.error("NOT_CONNECTED", "Printer not connected", null);
      return;
    }

    // Create a listener for getPrinterSetting callback
    PrinterSettingListener settingListener = new PrinterSettingListener() {
      @Override
      public void onGetPrinterSetting(int code, int type, int value) {
        Handler mainHandler = new Handler(Looper.getMainLooper());
        mainHandler.post(() -> {
          // Log the actual values for debugging
          android.util.Log.d("EpsonPrinter", "getPrinterSetting result - code: " + code + ", type: " + type + ", value: " + value);
          
          // Use 0 as success code (common pattern in SDK)
          if (code == 0) {
            String paperWidth = mapPaperWidthValue(value);
            android.util.Log.d("EpsonPrinter", "Mapped paper width: " + paperWidth + " (from value: " + value + ")");
            result.success(paperWidth);
          } else {
            // Return error with actual codes for debugging
            result.error("DETECTION_FAILED", "getPrinterSetting failed - code: " + code + ", type: " + type + ", value: " + value, null);
          }
        });
      }

      @Override
      public void onSetPrinterSetting(int code) {
        // Not used for getPrinterSetting
      }
    };

    try {
      // Based on the API doc pattern and existing code, try likely constant values
      // From the docs: "Printer.Setting.PaperWidth" but actual SDK likely uses different naming
      // Let's try a few common patterns for the paper width setting type constant
      
      // Pattern 1: Try simple numbering (0, 1, 2...)
      mPrinter.getPrinterSetting(Printer.PARAM_DEFAULT, 0, settingListener);
    } catch (Exception e) {
      result.error("DETECTION_FAILED", "getPrinterSetting exception: " + e.getMessage(), null);
    }
  }

  private String mapPaperWidthValue(int value) {
    // Map the received value to paper width strings
    // Based on actual testing with TM-m30iii:
    // - 58mm setting returns value: 2
    // - 80mm setting returns value: 6
    switch (value) {
      case 2: return "58mm";       // CONFIRMED: 58mm setting returns value 2
      case 6: return "80mm";       // CONFIRMED: 80mm setting returns value 6
      // Other potential values (not yet tested on TM-m30iii):
      case 0: return "Unknown-0";  // May correspond to 60mm, 70mm, or 76mm - needs testing
      case 1: return "Unknown-1";  
      case 3: return "Unknown-3";  
      case 4: return "Unknown-4";  
      case 5: return "Unknown-5";  
      default: 
        // Return the raw value for debugging
        return "Unknown(" + value + ")";
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
