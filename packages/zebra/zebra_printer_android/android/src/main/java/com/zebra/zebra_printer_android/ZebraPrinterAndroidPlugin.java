package com.zebra.zebra_printer_android;

import android.app.Activity;
import android.app.PendingIntent;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.net.wifi.WifiManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

import com.zebra.sdk.comm.Connection;
import com.zebra.sdk.comm.ConnectionException;
import com.zebra.sdk.comm.TcpConnection;
import com.zebra.sdk.comm.BluetoothConnection;
import com.zebra.sdk.comm.BluetoothConnectionInsecure;
import com.zebra.sdk.btleComm.BluetoothLeConnection;
import com.zebra.sdk.btleComm.BluetoothLeDiscoverer;
import com.zebra.sdk.btleComm.DiscoveredPrinterBluetoothLe;
import com.zebra.sdk.printer.discovery.DiscoveredPrinter;
import com.zebra.sdk.printer.discovery.DiscoveredPrinterNetwork;
import com.zebra.sdk.printer.discovery.DiscoveryHandler;
import com.zebra.sdk.printer.discovery.DiscoveryException;
import com.zebra.sdk.printer.discovery.NetworkDiscoverer;
import com.zebra.sdk.printer.discovery.UsbDiscoverer;
import com.zebra.sdk.printer.discovery.DiscoveredPrinterUsb;
import com.zebra.sdk.printer.discovery.BluetoothDiscoverer;
import com.zebra.sdk.printer.ZebraPrinter;
import com.zebra.sdk.printer.ZebraPrinterFactory;
import com.zebra.sdk.printer.ZebraPrinterLanguageUnknownException;
import com.zebra.sdk.printer.PrinterStatus;
import com.zebra.sdk.settings.SettingsException;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.CompletableFuture;
import java.io.ByteArrayOutputStream;
import java.io.IOException;

/** ZebraPrinterAndroidPlugin */
public class ZebraPrinterAndroidPlugin implements FlutterPlugin, MethodCallHandler, ActivityAware {
    private static final String TAG = "ZebraPrinterAndroid";
    private MethodChannel channel;
    private Context context;
    private Activity activity;
    private Connection activeConnection;
    private ZebraPrinter zebraPrinter;
    private ExecutorService executor = Executors.newCachedThreadPool();
    private Handler mainHandler = new Handler(Looper.getMainLooper());
    
    // USB permission handling
    private static final String USB_PERMISSION_ACTION = "com.zebra.zebra_printer_android.USB_PERMISSION";
    private CompletableFuture<Boolean> usbPermissionFuture;
    private BroadcastReceiver usbPermissionReceiver;
    
    // Discovery state management
    private volatile boolean isUsbDiscoveryInProgress = false;
    private volatile boolean isNetworkDiscoveryInProgress = false;
    private volatile boolean isBleDiscoveryInProgress = false;

    // Helper method to get printer address based on type
    private String getPrinterAddress(DiscoveredPrinter printer) {
        if (printer instanceof DiscoveredPrinterNetwork) {
            return ((DiscoveredPrinterNetwork) printer).address;
        } else {
            return printer.toString();
        }
    }

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding flutterPluginBinding) {
        channel = new MethodChannel(flutterPluginBinding.getBinaryMessenger(), "zebra_printer");
        channel.setMethodCallHandler(this);
        context = flutterPluginBinding.getApplicationContext();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
        switch (call.method) {
            case "discoverPrinters":
                discoverPrinters(call, result);
                break;
            case "discoverNetworkPrintersAuto":
                discoverNetworkPrintersAuto(call, result);
                break;
            case "discoverMulticastPrinters":
                discoverMulticastPrinters(call, result);
                break;
            case "discoverSubnetSearch":
                discoverSubnetSearch(call, result);
                break;
            case "discoverBluetoothPrinters":
                discoverBluetoothPrinters(call, result);
                break;
            case "discoverBluetoothNative":
                discoverBluetoothNative(call, result);
                break;
            case "testDirectBleConnection":
                testDirectBleConnection(call, result);
                break;
            case "discoverUsbPrinters":
                discoverUsbPrinters(call, result);
                break;
            case "requestBluetoothPermissions":
                requestBluetoothPermissions(result);
                break;
            case "requestUsbPermissions":
                requestUsbPermissions(call, result);
                break;
            case "connect":
                connect(call, result);
                break;
            case "disconnect":
                disconnect(result);
                break;
            case "sendCommands":
                sendCommands(call, result);
                break;
            case "isConnected":
                isConnected(result);
                break;
            case "getActiveConnection":
                getActiveConnection(result);
                break;
            case "getSgdParameter":
                getSgdParameter(call, result);
                break;
            case "setSgdParameter":
                setSgdParameter(call, result);
                break;
            case "getPrinterDimensions":
                getPrinterDimensions(result);
                break;
            case "setLabelLength":
                setLabelLength(call, result);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private void discoverNetworkPrintersAuto(MethodCall call, Result result) {
        // Check if discovery is already in progress
        if (isNetworkDiscoveryInProgress) {
            result.error("DISCOVERY_IN_PROGRESS", "Network discovery is already in progress. Please wait for it to complete.", null);
            return;
        }
        
        executor.execute(() -> {
            try {
                isNetworkDiscoveryInProgress = true;
                Log.d(TAG, "Starting auto network discovery using findPrinters");
                
                final List<DiscoveredPrinter> discoveredPrinters = new ArrayList<>();
                final Object discoveryLock = new Object();
                final boolean[] discoveryComplete = {false};
                
                DiscoveryHandler discoveryHandler = new DiscoveryHandler() {
                    @Override
                    public void foundPrinter(DiscoveredPrinter printer) {
                        synchronized (discoveredPrinters) {
                            // Check for duplicates based on address
                            boolean duplicate = false;
                            for (DiscoveredPrinter existing : discoveredPrinters) {
                                if (getPrinterAddress(existing).equals(getPrinterAddress(printer))) {
                                    duplicate = true;
                                    break;
                                }
                            }
                            if (!duplicate) {
                                discoveredPrinters.add(printer);
                                Log.d(TAG, "Found printer: " + getPrinterAddress(printer));
                            }
                        }
                    }

                    @Override
                    public void discoveryFinished() {
                        Log.d(TAG, "Auto discovery finished");
                        synchronized (discoveryLock) {
                            discoveryComplete[0] = true;
                            discoveryLock.notify();
                        }
                    }

                    @Override
                    public void discoveryError(String error) {
                        Log.e(TAG, "Auto discovery error: " + error);
                        synchronized (discoveryLock) {
                            discoveryComplete[0] = true;
                            discoveryLock.notify();
                        }
                    }
                };
                
                // Use findPrinters which combines multiple discovery methods
                WifiManager wifi = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
                WifiManager.MulticastLock lock = wifi.createMulticastLock("zebra_discovery_lock");
                lock.setReferenceCounted(true);
                lock.acquire();
                
                try {
                    NetworkDiscoverer.findPrinters(discoveryHandler);
                    
                    // Wait for discovery to complete
                    synchronized (discoveryLock) {
                        while (!discoveryComplete[0]) {
                            discoveryLock.wait(15000); // 15 second timeout for comprehensive search
                            break; // Exit if timeout
                        }
                    }
                } finally {
                    lock.release();
                }

                List<Map<String, Object>> printers = new ArrayList<>();
                synchronized (discoveredPrinters) {
                    for (DiscoveredPrinter printer : discoveredPrinters) {
                        Map<String, Object> printerMap = new HashMap<>();
                        printerMap.put("friendlyName", printer.getDiscoveryDataMap().get("FRIENDLY_NAME"));
                        printerMap.put("address", getPrinterAddress(printer));
                        printerMap.put("port", 9100);
                        printerMap.put("interfaceType", "TCP");
                        printerMap.put("serialNumber", printer.getDiscoveryDataMap().get("SERIAL_NUMBER"));
                        printerMap.put("additionalInfo", printer.getDiscoveryDataMap());
                        printers.add(printerMap);
                    }
                }

                mainHandler.post(() -> {
                    Log.d(TAG, "Auto network discovery completed. Found " + printers.size() + " printers");
                    result.success(printers);
                });
                
            } catch (Exception e) {
                Log.e(TAG, "Auto network discovery failed", e);
                mainHandler.post(() -> {
                    result.error("DISCOVERY_FAILED", e.getMessage(), null);
                });
            } finally {
                isNetworkDiscoveryInProgress = false;
            }
        });
    }

    private void connect(MethodCall call, Result result) {
        @SuppressWarnings("unchecked")
        Map<String, Object> settings = (Map<String, Object>) call.arguments;
        if (settings == null) {
            result.error("MISSING_ARGUMENT", "Connection settings are required", null);
            return;
        }

        String interfaceType = (String) settings.get("interfaceType");
        String identifier = (String) settings.get("identifier");
        Integer timeout = (Integer) settings.get("timeout");
        
        if (interfaceType == null || identifier == null) {
            result.error("MISSING_ARGUMENT", "interfaceType and identifier are required", null);
            return;
        }

        // Support TCP, Bluetooth, and USB connections
        if (!"tcp".equalsIgnoreCase(interfaceType) && 
            !"bluetooth".equalsIgnoreCase(interfaceType) && 
            !"usb".equalsIgnoreCase(interfaceType)) {
            result.error("UNSUPPORTED_INTERFACE", "Only TCP, Bluetooth, and USB interfaces are currently supported", null);
            return;
        }

        executor.execute(() -> {
            // Only prepare Looper if one doesn't already exist
            if (Looper.myLooper() == null) {
                Looper.prepare(); // Required for Bluetooth connections per Zebra SDK docs
            }
            try {
                Log.d(TAG, "Connecting to " + interfaceType + " printer at " + identifier);
                
                // Close existing connection if any
                if (activeConnection != null && activeConnection.isConnected()) {
                    activeConnection.close();
                }

                // Create connection based on interface type
                if ("tcp".equalsIgnoreCase(interfaceType)) {
                    // Parse IP address and port from identifier
                    String ipAddress;
                    int port = 9100; // Default Zebra port
                    
                    if (identifier.contains(":")) {
                        String[] parts = identifier.split(":");
                        ipAddress = parts[0];
                        try {
                            port = Integer.parseInt(parts[1]);
                        } catch (NumberFormatException e) {
                            // Keep default port if parsing fails
                        }
                    } else {
                        ipAddress = identifier;
                    }
                    
                    activeConnection = new TcpConnection(ipAddress, port);
                } else if ("bluetooth".equalsIgnoreCase(interfaceType)) {
                    // Get connection type from printer data (secure vs insecure)
                    String connectionType = (String) settings.get("connectionType");
                    boolean isClassicBluetooth = isClassicBluetoothDevice(identifier);
                    
                    if (isClassicBluetooth) {
                        if ("secure".equals(connectionType)) {
                            Log.d(TAG, "Creating Secure Classic Bluetooth connection to: " + identifier);
                            activeConnection = new BluetoothConnection(identifier);
                        } else {
                            Log.d(TAG, "Creating Insecure Classic Bluetooth connection to: " + identifier);
                            activeConnection = new BluetoothConnectionInsecure(identifier);
                        }
                    } else {
                        Log.d(TAG, "Creating BLE connection to: " + identifier);
                        // Create Bluetooth LE connection using MAC address
                        activeConnection = new BluetoothLeConnection(identifier);
                        
                        // Set context for BLE connection (required by Zebra SDK)
                        if (activeConnection instanceof BluetoothLeConnection) {
                            ((BluetoothLeConnection) activeConnection).setContext(activity);
                        }
                    }
                } else if ("usb".equalsIgnoreCase(interfaceType)) {
                    // USB connections require the DiscoveredPrinterUsb object
                    // For now, we'll need to discover the printer again to get the connection
                    Log.d(TAG, "Creating USB connection for device: " + identifier);
                    
                    // Find the USB printer by discovering again
                    final DiscoveredPrinterUsb[] foundUsbPrinter = new DiscoveredPrinterUsb[1];
                    final boolean[] discoveryComplete = new boolean[1];
                    
                    DiscoveryHandler usbDiscoveryHandler = new DiscoveryHandler() {
                        @Override
                        public void foundPrinter(DiscoveredPrinter discoveredPrinter) {
                            if (discoveredPrinter instanceof DiscoveredPrinterUsb) {
                                DiscoveredPrinterUsb usbPrinter = (DiscoveredPrinterUsb) discoveredPrinter;
                                if (identifier.equals(usbPrinter.device.getDeviceName()) ||
                                    identifier.contains(String.valueOf(usbPrinter.device.getProductId()))) {
                                    foundUsbPrinter[0] = usbPrinter;
                                }
                            }
                        }

                        @Override
                        public void discoveryFinished() {
                            discoveryComplete[0] = true;
                        }

                        @Override
                        public void discoveryError(String message) {
                            discoveryComplete[0] = true;
                        }
                    };
                    
                    UsbDiscoverer.findPrinters(activity.getApplicationContext(), usbDiscoveryHandler);
                    
                    // Wait for discovery to complete (timeout after 5 seconds)
                    int waitCount = 0;
                    while (!discoveryComplete[0] && waitCount < 50) {
                        try {
                            Thread.sleep(100);
                            waitCount++;
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                            break;
                        }
                    }
                    
                    if (foundUsbPrinter[0] == null) {
                        throw new Exception("USB printer not found: " + identifier);
                    }
                    
                    // Request USB permission asynchronously
                    CompletableFuture<Boolean> permissionFuture = requestUsbPermissionAsync(foundUsbPrinter[0].device);
                    
                    permissionFuture.thenAccept(granted -> {
                        if (!granted) {
                            mainHandler.post(() -> result.error("USB_PERMISSION_DENIED", "USB permission was denied", null));
                            return;
                        }
                        
                        try {
                            // Get USB connection
                            activeConnection = foundUsbPrinter[0].getConnection();
                            
                            if (activeConnection == null) {
                                mainHandler.post(() -> result.error("CONNECTION_ERROR", "Failed to create USB connection", null));
                                return;
                            }
                            
                            activeConnection.open();
                            
                            // Create ZebraPrinter instance
                            zebraPrinter = ZebraPrinterFactory.getInstance(activeConnection);

                            mainHandler.post(() -> {
                                Log.d(TAG, "Successfully connected to USB printer");
                                result.success(true);
                            });
                        } catch (Exception e) {
                            Log.e(TAG, "USB connection failed after permission granted", e);
                            mainHandler.post(() -> result.error("CONNECTION_ERROR", "USB connection failed: " + e.getMessage(), null));
                        }
                    }).exceptionally(throwable -> {
                        Log.e(TAG, "USB permission request failed", throwable);
                        mainHandler.post(() -> result.error("USB_PERMISSION_ERROR", "USB permission request failed: " + throwable.getMessage(), null));
                        return null;
                    });
                    
                    // Return early for USB - the completion will be handled asynchronously
                    return;
                }
                
                if (activeConnection == null) {
                    throw new Exception("Failed to create connection for interface type: " + interfaceType);
                }
                
                activeConnection.open();
                
                // Create ZebraPrinter instance
                zebraPrinter = ZebraPrinterFactory.getInstance(activeConnection);

                mainHandler.post(() -> {
                    Log.d(TAG, "Successfully connected to printer");
                    result.success(true);
                });
                
            } catch (Exception e) {
                Log.e(TAG, "Connection failed", e);
                mainHandler.post(() -> {
                    result.error("CONNECTION_FAILED", e.getMessage(), null);
                });
            } finally {
                // Only quit Looper if it exists and we're on a background thread
                if (Looper.myLooper() != null && Looper.myLooper() != Looper.getMainLooper()) {
                    Looper.myLooper().quit();
                }
            }
        });
    }

    private void disconnect(Result result) {
        executor.execute(() -> {
            try {
                if (activeConnection != null && activeConnection.isConnected()) {
                    activeConnection.close();
                    Log.d(TAG, "Disconnected from printer");
                }
                activeConnection = null;
                zebraPrinter = null;

                mainHandler.post(() -> {
                    result.success(true);
                });
                
            } catch (Exception e) {
                Log.e(TAG, "Disconnect failed", e);
                mainHandler.post(() -> {
                    result.error("DISCONNECT_FAILED", e.getMessage(), null);
                });
            }
        });
    }

    private void sendCommands(MethodCall call, Result result) {
        String commands = call.argument("commands");
        if (commands == null) {
            result.error("MISSING_ARGUMENT", "Commands are required", null);
            return;
        }

        if (activeConnection == null || !activeConnection.isConnected()) {
            result.error("NOT_CONNECTED", "No active printer connection", null);
            return;
        }

        executor.execute(() -> {
            try {
                Log.d(TAG, "Sending commands to printer: " + commands);
                
                // Send raw ZPL commands
                activeConnection.write(commands.getBytes());

                mainHandler.post(() -> {
                    Log.d(TAG, "Commands sent successfully");
                    result.success(true);
                });
                
            } catch (Exception e) {
                Log.e(TAG, "Failed to send commands", e);
                mainHandler.post(() -> {
                    result.error("SEND_FAILED", e.getMessage(), null);
                });
            }
        });
    }

    private void getActiveConnection(Result result) {
        if (activeConnection != null && activeConnection.isConnected()) {
            Map<String, Object> connectionInfo = new HashMap<>();
            connectionInfo.put("isConnected", true);
            connectionInfo.put("type", "TCP");
            result.success(connectionInfo);
        } else {
            result.success(null);
        }
    }

    private void discoverBluetoothPrinters(MethodCall call, Result result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity context is required for Bluetooth discovery", null);
            return;
        }

        // Check if discovery is already in progress
        if (isBleDiscoveryInProgress) {
            result.error("DISCOVERY_IN_PROGRESS", "Bluetooth discovery is already in progress. Please wait for it to complete.", null);
            return;
        }

        // Check for required permissions
        if (!hasBluetoothPermissions()) {
            result.error("MISSING_PERMISSIONS", 
                "Bluetooth permissions are required. Please grant BLUETOOTH_SCAN and location permissions.", 
                null);
            return;
        }

        // Check if Bluetooth is enabled
        BluetoothManager bluetoothManager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
        BluetoothAdapter bluetoothAdapter = bluetoothManager.getAdapter();
        
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
            result.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled. Please enable Bluetooth and try again.", null);
            return;
        }

        Log.d(TAG, "Starting Bluetooth discovery - Adapter state: " + bluetoothAdapter.getState());
        Log.d(TAG, "Bluetooth permissions check passed");

        // Cancel any ongoing discovery before starting new one
        try {
            if (bluetoothAdapter.isDiscovering()) {
                if (ActivityCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED) {
                    bluetoothAdapter.cancelDiscovery();
                    Log.d(TAG, "Cancelled existing discovery before starting new one");
                    // Wait a moment for cancellation to complete
                    Thread.sleep(500);
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "Error cancelling existing discovery: " + e.getMessage());
        }

        new Thread(() -> {
            Looper.prepare();
            try {
                isBleDiscoveryInProgress = true;
                Log.d(TAG, "Starting Bluetooth discovery using BluetoothDiscoverer...");
                
                List<Map<String, Object>> discoveredPrinters = new ArrayList<>();
                final boolean[] discoveryCompleted = {false};
                
                // Create a timeout handler
                Handler timeoutHandler = new Handler(Looper.getMainLooper());
                Runnable timeoutRunnable = () -> {
                    if (!discoveryCompleted[0]) {
                        Log.w(TAG, "Bluetooth discovery timed out after 30 seconds");
                        discoveryCompleted[0] = true;
                        
                        // Clean up any ongoing discovery
                        try {
                            if (bluetoothAdapter != null && bluetoothAdapter.isDiscovering()) {
                                if (ActivityCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED) {
                                    bluetoothAdapter.cancelDiscovery();
                                    Log.d(TAG, "Cancelled discovery due to timeout");
                                }
                            }
                        } catch (Exception e) {
                            Log.w(TAG, "Error cancelling discovery on timeout: " + e.getMessage());
                        }
                        
                        mainHandler.post(() -> {
                            result.success(discoveredPrinters); // Return whatever we found so far
                        });
                        isBleDiscoveryInProgress = false;
                    }
                };
                
                // Set 30 second timeout
                timeoutHandler.postDelayed(timeoutRunnable, 30000);
                
                Log.d(TAG, "Calling BluetoothDiscoverer.findPrinters() with context: " + context.getClass().getSimpleName());
                
                // First try to check paired devices (like iOS checks connected accessories)
                try {
                    if (ActivityCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) {
                        Set<BluetoothDevice> pairedDevices = bluetoothAdapter.getBondedDevices();
                        Log.d(TAG, "Found " + pairedDevices.size() + " paired Bluetooth devices");
                        
                        for (BluetoothDevice device : pairedDevices) {
                            String deviceName = device.getName();
                            String deviceAddress = device.getAddress();
                            
                            Log.d(TAG, "Checking paired device: " + deviceName + " (" + deviceAddress + ")");
                            
                            // Check if this looks like a Zebra printer
                            boolean isZebraPrinter = false;
                            
                            if (deviceName != null) {
                                String nameLower = deviceName.toLowerCase();
                                
                                // Check for explicit Zebra branding
                                if (nameLower.contains("zebra") || nameLower.contains("zq") || 
                                    nameLower.contains("zt") || nameLower.contains("zd")) {
                                    isZebraPrinter = true;
                                }
                                // Check for Zebra printer serial number patterns
                                // Zebra printers often use serial numbers like: 50N220800901, XXABC123456, etc.
                                else if (deviceName.matches("^[0-9]{2}[A-Z][0-9]{9}$") ||  // 50N220800901 pattern
                                         deviceName.matches("^[A-Z0-9]{10,15}$") ||        // General alphanumeric serial
                                         deviceName.matches("^[0-9A-Z]{8,12}$")) {        // Shorter serial patterns
                                    Log.d(TAG, "Device name matches Zebra serial number pattern: " + deviceName);
                                    isZebraPrinter = true;
                                }
                            }
                            
                            if (isZebraPrinter) {
                                Log.d(TAG, "Found paired Zebra printer: " + deviceName);
                                
                                Map<String, Object> printerMap = new HashMap<>();
                                printerMap.put("friendlyName", deviceName);
                                printerMap.put("address", deviceAddress);
                                printerMap.put("interfaceType", "bluetooth");
                                printerMap.put("port", 0);  // Integer, not string
                                printerMap.put("serialNumber", deviceAddress); // Use MAC as serial for paired devices
                                printerMap.put("manufacturer", "Zebra");
                                printerMap.put("connectionType", "secure");
                                
                                discoveredPrinters.add(printerMap);
                            }
                        }
                    }
                } catch (Exception e) {
                    Log.w(TAG, "Error checking paired devices: " + e.getMessage());
                }
                
                // If we found paired printers, return them immediately
                if (!discoveredPrinters.isEmpty()) {
                    Log.d(TAG, "Found " + discoveredPrinters.size() + " paired Zebra printers, returning immediately");
                    discoveryCompleted[0] = true;
                    timeoutHandler.removeCallbacks(timeoutRunnable);
                    mainHandler.post(() -> {
                        result.success(discoveredPrinters);
                    });
                    isBleDiscoveryInProgress = false;
                    return;
                }
                
                Log.d(TAG, "No paired Zebra printers found, starting active discovery...");
                
                // Use Zebra SDK BluetoothDiscoverer for active discovery - following official demo pattern
                BluetoothDiscoverer.findPrinters(context, new DiscoveryHandler() {
                    @Override
                    public void foundPrinter(DiscoveredPrinter discoveredPrinter) {
                        if (discoveryCompleted[0]) return;
                        
                        Log.d(TAG, "Found Bluetooth printer: " + discoveredPrinter.getDiscoveryDataMap());
                        
                        Map<String, Object> printerMap = new HashMap<>();
                        printerMap.put("friendlyName", discoveredPrinter.getDiscoveryDataMap().get("FRIENDLY_NAME"));
                        printerMap.put("address", getPrinterAddress(discoveredPrinter));
                        printerMap.put("interfaceType", "bluetooth");
                        printerMap.put("port", 0);  // Integer, not string
                        printerMap.put("serialNumber", discoveredPrinter.getDiscoveryDataMap().get("SERIAL_NUMBER"));
                        printerMap.put("manufacturer", "Zebra");
                        printerMap.put("connectionType", "secure"); // Mark as secure Bluetooth
                        
                        discoveredPrinters.add(printerMap);
                    }
                    
                    @Override
                    public void discoveryFinished() {
                        if (discoveryCompleted[0]) return;
                        
                        Log.d(TAG, "Bluetooth discovery finished. Found " + discoveredPrinters.size() + " printers");
                        discoveryCompleted[0] = true;
                        timeoutHandler.removeCallbacks(timeoutRunnable);
                        mainHandler.post(() -> {
                            result.success(discoveredPrinters);
                        });
                        isBleDiscoveryInProgress = false;
                    }
                    
                    @Override
                    public void discoveryError(String message) {
                        if (discoveryCompleted[0]) return;
                        
                        Log.e(TAG, "Bluetooth discovery error: " + message);
                        discoveryCompleted[0] = true;
                        timeoutHandler.removeCallbacks(timeoutRunnable);
                        mainHandler.post(() -> {
                            result.error("DISCOVERY_FAILED", message, null);
                        });
                        isBleDiscoveryInProgress = false;
                    }
                });
                
            } catch (ConnectionException e) {
                Log.e(TAG, "Bluetooth discovery ConnectionException: " + e.getMessage());
                mainHandler.post(() -> {
                    result.error("CONNECTION_EXCEPTION", e.getMessage(), null);
                });
                isBleDiscoveryInProgress = false;
            } catch (Exception e) {
                Log.e(TAG, "Bluetooth discovery failed", e);
                mainHandler.post(() -> {
                    result.error("DISCOVERY_FAILED", e.getMessage(), null);
                });
                isBleDiscoveryInProgress = false;
            } finally {
                // Clean up Bluetooth state
                try {
                    if (bluetoothAdapter != null && bluetoothAdapter.isDiscovering()) {
                        if (ActivityCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED) {
                            bluetoothAdapter.cancelDiscovery();
                            Log.d(TAG, "Cancelled ongoing Bluetooth discovery to clean up");
                        }
                    }
                } catch (Exception e) {
                    Log.w(TAG, "Error cleaning up Bluetooth state: " + e.getMessage());
                }
                
                // Always clean up the Looper if we're on a background thread
                if (Looper.myLooper() != null && Looper.myLooper() != Looper.getMainLooper()) {
                    Looper.myLooper().quit();
                }
            }
        }).start();
    }

    private List<Map<String, Object>> discoverClassicBluetoothPrinters() {
        List<Map<String, Object>> classicPrinters = new ArrayList<>();
        
        try {
            BluetoothManager bluetoothManager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
            BluetoothAdapter bluetoothAdapter = bluetoothManager.getAdapter();
            
            if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
                Log.d(TAG, "Bluetooth adapter not available or not enabled");
                return classicPrinters;
            }
            
            // Check permissions for getBondedDevices
            if (ActivityCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                Log.w(TAG, "Missing BLUETOOTH_CONNECT permission for Classic Bluetooth discovery");
                return classicPrinters;
            }
            
            // Get paired (bonded) devices
            Set<BluetoothDevice> pairedDevices = bluetoothAdapter.getBondedDevices();
            Log.d(TAG, "Found " + pairedDevices.size() + " paired Bluetooth devices");
            
            for (BluetoothDevice device : pairedDevices) {
                String deviceName = device.getName();
                String deviceAddress = device.getAddress();
                
                Log.d(TAG, "Checking paired device: " + deviceName + " (" + deviceAddress + ")");
                
                // Filter for Zebra printers (you can adjust this logic)
                if (deviceName != null && (deviceName.toLowerCase().contains("zebra") || 
                    deviceName.toLowerCase().contains("zd410") || 
                    deviceName.toLowerCase().contains("zd421"))) {
                    
                    Log.d(TAG, "Found Zebra Classic Bluetooth printer: " + deviceName);
                    
                    Map<String, Object> printerMap = new HashMap<>();
                    printerMap.put("friendlyName", deviceName);
                    printerMap.put("address", deviceAddress);
                    printerMap.put("interfaceType", "bluetooth");
                    printerMap.put("port", "0");
                    printerMap.put("serialNumber", "Unknown");
                    printerMap.put("manufacturer", "Zebra");
                    printerMap.put("connectionType", "secure"); // Mark as secure Bluetooth
                    
                    classicPrinters.add(printerMap);
                }
            }
            
            Log.d(TAG, "Classic Bluetooth discovery found " + classicPrinters.size() + " Zebra printers");
            
        } catch (Exception e) {
            Log.e(TAG, "Error during Classic Bluetooth discovery", e);
        }
        
        return classicPrinters;
    }

    private boolean isClassicBluetoothDevice(String macAddress) {
        try {
            BluetoothManager bluetoothManager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
            BluetoothAdapter bluetoothAdapter = bluetoothManager.getAdapter();
            
            if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
                return false;
            }
            
            // Check permissions for getBondedDevices
            if (ActivityCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                return false;
            }
            
            // Check if the MAC address is in paired devices
            Set<BluetoothDevice> pairedDevices = bluetoothAdapter.getBondedDevices();
            for (BluetoothDevice device : pairedDevices) {
                if (macAddress.equalsIgnoreCase(device.getAddress())) {
                    return true;
                }
            }
        } catch (Exception e) {
            Log.e(TAG, "Error checking if device is Classic Bluetooth", e);
        }
        
        return false; // Default to BLE if we can't determine
    }

    private void discoverBluetoothPrintersInsecure(MethodCall call, Result result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity context is required for Bluetooth discovery", null);
            return;
        }

        // Check if discovery is already in progress
        if (isBleDiscoveryInProgress) {
            result.error("DISCOVERY_IN_PROGRESS", "Bluetooth discovery is already in progress. Please wait for it to complete.", null);
            return;
        }

        // Check for required permissions
        if (!hasBluetoothPermissions()) {
            result.error("MISSING_PERMISSIONS", 
                "Bluetooth permissions are required. Please grant BLUETOOTH_SCAN and location permissions.", 
                null);
            return;
        }

        executor.execute(() -> {
            try {
                isBleDiscoveryInProgress = true;
                Log.d(TAG, "Starting Insecure Classic Bluetooth discovery...");
                
                // Discover Classic Bluetooth paired devices using insecure connection
                List<Map<String, Object>> classicPrinters = discoverClassicBluetoothPrintersInsecure();
                
                mainHandler.post(() -> {
                    Log.d(TAG, "Insecure Classic Bluetooth discovery completed. Found " + classicPrinters.size() + " printers");
                    result.success(classicPrinters);
                });
                
            } catch (Exception e) {
                Log.e(TAG, "Insecure Classic Bluetooth discovery failed", e);
                mainHandler.post(() -> {
                    result.error("DISCOVERY_FAILED", e.getMessage(), null);
                });
            } finally {
                isBleDiscoveryInProgress = false;
            }
        });
    }

    private List<Map<String, Object>> discoverClassicBluetoothPrintersInsecure() {
        List<Map<String, Object>> classicPrinters = new ArrayList<>();
        
        try {
            BluetoothManager bluetoothManager = (BluetoothManager) context.getSystemService(Context.BLUETOOTH_SERVICE);
            BluetoothAdapter bluetoothAdapter = bluetoothManager.getAdapter();
            
            if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
                Log.d(TAG, "Bluetooth adapter not available or not enabled");
                return classicPrinters;
            }
            
            // Check permissions for getBondedDevices
            if (ActivityCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                Log.w(TAG, "Missing BLUETOOTH_CONNECT permission for Classic Bluetooth discovery");
                return classicPrinters;
            }
            
            // Get paired (bonded) devices
            Set<BluetoothDevice> pairedDevices = bluetoothAdapter.getBondedDevices();
            Log.d(TAG, "Found " + pairedDevices.size() + " paired Bluetooth devices");
            
            for (BluetoothDevice device : pairedDevices) {
                String deviceName = device.getName();
                String deviceAddress = device.getAddress();
                
                Log.d(TAG, "Checking paired device: " + deviceName + " (" + deviceAddress + ")");
                
                // Filter for Zebra printers (you can adjust this logic)
                if (deviceName != null && (deviceName.toLowerCase().contains("zebra") || 
                    deviceName.toLowerCase().contains("zd410") || 
                    deviceName.toLowerCase().contains("zd421"))) {
                    
                    Log.d(TAG, "Found Zebra Insecure Classic Bluetooth printer: " + deviceName);
                    
                    Map<String, Object> printerMap = new HashMap<>();
                    printerMap.put("friendlyName", deviceName);
                    printerMap.put("address", deviceAddress);
                    printerMap.put("interfaceType", "bluetooth");
                    printerMap.put("port", "0");
                    printerMap.put("serialNumber", "Unknown");
                    printerMap.put("manufacturer", "Zebra");
                    printerMap.put("connectionType", "insecure"); // Mark as insecure Bluetooth
                    
                    classicPrinters.add(printerMap);
                }
            }
            
            Log.d(TAG, "Insecure Classic Bluetooth discovery found " + classicPrinters.size() + " Zebra printers");
            
        } catch (Exception e) {
            Log.e(TAG, "Error during Insecure Classic Bluetooth discovery", e);
        }
        
        return classicPrinters;
    }

    private void discoverBluetoothNative(MethodCall call, Result result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity context is required for Bluetooth discovery", null);
            return;
        }

        // Check for required permissions
        if (!hasBluetoothPermissions()) {
            result.error("MISSING_PERMISSIONS", 
                "Bluetooth permissions are required. Please grant BLUETOOTH_SCAN and location permissions.", 
                null);
            return;
        }

        BluetoothManager bluetoothManager = (BluetoothManager) activity.getSystemService(Context.BLUETOOTH_SERVICE);
        if (bluetoothManager == null) {
            result.error("NO_BLUETOOTH", "Bluetooth is not available on this device", null);
            return;
        }

        BluetoothAdapter bluetoothAdapter = bluetoothManager.getAdapter();
        if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled()) {
            result.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled", null);
            return;
        }

        BluetoothLeScanner scanner = bluetoothAdapter.getBluetoothLeScanner();
        if (scanner == null) {
            result.error("NO_LE_SCANNER", "Bluetooth LE scanner not available", null);
            return;
        }
        
        Log.d(TAG, "Bluetooth adapter state: " + bluetoothAdapter.getState());
        Log.d(TAG, "Bluetooth adapter name: " + bluetoothAdapter.getName());
        Log.d(TAG, "BLE scanner available: " + (scanner != null));

        final List<Map<String, Object>> foundDevices = new ArrayList<>();
        final Handler timeoutHandler = new Handler(Looper.getMainLooper());

        ScanCallback scanCallback = new ScanCallback() {
            @Override
            public void onScanResult(int callbackType, ScanResult scanResult) {
                BluetoothDevice device = scanResult.getDevice();
                String deviceName = device.getName();
                String deviceAddress = device.getAddress();
                int rssi = scanResult.getRssi();
                
                // Log ALL devices for debugging
                Log.d(TAG, "Native BLE scan found device:");
                Log.d(TAG, "  Name: " + (deviceName != null ? deviceName : "Unknown"));
                Log.d(TAG, "  Address: " + deviceAddress);
                Log.d(TAG, "  RSSI: " + rssi);
                Log.d(TAG, "  Type: " + device.getType());
                Log.d(TAG, "  Bond State: " + device.getBondState());

                // Look for Zebra devices or devices with "ZD" in the name
                boolean isZebraDevice = (deviceName != null && 
                    (deviceName.toLowerCase().contains("zebra") || 
                     deviceName.toLowerCase().contains("zd") ||
                     deviceName.toLowerCase().contains("zq") ||
                     deviceName.toLowerCase().contains("zt")));

                // ADD ALL DEVICES for debugging - don't filter anything yet
                Map<String, Object> deviceMap = new HashMap<>();
                deviceMap.put("friendlyName", deviceName != null ? deviceName : "Unknown Device");
                deviceMap.put("address", deviceAddress);
                deviceMap.put("rssi", rssi);
                deviceMap.put("port", "0");
                deviceMap.put("interfaceType", "bluetooth");
                deviceMap.put("isZebra", isZebraDevice);
                deviceMap.put("serialNumber", "Unknown");
                deviceMap.put("deviceType", device.getType());
                deviceMap.put("bondState", device.getBondState());
                
                synchronized (foundDevices) {
                    // Avoid duplicates
                    boolean isDuplicate = false;
                        for (Map<String, Object> existing : foundDevices) {
                            if (deviceAddress.equals(existing.get("address"))) {
                                isDuplicate = true;
                                break;
                            }
                        }
                        if (!isDuplicate) {
                            foundDevices.add(deviceMap);
                            Log.d(TAG, "Added device to list: " + deviceName + " (Zebra: " + isZebraDevice + ")");
                        }
                    }
            }

            @Override
            public void onScanFailed(int errorCode) {
                Log.e(TAG, "Native BLE scan failed with error code: " + errorCode);
                mainHandler.post(() -> {
                    result.error("SCAN_FAILED", "Native BLE scan failed with error code: " + errorCode, null);
                });
            }
        };

        Log.d(TAG, "Starting native Android BLE scan for 15 seconds...");
        
        try {
            // Use aggressive scan settings
            ScanSettings.Builder settingsBuilder = new ScanSettings.Builder();
            settingsBuilder.setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY); // Most aggressive
            settingsBuilder.setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES);
            
            // Use empty filter list to scan for ALL devices
            List<ScanFilter> filters = new ArrayList<>();
            
            scanner.startScan(filters, settingsBuilder.build(), scanCallback);
            
            // Stop scanning after 15 seconds and return results
            timeoutHandler.postDelayed(() -> {
                try {
                    scanner.stopScan(scanCallback);
                } catch (Exception e) {
                    Log.w(TAG, "Error stopping native BLE scan", e);
                }
                
                synchronized (foundDevices) {
                    Log.d(TAG, "Native BLE scan completed. Found " + foundDevices.size() + " devices");
                    result.success(new ArrayList<>(foundDevices));
                }
            }, 15000);
            
        } catch (SecurityException e) {
            Log.e(TAG, "SecurityException during native BLE scan", e);
            result.error("PERMISSION_DENIED", "Permission denied for BLE scan: " + e.getMessage(), null);
        } catch (Exception e) {
            Log.e(TAG, "Exception during native BLE scan", e);
            result.error("SCAN_ERROR", "Error during BLE scan: " + e.getMessage(), null);
        }
    }

    private void testDirectBleConnection(MethodCall call, Result result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity context is required for BLE connection", null);
            return;
        }

        // Check for required permissions
        if (!hasBluetoothPermissions()) {
            result.error("MISSING_PERMISSIONS", 
                "Bluetooth permissions are required. Please grant BLUETOOTH_SCAN and location permissions.", 
                null);
            return;
        }

        // Get MAC address from call arguments 
        @SuppressWarnings("unchecked")
        Map<String, Object> args = (Map<String, Object>) call.arguments;
        String macAddress = args != null ? (String) args.get("macAddress") : null;
        
        if (macAddress == null || macAddress.trim().isEmpty()) {
            result.error("MISSING_MAC_ADDRESS", "MAC address is required for direct BLE connection", null);
            return;
        }
        
        Log.d(TAG, "Testing direct BLE connection to: " + macAddress);

        executor.execute(() -> {
            BluetoothLeConnection bleConnection = null;
            ZebraPrinter printer = null;
            
            try {
                Log.d(TAG, "Creating BluetoothLeConnection for MAC: " + macAddress);
                bleConnection = new BluetoothLeConnection(macAddress);
                
                Log.d(TAG, "Setting context for BLE connection...");
                bleConnection.setContext(activity);
                
                Log.d(TAG, "Attempting to open BLE connection...");
                bleConnection.open();
                
                if (bleConnection.isConnected()) {
                    Log.d(TAG, "BLE connection successful! Testing printer communication...");
                    
                    // Try to create a printer instance
                    printer = ZebraPrinterFactory.getInstance(bleConnection);
                    
                    if (printer != null) {
                        Log.d(TAG, "Successfully created ZebraPrinter instance via BLE!");
                        
                        // Try to get printer status
                        try {
                            String status = printer.getCurrentStatus().toString();
                            Log.d(TAG, "Printer status via BLE: " + status);
                            
                            // Create success result with printer info
                            Map<String, Object> printerInfo = new HashMap<>();
                            printerInfo.put("friendlyName", "ZD421 (Direct BLE)");
                            printerInfo.put("address", macAddress);
                            printerInfo.put("port", 0); // Use integer 0, not string "0"
                            printerInfo.put("interfaceType", "bluetooth"); // Use "bluetooth" to match connect() method
                            printerInfo.put("status", status);
                            printerInfo.put("serialNumber", "Unknown");
                            
                            List<Map<String, Object>> printers = new ArrayList<>();
                            printers.add(printerInfo);
                            
                            mainHandler.post(() -> {
                                result.success(printers);
                            });
                            
                        } catch (Exception statusEx) {
                            Log.w(TAG, "Could not get printer status via BLE", statusEx);
                            
                            // Still report success since connection worked
                            Map<String, Object> printerInfo = new HashMap<>();
                            printerInfo.put("friendlyName", "ZD421 (Direct BLE - Limited)");
                            printerInfo.put("address", macAddress);
                            printerInfo.put("port", 0); // Use integer 0, not string "0"
                            printerInfo.put("interfaceType", "bluetooth"); // Use "bluetooth" to match connect() method
                            printerInfo.put("status", "Connected but status unavailable");
                            printerInfo.put("serialNumber", "Unknown");
                            
                            List<Map<String, Object>> printers = new ArrayList<>();
                            printers.add(printerInfo);
                            
                            mainHandler.post(() -> {
                                result.success(printers);
                            });
                        }
                    } else {
                        Log.w(TAG, "BLE connection successful but could not create printer instance");
                        mainHandler.post(() -> {
                            result.error("PRINTER_CREATION_FAILED", 
                                "Connected via BLE but could not create printer instance", null);
                        });
                    }
                } else {
                    Log.w(TAG, "BLE connection failed - not connected after open()");
                    mainHandler.post(() -> {
                        result.error("CONNECTION_FAILED", 
                            "Could not establish BLE connection to " + macAddress, null);
                    });
                }
                
            } catch (Exception e) {
                Log.e(TAG, "Exception during direct BLE connection test", e);
                mainHandler.post(() -> {
                    result.error("BLE_CONNECTION_ERROR", 
                        "BLE connection failed: " + e.getMessage(), null);
                });
            } finally {
                // Clean up connections
                try {
                    if (bleConnection != null && bleConnection.isConnected()) {
                        bleConnection.close();
                        Log.d(TAG, "Closed BLE connection");
                    }
                } catch (Exception closeEx) {
                    Log.w(TAG, "Error closing BLE connection", closeEx);
                }
            }
        });
    }

    private void discoverUsbPrinters(MethodCall call, Result result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity context is required for USB discovery", null);
            return;
        }

        // Check if discovery is already in progress
        if (isUsbDiscoveryInProgress) {
            result.error("DISCOVERY_IN_PROGRESS", "USB discovery is already in progress. Please wait for it to complete.", null);
            return;
        }

        Log.d(TAG, "Starting USB printer discovery...");

        executor.execute(() -> {
            try {
                isUsbDiscoveryInProgress = true;
                
                final List<DiscoveredPrinter> discoveredPrinters = new ArrayList<>();
                final Object discoveryLock = new Object();
                final boolean[] discoveryComplete = {false};

                DiscoveryHandler discoveryHandler = new DiscoveryHandler() {
                    @Override
                    public void foundPrinter(DiscoveredPrinter discoveredPrinter) {
                        Log.d(TAG, "Found USB printer!");
                        
                        // Check if this is specifically a USB printer
                        if (discoveredPrinter instanceof DiscoveredPrinterUsb) {
                            DiscoveredPrinterUsb usbPrinter = (DiscoveredPrinterUsb) discoveredPrinter;
                            Log.d(TAG, "  USB Device: " + usbPrinter.device.getDeviceName());
                            Log.d(TAG, "  USB Product ID: " + usbPrinter.device.getProductId());
                            Log.d(TAG, "  USB Vendor ID: " + usbPrinter.device.getVendorId());
                        }
                        
                        Map<String, String> discoveryData = discoveredPrinter.getDiscoveryDataMap();
                        Log.d(TAG, "  FRIENDLY_NAME: " + discoveryData.get("FRIENDLY_NAME"));
                        Log.d(TAG, "  All discovery data: " + discoveryData.toString());

                        synchronized (discoveredPrinters) {
                            discoveredPrinters.add(discoveredPrinter);
                        }
                    }

                    @Override
                    public void discoveryFinished() {
                        Log.d(TAG, "USB discovery finished callback received");
                        synchronized (discoveryLock) {
                            discoveryComplete[0] = true;
                            discoveryLock.notify();
                        }
                    }

                    @Override
                    public void discoveryError(String message) {
                        Log.e(TAG, "USB discovery error callback: " + message);
                        synchronized (discoveryLock) {
                            discoveryComplete[0] = true;
                            discoveryLock.notify();
                        }
                    }
                };

                Log.d(TAG, "Starting UsbDiscoverer.findPrinters...");
                // Use the application context for USB discovery
                UsbDiscoverer.findPrinters(activity.getApplicationContext(), discoveryHandler);
                
                // Wait for discovery to complete with timeout
                synchronized (discoveryLock) {
                    while (!discoveryComplete[0]) {
                        discoveryLock.wait(10000); // 10 second timeout for USB discovery
                        break; // Exit if timeout
                    }
                }
                
                List<Map<String, Object>> printers = new ArrayList<>();
                synchronized (discoveredPrinters) {
                    for (DiscoveredPrinter printer : discoveredPrinters) {
                        Map<String, Object> printerMap = new HashMap<>();
                        
                        // Handle USB printers specifically
                        if (printer instanceof DiscoveredPrinterUsb) {
                            DiscoveredPrinterUsb usbPrinter = (DiscoveredPrinterUsb) printer;
                            printerMap.put("friendlyName", "USB Printer (" + usbPrinter.device.getProductId() + ")");
                            printerMap.put("address", usbPrinter.device.getDeviceName());
                            printerMap.put("interfaceType", "usb");
                            printerMap.put("productId", usbPrinter.device.getProductId());
                            printerMap.put("vendorId", usbPrinter.device.getVendorId());
                        } else {
                            // Fallback to discovery data
                            printerMap.put("friendlyName", printer.getDiscoveryDataMap().get("FRIENDLY_NAME"));
                            printerMap.put("address", "Unknown USB Device");
                            printerMap.put("interfaceType", "usb");
                        }
                        
                        printerMap.put("port", 0);
                        printerMap.put("serialNumber", printer.getDiscoveryDataMap().get("SERIAL_NUMBER"));
                        printers.add(printerMap);
                    }
                }

                mainHandler.post(() -> {
                    Log.d(TAG, "USB discovery completed. Found " + printers.size() + " printers");
                    result.success(printers);
                });
                
            } catch (Exception e) {
                Log.e(TAG, "USB discovery failed", e);
                mainHandler.post(() -> {
                    result.error("DISCOVERY_FAILED", e.getMessage(), null);
                });
            } finally {
                isUsbDiscoveryInProgress = false;
            }
        });
    }

    private boolean hasBluetoothPermissions() {
        if (activity == null) {
            return false;
        }
        
        // Check basic location permissions (required for all Android versions)
        boolean hasLocationPermission = 
            ContextCompat.checkSelfPermission(activity, android.Manifest.permission.ACCESS_COARSE_LOCATION) 
                == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(activity, android.Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED;

        // For Android 12+ (API 31+), also check BLUETOOTH_SCAN permission
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            boolean hasBluetoothScan = 
                ContextCompat.checkSelfPermission(activity, android.Manifest.permission.BLUETOOTH_SCAN) 
                    == PackageManager.PERMISSION_GRANTED;
            return hasLocationPermission && hasBluetoothScan;
        }
        
        // For older Android versions, check legacy Bluetooth permissions
        boolean hasBluetoothPermission = 
            ContextCompat.checkSelfPermission(activity, android.Manifest.permission.BLUETOOTH) 
                == PackageManager.PERMISSION_GRANTED;
        boolean hasBluetoothAdmin = 
            ContextCompat.checkSelfPermission(activity, android.Manifest.permission.BLUETOOTH_ADMIN) 
                == PackageManager.PERMISSION_GRANTED;
                
        return hasLocationPermission && hasBluetoothPermission && hasBluetoothAdmin;
    }

    private void requestBluetoothPermissions(Result result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity context is required for permission requests", null);
            return;
        }

        // Check if permissions are already granted
        if (hasBluetoothPermissions()) {
            result.success(true);
            return;
        }

        // For now, just return a message asking user to grant permissions manually
        // A full implementation would use ActivityCompat.requestPermissions()
        result.error("PERMISSION_DENIED", 
            "Please grant Bluetooth and location permissions in system settings", null);
    }

    private void requestUsbPermissions(MethodCall call, Result result) {
        if (activity == null) {
            result.error("NO_ACTIVITY", "Activity context is required for USB permission requests", null);
            return;
        }

        String deviceName = call.hasArgument("deviceName") ? (String) call.argument("deviceName") : null;
        
        if (deviceName == null) {
            result.error("MISSING_ARGUMENT", "Device name is required for USB permission request", null);
            return;
        }

        Log.d(TAG, "Requesting USB permission for device: " + deviceName);

        executor.execute(() -> {
            try {
                UsbManager usbManager = (UsbManager) activity.getSystemService(Context.USB_SERVICE);
                if (usbManager == null) {
                    mainHandler.post(() -> {
                        result.error("NO_USB_SERVICE", "USB service not available", null);
                    });
                    return;
                }

                // Find the USB device
                UsbDevice targetDevice = null;
                for (UsbDevice device : usbManager.getDeviceList().values()) {
                    if (deviceName.equals(device.getDeviceName()) || 
                        deviceName.contains(String.valueOf(device.getProductId()))) {
                        targetDevice = device;
                        break;
                    }
                }

                final UsbDevice finalTargetDevice = targetDevice; // Make it final for lambda usage

                if (finalTargetDevice == null) {
                    mainHandler.post(() -> {
                        result.error("DEVICE_NOT_FOUND", "USB device not found: " + deviceName, null);
                    });
                    return;
                }

                // Check if permission is already granted
                if (usbManager.hasPermission(finalTargetDevice)) {
                    mainHandler.post(() -> {
                        result.success(true);
                    });
                    return;
                }

                // For now, inform user that USB permission needs to be granted manually
                // A full implementation would use PendingIntent and BroadcastReceiver
                mainHandler.post(() -> {
                    // Try to request permission using the system dialog
                    try {
                        String usbPermissionAction = "com.zebra.zebra_printer_android.USB_PERMISSION";
                        Intent intent = new Intent(usbPermissionAction);
                        PendingIntent permissionIntent = PendingIntent.getBroadcast(
                            activity, 
                            0, 
                            intent, 
                            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
                        );
                        
                        usbManager.requestPermission(finalTargetDevice, permissionIntent);
                        
                        // Since we can't wait for the broadcast receiver in this simple implementation,
                        // we'll inform the user that permission was requested
                        result.success(false); // Permission requested, but not yet granted
                        
                    } catch (Exception e) {
                        result.error("PERMISSION_REQUEST_FAILED", 
                            "Failed to request USB permission: " + e.getMessage(), null);
                    }
                });

            } catch (Exception e) {
                Log.e(TAG, "Error requesting USB permission", e);
                mainHandler.post(() -> {
                    result.error("PERMISSION_ERROR", "Error requesting USB permission: " + e.getMessage(), null);
                });
            }
        });
    }

    private void discoverPrinters(MethodCall call, Result result) {
        executor.execute(() -> {
            try {
                Log.d(TAG, "Starting local broadcast discovery");
                
                final List<DiscoveredPrinter> discoveredPrinters = new ArrayList<>();
                final Object discoveryLock = new Object();
                final boolean[] discoveryComplete = {false};
                
                DiscoveryHandler discoveryHandler = new DiscoveryHandler() {
                    @Override
                    public void foundPrinter(DiscoveredPrinter printer) {
                        synchronized (discoveredPrinters) {
                            discoveredPrinters.add(printer);
                            Log.d(TAG, "Found printer: " + getPrinterAddress(printer));
                        }
                    }

                    @Override
                    public void discoveryFinished() {
                        Log.d(TAG, "Discovery finished");
                        synchronized (discoveryLock) {
                            discoveryComplete[0] = true;
                            discoveryLock.notify();
                        }
                    }

                    @Override
                    public void discoveryError(String error) {
                        Log.e(TAG, "Discovery error: " + error);
                        synchronized (discoveryLock) {
                            discoveryComplete[0] = true;
                            discoveryLock.notify();
                        }
                    }
                };

                // Perform local broadcast discovery
                NetworkDiscoverer.localBroadcast(discoveryHandler);
                
                // Wait for discovery to complete
                synchronized (discoveryLock) {
                    while (!discoveryComplete[0]) {
                        discoveryLock.wait(10000); // 10 second timeout
                        break; // Exit if timeout
                    }
                }

                List<Map<String, Object>> printers = new ArrayList<>();
                synchronized (discoveredPrinters) {
                    for (DiscoveredPrinter printer : discoveredPrinters) {
                        Map<String, Object> printerMap = new HashMap<>();
                        printerMap.put("friendlyName", printer.getDiscoveryDataMap().get("FRIENDLY_NAME"));
                        printerMap.put("address", getPrinterAddress(printer));
                        printerMap.put("port", "9100");
                        printerMap.put("interfaceType", "tcp");
                        printerMap.put("serialNumber", printer.getDiscoveryDataMap().get("SERIAL_NUMBER"));
                        printers.add(printerMap);
                    }
                }

                mainHandler.post(() -> {
                    Log.d(TAG, "Local broadcast discovery completed. Found " + printers.size() + " printers");
                    result.success(printers);
                });
                
            } catch (Exception e) {
                Log.e(TAG, "Local broadcast discovery failed", e);
                mainHandler.post(() -> {
                    result.error("DISCOVERY_FAILED", e.getMessage(), null);
                });
            }
        });
    }

    private void discoverSubnetSearch(MethodCall call, Result result) {
        String subnetRange = call.argument("subnetRange");
        if (subnetRange == null) {
            result.error("MISSING_ARGUMENT", "Subnet range is required", null);
            return;
        }

        executor.execute(() -> {
            try {
                Log.d(TAG, "Starting subnet search for range: " + subnetRange);
                
                final List<DiscoveredPrinter> discoveredPrinters = new ArrayList<>();
                final Object discoveryLock = new Object();
                final boolean[] discoveryComplete = {false};
                
                DiscoveryHandler discoveryHandler = new DiscoveryHandler() {
                    @Override
                    public void foundPrinter(DiscoveredPrinter printer) {
                        synchronized (discoveredPrinters) {
                            discoveredPrinters.add(printer);
                            Log.d(TAG, "Found printer: " + getPrinterAddress(printer));
                        }
                    }

                    @Override
                    public void discoveryFinished() {
                        Log.d(TAG, "Subnet discovery finished");
                        synchronized (discoveryLock) {
                            discoveryComplete[0] = true;
                            discoveryLock.notify();
                        }
                    }

                    @Override
                    public void discoveryError(String error) {
                        Log.e(TAG, "Subnet discovery error: " + error);
                        synchronized (discoveryLock) {
                            discoveryComplete[0] = true;
                            discoveryLock.notify();
                        }
                    }
                };

                NetworkDiscoverer.subnetSearch(discoveryHandler, subnetRange);
                
                // Wait for discovery to complete
                synchronized (discoveryLock) {
                    while (!discoveryComplete[0]) {
                        discoveryLock.wait(20000); // 20 second timeout for subnet search
                        break; // Exit if timeout
                    }
                }

                List<Map<String, Object>> printers = new ArrayList<>();
                synchronized (discoveredPrinters) {
                    for (DiscoveredPrinter printer : discoveredPrinters) {
                        Map<String, Object> printerMap = new HashMap<>();
                        printerMap.put("friendlyName", printer.getDiscoveryDataMap().get("FRIENDLY_NAME"));
                        printerMap.put("address", getPrinterAddress(printer));
                        printerMap.put("port", "9100");
                        printerMap.put("interfaceType", "tcp");
                        printerMap.put("serialNumber", printer.getDiscoveryDataMap().get("SERIAL_NUMBER"));
                        printers.add(printerMap);
                    }
                }

                mainHandler.post(() -> {
                    Log.d(TAG, "Subnet search completed. Found " + printers.size() + " printers");
                    result.success(printers);
                });
                
            } catch (Exception e) {
                Log.e(TAG, "Subnet search failed", e);
                mainHandler.post(() -> {
                    result.error("DISCOVERY_FAILED", e.getMessage(), null);
                });
            }
        });
    }

    private void isConnected(Result result) {
        boolean connected = activeConnection != null && activeConnection.isConnected();
        result.success(connected);
    }

    private void discoverMulticastPrinters(MethodCall call, Result result) {
        Integer hops = call.argument("hops");
        if (hops == null) {
            hops = 3; // Default hops
        }

        final int finalHops = hops;
        
        executor.execute(() -> {
            try {
                Log.d(TAG, "Starting multicast discovery with " + finalHops + " hops");
                
                final List<DiscoveredPrinter> discoveredPrinters = new ArrayList<>();
                final Object discoveryLock = new Object();
                final boolean[] discoveryComplete = {false};
                
                DiscoveryHandler discoveryHandler = new DiscoveryHandler() {
                    @Override
                    public void foundPrinter(DiscoveredPrinter printer) {
                        synchronized (discoveredPrinters) {
                            discoveredPrinters.add(printer);
                            Log.d(TAG, "Found printer: " + getPrinterAddress(printer));
                        }
                    }

                    @Override
                    public void discoveryFinished() {
                        Log.d(TAG, "Multicast discovery finished");
                        synchronized (discoveryLock) {
                            discoveryComplete[0] = true;
                            discoveryLock.notify();
                        }
                    }

                    @Override
                    public void discoveryError(String error) {
                        Log.e(TAG, "Multicast discovery error: " + error);
                        synchronized (discoveryLock) {
                            discoveryComplete[0] = true;
                            discoveryLock.notify();
                        }
                    }
                };

                // Use multicast discovery with multicast lock
                WifiManager wifi = (WifiManager) context.getSystemService(Context.WIFI_SERVICE);
                WifiManager.MulticastLock lock = wifi.createMulticastLock("zebra_multicast_discovery_lock");
                lock.setReferenceCounted(true);
                lock.acquire();
                
                try {
                    NetworkDiscoverer.multicast(discoveryHandler, finalHops);
                    
                    // Wait for discovery to complete
                    synchronized (discoveryLock) {
                        while (!discoveryComplete[0]) {
                            discoveryLock.wait(10000); // 10 second timeout for multicast
                            break; // Exit if timeout
                        }
                    }
                } finally {
                    lock.release();
                }

                List<Map<String, Object>> printers = new ArrayList<>();
                synchronized (discoveredPrinters) {
                    for (DiscoveredPrinter printer : discoveredPrinters) {
                        Map<String, Object> printerMap = new HashMap<>();
                        printerMap.put("friendlyName", printer.getDiscoveryDataMap().get("FRIENDLY_NAME"));
                        printerMap.put("address", getPrinterAddress(printer));
                        printerMap.put("port", "9100");
                        printerMap.put("interfaceType", "tcp");
                        printerMap.put("serialNumber", printer.getDiscoveryDataMap().get("SERIAL_NUMBER"));
                        printers.add(printerMap);
                    }
                }

                mainHandler.post(() -> {
                    Log.d(TAG, "Multicast discovery completed. Found " + printers.size() + " printers");
                    result.success(printers);
                });
                
            } catch (Exception e) {
                Log.e(TAG, "Multicast discovery failed", e);
                mainHandler.post(() -> {
                    result.error("DISCOVERY_FAILED", e.getMessage(), null);
                });
            }
        });
    }

    private void setupUsbPermissionReceiver() {
        if (usbPermissionReceiver == null && activity != null) {
            usbPermissionReceiver = new BroadcastReceiver() {
                @Override
                public void onReceive(Context context, Intent intent) {
                    String action = intent.getAction();
                    if (USB_PERMISSION_ACTION.equals(action)) {
                        boolean granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false);
                        if (usbPermissionFuture != null) {
                            usbPermissionFuture.complete(granted);
                        }
                    }
                }
            };
            
            IntentFilter filter = new IntentFilter(USB_PERMISSION_ACTION);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity.registerReceiver(usbPermissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED);
            } else {
                activity.registerReceiver(usbPermissionReceiver, filter);
            }
        }
    }
    
    private void cleanupUsbPermissionReceiver() {
        if (usbPermissionReceiver != null && activity != null) {
            try {
                activity.unregisterReceiver(usbPermissionReceiver);
            } catch (Exception e) {
                Log.e(TAG, "Error unregistering USB permission receiver", e);
            }
            usbPermissionReceiver = null;
        }
        
        if (usbPermissionFuture != null && !usbPermissionFuture.isDone()) {
            usbPermissionFuture.complete(false);
        }
    }
    
    private CompletableFuture<Boolean> requestUsbPermissionAsync(UsbDevice device) {
        UsbManager usbManager = (UsbManager) activity.getSystemService(Context.USB_SERVICE);
        
        if (usbManager.hasPermission(device)) {
            return CompletableFuture.completedFuture(true);
        }
        
        usbPermissionFuture = new CompletableFuture<>();
        
        Intent intent = new Intent(USB_PERMISSION_ACTION);
        PendingIntent permissionIntent = PendingIntent.getBroadcast(
            activity, 
            0, 
            intent, 
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );
        
        usbManager.requestPermission(device, permissionIntent);
        return usbPermissionFuture;
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        
        // Clean up connections
        if (activeConnection != null && activeConnection.isConnected()) {
            try {
                activeConnection.close();
            } catch (Exception e) {
                Log.e(TAG, "Error closing connection during cleanup", e);
            }
        }
        
        executor.shutdown();
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        setupUsbPermissionReceiver();
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        cleanupUsbPermissionReceiver();
        activity = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        activity = binding.getActivity();
        setupUsbPermissionReceiver();
    }

    @Override
    public void onDetachedFromActivity() {
        cleanupUsbPermissionReceiver();
        activity = null;
    }

    private void getSgdParameter(MethodCall call, Result result) {
        if (activeConnection == null || !activeConnection.isConnected()) {
            result.error("NOT_CONNECTED", "No active printer connection", null);
            return;
        }

        String parameter = call.argument("parameter");
        if (parameter == null || parameter.trim().isEmpty()) {
            result.error("INVALID_ARGUMENT", "Parameter is required", null);
            return;
        }

        executor.execute(() -> {
            try {
                Log.d(TAG, "Getting SGD parameter: " + parameter);
                
                // Use ZPL getvar command for consistency with iOS
                String zplCommand = String.format("! U1 getvar \"%s\"\r\n", parameter);
                Log.d(TAG, "Sending ZPL getvar command: " + zplCommand.replace("\r\n", "\\r\\n"));
                
                // Send the command
                activeConnection.write(zplCommand.getBytes());
                
                // Wait for response
                Thread.sleep(1000);
                
                // Try to read response
                String response = "";
                try {
                    ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
                    activeConnection.read(outputStream);
                    byte[] responseBytes = outputStream.toByteArray();
                    if (responseBytes.length > 0) {
                        response = new String(responseBytes).trim();
                        response = response.replaceAll("\"", ""); // Remove quotes
                        response = response.replace("\0", ""); // Remove null characters
                        Log.d(TAG, "Got SGD parameter response: " + response);
                    }
                    outputStream.close();
                } catch (Exception e) {
                    Log.d(TAG, "Error reading response: " + e.getMessage());
                    response = "";
                }

                final String finalResponse = response;
                new Handler(Looper.getMainLooper()).post(() -> {
                    result.success(finalResponse);
                });

            } catch (Exception e) {
                Log.e(TAG, "Error getting SGD parameter", e);
                new Handler(Looper.getMainLooper()).post(() -> {
                    result.error("GET_FAILED", "Failed to get SGD parameter: " + e.getMessage(), null);
                });
            }
        });
    }

    private void setSgdParameter(MethodCall call, Result result) {
        if (activeConnection == null || !activeConnection.isConnected()) {
            result.error("NOT_CONNECTED", "No active printer connection", null);
            return;
        }

        String parameter = call.argument("parameter");
        String value = call.argument("value");
        
        if (parameter == null || parameter.trim().isEmpty()) {
            result.error("INVALID_ARGUMENT", "Parameter is required", null);
            return;
        }
        
        if (value == null) {
            result.error("INVALID_ARGUMENT", "Value is required", null);
            return;
        }

        executor.execute(() -> {
            try {
                Log.d(TAG, "Setting SGD parameter " + parameter + " to " + value);
                
                // Use ZPL setvar command for consistency with iOS
                String zplCommand = String.format("! U1 setvar \"%s\" \"%s\"\r\n", parameter, value);
                Log.d(TAG, "Sending ZPL setvar command: " + zplCommand.replace("\r\n", "\\r\\n"));
                
                activeConnection.write(zplCommand.getBytes());
                
                // Wait for command to be processed
                Thread.sleep(1000);
                
                Log.d(TAG, "Successfully sent SGD setvar command");
                
                new Handler(Looper.getMainLooper()).post(() -> {
                    result.success(null);
                });

            } catch (Exception e) {
                Log.e(TAG, "Error setting SGD parameter", e);
                new Handler(Looper.getMainLooper()).post(() -> {
                    result.error("SET_FAILED", "Failed to set SGD parameter: " + e.getMessage(), null);
                });
            }
        });
    }

    private void getPrinterDimensions(Result result) {
        if (activeConnection == null || !activeConnection.isConnected()) {
            result.error("NOT_CONNECTED", "No active printer connection", null);
            return;
        }

        executor.execute(() -> {
            try {
                Log.d(TAG, "Getting printer dimensions");
                java.util.Map<String, Integer> dimensions = new java.util.HashMap<>();
                
                // Initialize default values
                dimensions.put("labelLengthInDots", 0);
                dimensions.put("printWidthInDots", 0);
                dimensions.put("dpi", 0);
                dimensions.put("maxPrintWidthInDots", 0);
                dimensions.put("mediaWidthInDots", 0);
                
                // Get ZebraPrinter instance for status queries
                ZebraPrinter zebraPrinter = ZebraPrinterFactory.getInstance(activeConnection);
                if (zebraPrinter != null) {
                    // Get printer status which includes label length in dots
                    PrinterStatus status = zebraPrinter.getCurrentStatus();
                    if (status != null) {
                        dimensions.put("labelLengthInDots", status.labelLengthInDots);
                        Log.d(TAG, "Label length in dots: " + status.labelLengthInDots);
                    }
                }
                
                // Use helper method to get SGD values
                String printWidth = getSgdValue("ezpl.print_width");
                if (printWidth != null && !printWidth.isEmpty()) {
                    try {
                        dimensions.put("printWidthInDots", Integer.parseInt(printWidth));
                        Log.d(TAG, "Print width in dots: " + printWidth);
                    } catch (NumberFormatException e) {
                        Log.d(TAG, "Invalid print width value: " + printWidth);
                    }
                }
                
                // Get printer DPI using head resolution
                String dpi = getSgdValue("head.resolution.in_dpi");
                if (dpi != null && !dpi.isEmpty()) {
                    try {
                        dimensions.put("dpi", Integer.parseInt(dpi));
                        Log.d(TAG, "Printer DPI: " + dpi);
                    } catch (NumberFormatException e) {
                        Log.d(TAG, "Invalid DPI value: " + dpi);
                    }
                } else {
                    // Fallback to device.resolution
                    String fallbackDpi = getSgdValue("device.resolution");
                    if (fallbackDpi != null && !fallbackDpi.isEmpty()) {
                        try {
                            dimensions.put("dpi", Integer.parseInt(fallbackDpi));
                            Log.d(TAG, "Fallback DPI: " + fallbackDpi);
                        } catch (NumberFormatException e) {
                            Log.d(TAG, "Invalid fallback DPI value: " + fallbackDpi);
                        }
                    }
                }
                
                String maxPrintWidth = getSgdValue("ezpl.max_print_width");
                if (maxPrintWidth != null && !maxPrintWidth.isEmpty()) {
                    try {
                        dimensions.put("maxPrintWidthInDots", Integer.parseInt(maxPrintWidth));
                        Log.d(TAG, "Max print width in dots: " + maxPrintWidth);
                    } catch (NumberFormatException e) {
                        Log.d(TAG, "Invalid max print width value: " + maxPrintWidth);
                    }
                }
                
                String mediaWidth = getSgdValue("ezpl.media_width");
                if (mediaWidth != null && !mediaWidth.isEmpty()) {
                    try {
                        dimensions.put("mediaWidthInDots", Integer.parseInt(mediaWidth));
                        Log.d(TAG, "Media width in dots: " + mediaWidth);
                    } catch (NumberFormatException e) {
                        Log.d(TAG, "Invalid media width value: " + mediaWidth);
                    }
                }
                
                Log.d(TAG, "Returning printer dimensions: " + dimensions);
                
                new Handler(Looper.getMainLooper()).post(() -> {
                    result.success(dimensions);
                });

            } catch (Exception e) {
                Log.e(TAG, "Error getting printer dimensions", e);
                new Handler(Looper.getMainLooper()).post(() -> {
                    result.error("QUERY_FAILED", "Failed to query printer dimensions: " + e.getMessage(), null);
                });
            }
        });
    }

    // Helper method to get SGD values using ZPL commands
    private String getSgdValue(String parameter) {
        try {
            String zplCommand = String.format("! U1 getvar \"%s\"\r\n", parameter);
            activeConnection.write(zplCommand.getBytes());
            Thread.sleep(500);
            
            ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
            activeConnection.read(outputStream);
            byte[] responseBytes = outputStream.toByteArray();
            String response = "";
            if (responseBytes.length > 0) {
                response = new String(responseBytes).trim();
                response = response.replaceAll("\"", "");
                response = response.replace("\0", "");
            }
            outputStream.close();
            
            return response.isEmpty() ? null : response;
        } catch (Exception e) {
            Log.d(TAG, "Failed to get SGD value for " + parameter + ": " + e.getMessage());
            return null;
        }
    }

    private void setLabelLength(MethodCall call, Result result) {
        if (activeConnection == null || !activeConnection.isConnected()) {
            result.error("NOT_CONNECTED", "No active printer connection", null);
            return;
        }

        Integer lengthInDots = call.argument("lengthInDots");
        if (lengthInDots == null || lengthInDots <= 0) {
            result.error("INVALID_ARGUMENT", "Valid lengthInDots is required", null);
            return;
        }

        executor.execute(() -> {
            try {
                Log.d(TAG, "Setting label length to " + lengthInDots + " dots");
                
                // Use ZPL ^LL command to set label length for immediate effect
                String zplCommand = String.format("^XA^LL%d^XZ\r\n", lengthInDots);
                Log.d(TAG, "Sending ZPL label length command: " + zplCommand.replace("\r\n", "\\r\\n"));
                
                activeConnection.write(zplCommand.getBytes());
                
                // Wait for command to be processed
                Thread.sleep(500);
                
                Log.d(TAG, "Successfully set label length to " + lengthInDots + " dots");
                
                new Handler(Looper.getMainLooper()).post(() -> {
                    result.success(null);
                });

            } catch (Exception e) {
                Log.e(TAG, "Error setting label length", e);
                new Handler(Looper.getMainLooper()).post(() -> {
                    result.error("SET_FAILED", "Failed to set label length: " + e.getMessage(), null);
                });
            }
        });
    }
}