package com.example.star_printer_android

import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import com.starmicronics.stario10.*
import com.starmicronics.stario10.starxpandcommand.*
import com.starmicronics.stario10.starxpandcommand.printer.*
import com.starmicronics.stario10.starxpandcommand.drawer.*
import kotlinx.coroutines.*
import kotlinx.coroutines.CompletableDeferred
import android.hardware.usb.UsbManager
import android.content.Context
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat
import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint

/** StarPrinterPlugin */
class StarPrinterPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private var activity: Activity? = null
  private var printer: StarPrinter? = null
  private var discoveryManager: StarDeviceDiscoveryManager? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "star_printer")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "discoverPrinters" -> discoverPrinters(result)
      "discoverBluetoothPrinters" -> discoverBluetoothPrinters(result)
      "usbDiagnostics" -> runUsbDiagnostics(result)
      "connect" -> connectToPrinter(call, result)
      "disconnect" -> disconnectFromPrinter(result)
      "printReceipt" -> printReceipt(call, result)
      "getStatus" -> getStatus(result)
      "openCashDrawer" -> openCashDrawer(result)
      "isConnected" -> isConnected(result)
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    discoveryManager?.stopDiscovery()
  }

  private fun discoverPrinters(result: Result) {
    CoroutineScope(Dispatchers.IO).launch {
      try {
        // Check USB OTG support and connected devices first
        val usbManager = context.getSystemService(android.content.Context.USB_SERVICE) as UsbManager
        val hasUsbHost = context.packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_USB_HOST)
        
        println("StarPrinter: USB Host (OTG) support: $hasUsbHost")
        println("StarPrinter: Connected USB devices: ${usbManager.deviceList.size}")
        
        // List all connected USB devices for debugging
        usbManager.deviceList.forEach { (deviceName, device) ->
          println("StarPrinter: USB Device - Name: $deviceName")
          println("StarPrinter: USB Device - VendorId: ${device.vendorId} (0x${device.vendorId.toString(16)})")
          println("StarPrinter: USB Device - ProductId: ${device.productId} (0x${device.productId.toString(16)})")
          println("StarPrinter: USB Device - Manufacturer: ${device.manufacturerName}")
          println("StarPrinter: USB Device - Product: ${device.productName}")
          
          // Check if this matches TSP100 USB IDs (Star Micronics vendor ID: 0x0519 = 1305)
          if (device.vendorId == 1305) {
            println("StarPrinter: *** STAR MICRONICS DEVICE DETECTED! ***")
            println("StarPrinter: This appears to be a Star printer via USB")
          }
        }
        
        // Check Bluetooth permissions and availability
        if (!hasBluetoothPermissions()) {
          CoroutineScope(Dispatchers.Main).launch {
            result.error("BLUETOOTH_PERMISSION_DENIED", "Bluetooth permissions not granted", null)
          }
          return@launch
        }

        if (!isBluetoothAvailable()) {
          CoroutineScope(Dispatchers.Main).launch {
            result.error("BLUETOOTH_UNAVAILABLE", "Bluetooth is not available or enabled", null)
          }
          return@launch
        }

        val printers = mutableListOf<String>()
        
        // Optimized discovery strategy: try combined first for speed, fallback to individual
        val interfaceTypeSets = listOf(
          // Try combined discovery FIRST (most efficient - gets everything in one shot)
          listOf(InterfaceType.Lan, InterfaceType.Bluetooth, InterfaceType.Usb),
          // Individual fallbacks only if combined misses something (unlikely)
          listOf(InterfaceType.Lan),
          listOf(InterfaceType.Bluetooth),
          listOf(InterfaceType.Usb),
          // Bluetooth LE only as last resort with minimal timeout
          listOf(InterfaceType.BluetoothLE)
        )
        
        // Run optimized discovery with early exit logic
        val allDiscoveredPrinters = mutableSetOf<String>()
        
        for ((index, interfaceTypes) in interfaceTypeSets.withIndex()) {
          val isCombined = interfaceTypes.size > 1 && interfaceTypes.contains(InterfaceType.Lan) && interfaceTypes.contains(InterfaceType.Bluetooth)
          val isBLEOnly = interfaceTypes.size == 1 && interfaceTypes.first() == InterfaceType.BluetoothLE
          
          // Early exit optimization: if combined discovery found printers, skip individual fallbacks
          if (index > 0 && !isBLEOnly && allDiscoveredPrinters.isNotEmpty()) {
            println("StarPrinter: Skipping individual discovery for $interfaceTypes - combined discovery already found ${allDiscoveredPrinters.size} printers")
            continue
          }
          
          // Skip BLE if we already found printers via faster interfaces
          if (isBLEOnly && allDiscoveredPrinters.isNotEmpty()) {
            println("StarPrinter: Skipping BLE discovery - already found ${allDiscoveredPrinters.size} printers via faster interfaces")
            continue
          }
          
          try {
            discoveryManager?.stopDiscovery()
            discoveryManager = StarDeviceDiscoveryManagerFactory.create(interfaceTypes, context)
            
            // Timeout strategy: combined gets more time, BLE gets less, others are moderate
            when {
              isCombined -> {
                discoveryManager?.discoveryTime = 6000 // 6 seconds for combined (doing all the work)
                println("StarPrinter: Using extended timeout for combined discovery: 6 seconds")
              }
              isBLEOnly -> {
                discoveryManager?.discoveryTime = 2000 // Only 2 seconds for BLE (very aggressive)
                println("StarPrinter: Using reduced timeout for BLE-only discovery: 2 seconds")
              }
              else -> {
                discoveryManager?.discoveryTime = 4000 // 4 seconds for individual interfaces
                println("StarPrinter: Using moderate timeout for individual discovery: 4 seconds")
              }
            }
            
            val discoveryCompleted = CompletableDeferred<Unit>()
            val discoveryPrinters = mutableListOf<String>()
            
            discoveryManager?.callback = object : StarDeviceDiscoveryManager.Callback {
              override fun onPrinterFound(printer: StarPrinter) {
                val interfaceTypeStr = when (printer.connectionSettings.interfaceType) {
                  InterfaceType.Lan -> "LAN"
                  InterfaceType.Bluetooth -> "BT"
                  InterfaceType.BluetoothLE -> "BLE"
                  InterfaceType.Usb -> "USB"
                  else -> "UNKNOWN"
                }
                val identifier = printer.connectionSettings.identifier
                val model = printer.information?.model ?: "Unknown"
                val printerString = "$interfaceTypeStr:$identifier:$model"
                discoveryPrinters.add(printerString)
              }
              
              override fun onDiscoveryFinished() {
                discoveryCompleted.complete(Unit)
              }
            }
            
            discoveryManager?.startDiscovery()
            discoveryCompleted.await()
            
            // Add all discovered printers to the combined set
            allDiscoveredPrinters.addAll(discoveryPrinters)
            
          } catch (e: Exception) {
            // Log the error but continue trying other interface combinations
            println("StarPrinter: Discovery failed for interfaces $interfaceTypes: ${e.message}")
            continue
          }
        }
        
        // Convert set back to list and return all discovered printers
        printers.addAll(allDiscoveredPrinters.toList())
        
        CoroutineScope(Dispatchers.Main).launch {
          result.success(printers)
        }
        
      } catch (e: Exception) {
        CoroutineScope(Dispatchers.Main).launch {
          result.error("DISCOVERY_FAILED", e.message ?: "Unknown error", null)
        }
      }
    }
  }

  private fun discoverBluetoothPrinters(result: Result) {
    CoroutineScope(Dispatchers.IO).launch {
      try {
        // Check Bluetooth permissions and availability
        if (!hasBluetoothPermissions()) {
          CoroutineScope(Dispatchers.Main).launch {
            result.error("BLUETOOTH_PERMISSION_DENIED", "Bluetooth permissions not granted", null)
          }
          return@launch
        }

        if (!isBluetoothAvailable()) {
          CoroutineScope(Dispatchers.Main).launch {
            result.error("BLUETOOTH_UNAVAILABLE", "Bluetooth is not available or enabled", null)
          }
          return@launch
        }

        val printers = mutableListOf<String>()
        
        // Optimized Bluetooth discovery strategy: combined first, then fallbacks
        val bluetoothInterfaceSets = listOf(
          // Try combined Bluetooth discovery FIRST (most efficient)
          listOf(InterfaceType.Bluetooth, InterfaceType.BluetoothLE),
          // Try classic Bluetooth only as fallback
          listOf(InterfaceType.Bluetooth),
          // Try LE only as last resort with reduced timeout
          listOf(InterfaceType.BluetoothLE)
        )
        
        var discoverySucceeded = false
        
        for ((index, interfaceTypes) in bluetoothInterfaceSets.withIndex()) {
          val isCombined = interfaceTypes.size > 1
          val isBLEOnly = interfaceTypes.size == 1 && interfaceTypes.first() == InterfaceType.BluetoothLE
          
          // Early exit: if combined found printers, skip individual fallbacks
          if (index > 0 && !isBLEOnly && printers.isNotEmpty()) {
            println("StarPrinter: Skipping individual Bluetooth discovery for $interfaceTypes - combined already found ${printers.size} printers")
            continue
          }
          
          try {
            discoveryManager?.stopDiscovery()
            discoveryManager = StarDeviceDiscoveryManagerFactory.create(interfaceTypes, context)
            
            // Optimized timeouts for Bluetooth discovery
            when {
              isCombined -> {
                discoveryManager?.discoveryTime = 7000 // 7 seconds for combined (optimized from 10)
                println("StarPrinter: Using timeout for combined Bluetooth discovery: 7 seconds")
              }
              isBLEOnly -> {
                discoveryManager?.discoveryTime = 3000 // 3 seconds for BLE only (optimized)
                println("StarPrinter: Using reduced timeout for BLE-only discovery: 3 seconds")
              }
              else -> {
                discoveryManager?.discoveryTime = 5000 // 5 seconds for classic BT only
                println("StarPrinter: Using timeout for classic Bluetooth discovery: 5 seconds")
              }
            }
            
            discoveryManager?.callback = object : StarDeviceDiscoveryManager.Callback {
              override fun onPrinterFound(printer: StarPrinter) {
                val interfaceTypeStr = when (printer.connectionSettings.interfaceType) {
                  InterfaceType.Bluetooth -> "BT"
                  InterfaceType.BluetoothLE -> "BLE"
                  else -> "UNKNOWN"
                }
                val identifier = printer.connectionSettings.identifier
                val model = printer.information?.model ?: "Unknown"
                printers.add("$interfaceTypeStr:$identifier:$model")
              }
              
              override fun onDiscoveryFinished() {
                CoroutineScope(Dispatchers.Main).launch {
                  result.success(printers)
                }
              }
            }
            
            discoveryManager?.startDiscovery()
            discoverySucceeded = true
            break // Success, stop trying other combinations
            
          } catch (e: Exception) {
            println("StarPrinter: Bluetooth discovery failed for interfaces $interfaceTypes: ${e.message}")
            continue
          }
        }
        
        if (!discoverySucceeded) {
          CoroutineScope(Dispatchers.Main).launch {
            result.error("BLUETOOTH_DISCOVERY_FAILED", "All Bluetooth discovery methods failed", null)
          }
        }
        
      } catch (e: Exception) {
        CoroutineScope(Dispatchers.Main).launch {
          result.error("BLUETOOTH_DISCOVERY_FAILED", e.message ?: "Not supported interface.", null)
        }
      }
    }
  }

  private fun connectToPrinter(call: MethodCall, result: Result) {
    val args = call.arguments as? Map<*, *>
    val interfaceType = args?.get("interfaceType") as? String
    val identifier = args?.get("identifier") as? String

    if (interfaceType == null || identifier == null) {
      result.error("INVALID_ARGS", "Invalid connection settings", null)
      return
    }

    CoroutineScope(Dispatchers.IO).launch {
      try {
        // Close any existing connection
        printer?.closeAsync()?.await()
        
        val starInterfaceType = when (interfaceType) {
          "bluetooth" -> InterfaceType.Bluetooth
          "lan" -> InterfaceType.Lan
          "usb" -> InterfaceType.Usb
          else -> InterfaceType.Lan
        }
        
        val settings = StarConnectionSettings(starInterfaceType, identifier)
        val newPrinter = StarPrinter(settings, context)
        
        newPrinter.openAsync().await()
        printer = newPrinter
        
        withContext(Dispatchers.Main) {
          result.success(true)
        }
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          result.error("CONNECTION_FAILED", e.message ?: "Unknown error", null)
        }
      }
    }
  }

  private fun disconnectFromPrinter(result: Result) {
    CoroutineScope(Dispatchers.IO).launch {
      try {
        printer?.closeAsync()?.await()
        printer = null
        
        withContext(Dispatchers.Main) {
          result.success(true)
        }
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          result.error("DISCONNECT_FAILED", e.message ?: "Unknown error", null)
        }
      }
    }
  }

  private fun printReceipt(call: MethodCall, result: Result) {
    val args = call.arguments as? Map<*, *>
    val content = args?.get("content") as? String

    if (content == null) {
      result.error("INVALID_ARGS", "Content is required", null)
      return
    }

    if (printer == null) {
      result.error("NOT_CONNECTED", "Printer is not connected", null)
      return
    }

    CoroutineScope(Dispatchers.IO).launch {
      try {
        val builder = StarXpandCommandBuilder()

        // Read structured layout from Dart
        val settings = args["settings"] as? Map<*, *>
        val layout = settings?.get("layout") as? Map<*, *>
        val header = layout?.get("header") as? Map<*, *>
        val imageBlock = layout?.get("image") as? Map<*, *>
        val details = layout?.get("details") as? Map<*, *>
  val items = layout?.get("items") as? List<*>
  val returnItems = layout?.get("returnItems") as? List<*>
  val barcodeBlock = layout?.get("barcode") as? Map<*, *>

        val headerTitle = (header?.get("title") as? String)?.trim().orEmpty()
        val headerFontSize = (header?.get("fontSize") as? Number)?.toInt() ?: 32
        val headerSpacing = (header?.get("spacingLines") as? Number)?.toInt() ?: 1

        val smallImageBase64 = imageBlock?.get("base64") as? String
        val smallImageWidth = (imageBlock?.get("width") as? Number)?.toInt() ?: 200
        val smallImageSpacing = (imageBlock?.get("spacingLines") as? Number)?.toInt() ?: 1

        val locationText = (details?.get("locationText") as? String)?.trim().orEmpty()
        val dateText = (details?.get("date") as? String)?.trim().orEmpty()
        val timeText = (details?.get("time") as? String)?.trim().orEmpty()
        val cashier = (details?.get("cashier") as? String)?.trim().orEmpty()
        val receiptNum = (details?.get("receiptNum") as? String)?.trim().orEmpty()
        val lane = (details?.get("lane") as? String)?.trim().orEmpty()
        val footer = (details?.get("footer") as? String)?.trim().orEmpty()
        val receiptTitle = (details?.get("receiptTitle") as? String)?.trim() ?: "Receipt"  // Extract configurable receipt title
        
        // Financial summary fields
        val subtotal = (details?.get("subtotal") as? String)?.trim().orEmpty()
        val discounts = (details?.get("discounts") as? String)?.trim().orEmpty()
        val hst = (details?.get("hst") as? String)?.trim().orEmpty()
        val gst = (details?.get("gst") as? String)?.trim().orEmpty()
        val total = (details?.get("total") as? String)?.trim().orEmpty()
        
        // Payment methods breakdown
        @Suppress("UNCHECKED_CAST")
        val payments = (details?.get("payments") as? Map<String, String>)?.filterValues { it.isNotEmpty() } ?: emptyMap()
        
        // Barcode
        val barcodeContent = (barcodeBlock?.get("content") as? String)?.trim().orEmpty()
        val barcodeSymbology = (barcodeBlock?.get("symbology") as? String)?.trim()?.lowercase() ?: "code128"
        val barcodeHeight = (barcodeBlock?.get("height") as? Number)?.toInt() ?: 50
        val barcodePrintHRI = (barcodeBlock?.get("printHRI") as? Boolean) ?: true
        
        // Label template fields (from details, same as iOS)
        val category = (details?.get("category") as? String)?.trim().orEmpty()
        val size = (details?.get("size") as? String)?.trim().orEmpty()
        val color = (details?.get("color") as? String)?.trim().orEmpty()
        val labelPrice = (details?.get("price") as? String)?.trim().orEmpty()
        val layoutType = (details?.get("layoutType") as? String)?.trim().orEmpty()
        val printableAreaMm = (details?.get("printableAreaMm") as? Number)?.toDouble() ?: 51.0  // Default to 58mm paper
        
        println("DEBUG: Received printableAreaMm from Dart: ${details?.get("printableAreaMm")}, using: $printableAreaMm")
        println("DEBUG: Barcode settings from Dart - content=$barcodeContent, height=$barcodeHeight, symbology=$barcodeSymbology")
        println("DEBUG: Label layout - type=$layoutType, printableArea=${printableAreaMm}mm")
        println("DEBUG: Label fields - category='$category', size='$size', color='$color', price='$labelPrice'")

  val graphicsOnly = isGraphicsOnlyPrinter()

  val printerBuilder = PrinterBuilder()
  
  // Check if this is a label print job (has label-specific fields)
  val hasLabelFields = category.isNotEmpty() || size.isNotEmpty() || color.isNotEmpty() || labelPrice.isNotEmpty()
  
  // Compute dynamic printable characteristics to match iOS parity
  val labelPrinter = isLabelPrinter()
  val useLabelMode = (labelPrinter || hasLabelFields) && printableAreaMm > 0
  val targetDots: Int
  val fullWidthMm: Double
  
  // Detect printer DPI and magnification needs
  var textMagnificationWidth = 1
  var textMagnificationHeight = 1
  
  if (useLabelMode) {
    // Detect printer DPI based on model
    val dotsPerMm: Double
    val modelName = printer?.information?.model?.name?.lowercase() ?: ""
    if (modelName.contains("mc_label2") || modelName.contains("mc-label2")) {
      dotsPerMm = 11.8  // mcLabel2 is 300 DPI (300/25.4 = 11.8 dots/mm)
      textMagnificationWidth = 2
      textMagnificationHeight = 2  // Scale text 2x to match TSP100IVSK visual size
      println("DEBUG: Detected mcLabel2 - using 300 DPI (11.8 dots/mm) with 2x text magnification")
    } else {
      dotsPerMm = 8.0   // TSP100IVSK is 203 DPI (203/25.4 = 8.0 dots/mm)
      println("DEBUG: Detected TSP100IVSK or similar - using 203 DPI (8 dots/mm)")
    }
    
    targetDots = (printableAreaMm * dotsPerMm).toInt()
    fullWidthMm = printableAreaMm
    println("DEBUG: Using label printable area: ${printableAreaMm}mm = $targetDots dots")
  } else {
    // Use auto-detected width for receipts
    targetDots = currentPrintableWidthDots()
    fullWidthMm = currentPrintableWidthMm()
    println("DEBUG: Using auto-detected width: ${fullWidthMm}mm = $targetDots dots")
  }
  
  // Use targetDots for text width calculation in label mode (matching iOS logic)
  val cpl = if (useLabelMode) (targetDots / 12.0).toInt() else currentColumnsPerLine()
  println("DEBUG: Text width calculation - useLabelMode=$useLabelMode, cpl=$cpl (targetDots=$targetDots)")
  println("DEBUG: TSP650 currentPrintableWidthDots = ${currentPrintableWidthDots()}, fullWidthMm=$fullWidthMm")

        // 1) Header: print as bold text instead of image for labels
        if (headerTitle.isNotEmpty()) {
          if (useLabelMode) {
            // For labels, use bold text instead of image
            printerBuilder
              .styleAlignment(Alignment.Center)
              .styleBold(true)
              .styleMagnification(MagnificationParameter(textMagnificationWidth, textMagnificationHeight))
              .actionPrintText("$headerTitle\n")
              .styleMagnification(MagnificationParameter(1, 1))
              .styleBold(false)
              .styleAlignment(Alignment.Left)
            if (headerSpacing > 0) printerBuilder.actionFeedLine(headerSpacing)
          } else {
            // For receipts, use image
            val headerBitmap = createHeaderBitmap(headerTitle, headerFontSize, targetDots)
            if (headerBitmap != null) {
              printerBuilder
                .styleAlignment(Alignment.Center)
                .actionPrintImage(ImageParameter(headerBitmap, targetDots))
                .styleAlignment(Alignment.Left)
              if (headerSpacing > 0) printerBuilder.actionFeedLine(headerSpacing)
            }
          }
        }

        // 2) Small image centered
        if (!smallImageBase64.isNullOrEmpty()) {
          val clamped = smallImageWidth.coerceIn(8, targetDots)
          val decoded = decodeBase64ToBitmap(smallImageBase64)
          val src = decoded ?: createPlaceholderBitmap(clamped, clamped)
          if (src != null) {
            val flat = flattenBitmap(src, clamped)
            val centered = centerOnCanvas(flat, targetDots)
            if (centered != null) {
              printerBuilder
                .styleAlignment(Alignment.Center)
                .actionPrintImage(ImageParameter(centered, targetDots))
                .styleAlignment(Alignment.Left)
              if (smallImageSpacing > 0) printerBuilder.actionFeedLine(smallImageSpacing)
            }
          }
        }

  // 2.5) Barcode printing for receipts (labels print barcode at bottom in template)
        if (barcodeContent.isNotEmpty() && !(useLabelMode && hasLabelFields)) {
          println("DEBUG: Printing barcode (receipt mode): content=$barcodeContent, symbology=$barcodeSymbology, useLabelMode=$useLabelMode")
          
          // Map symbology string to StarXpand BarcodeSymbology enum
          val symbology = when (barcodeSymbology) {
            "code128" -> BarcodeSymbology.Code128
            "code39" -> BarcodeSymbology.Code39
            "code93" -> BarcodeSymbology.Code93
            "jan8", "ean8" -> BarcodeSymbology.Jan8
            "jan13", "ean13" -> BarcodeSymbology.Jan13
            "nw7", "codabar" -> BarcodeSymbology.NW7
            else -> BarcodeSymbology.Code128  // Default to CODE128
          }
          
          // Create barcode parameter
          // For narrow label printers, use minimal bar width (2 dots) to fit within print area
          val barDots = if (labelPrinter) 2 else 3
          val barcodeParam = BarcodeParameter(barcodeContent, symbology)
            .setBarDots(barDots)
            .setHeight(barcodeHeight.toDouble())
            .setPrintHri(barcodePrintHRI)  // Always print HRI in receipt mode too
          
          println("DEBUG: Barcode parameters - barDots=$barDots, height=$barcodeHeight, printableWidth=$targetDots")
          
          // Print barcode centered
          printerBuilder
            .styleAlignment(Alignment.Center)
            .actionPrintBarcode(barcodeParam)
            .styleAlignment(Alignment.Left)
          
          printerBuilder.actionFeedLine(1)  // Add spacing after barcode
          println("DEBUG: Barcode command added to printer builder")
        }

  // 2.6) Details block (we will later inject items between ruled lines)
        val hasAnyDetails = listOf(locationText, dateText, timeText, cashier, receiptNum, lane, footer).any { it.isNotEmpty() }
        if (hasAnyDetails) {
          // Only use image rendering for graphics-only printers (like iOS)
          // Label printers (mPOP, TSP100SK) support native text commands
          if (graphicsOnly) {
            // Force label printers to use targetDots for proper width like iOS
            val detailsCanvas = targetDots
            val detailsBmp = createDetailsBitmap(locationText, dateText, timeText, cashier, receiptNum, lane, footer, items, detailsCanvas, receiptTitle)
            if (detailsBmp != null) {
              printerBuilder.actionPrintImage(ImageParameter(detailsBmp, detailsCanvas)).actionFeedLine(1)
            }
          } else {
            // Centered location
            if (locationText.isNotEmpty()) {
              printerBuilder.styleAlignment(Alignment.Center).actionPrintText("$locationText\n").styleAlignment(Alignment.Left)
              printerBuilder.actionFeedLine(1) // blank line
            }
            // Centered Receipt Title (configurable)
            printerBuilder.styleAlignment(Alignment.Center).actionPrintText("$receiptTitle\n").styleAlignment(Alignment.Left)
            
            // For TSP650II - use manual space padding since .setWidth() isn't supported
            val modelStr = printer?.information?.model?.toString()?.lowercase() ?: ""
            if (modelStr.contains("tsp650")) {
              println("DEBUG: Using manual padding for TSP650II (42 chars per line)")
              val left1 = listOf(dateText, timeText).filter { it.isNotEmpty() }.joinToString(" ")
              val right1 = if (cashier.isNotEmpty()) "Cashier: $cashier" else ""
              if (left1.isNotEmpty() && right1.isNotEmpty()) {
                val totalLen = left1.length + right1.length
                val spacesNeeded = (42 - totalLen).coerceAtLeast(1)
                val paddedLine = left1 + " ".repeat(spacesNeeded) + right1
                printerBuilder.actionPrintText("$paddedLine\n")
              } else if (left1.isNotEmpty()) {
                printerBuilder.actionPrintText("$left1\n")
              } else if (right1.isNotEmpty()) {
                printerBuilder.actionPrintText("${" ".repeat(42 - right1.length)}$right1\n")
              }
              
              val left2 = if (receiptNum.isNotEmpty()) "Receipt No: $receiptNum" else ""
              val right2 = if (lane.isNotEmpty()) "Lane: $lane" else ""
              if (left2.isNotEmpty() && right2.isNotEmpty()) {
                val totalLen = left2.length + right2.length
                val spacesNeeded = (42 - totalLen).coerceAtLeast(1)
                val paddedLine = left2 + " ".repeat(spacesNeeded) + right2
                printerBuilder.actionPrintText("$paddedLine\n")
              } else if (left2.isNotEmpty()) {
                printerBuilder.actionPrintText("$left2\n")
              } else if (right2.isNotEmpty()) {
                printerBuilder.actionPrintText("${" ".repeat(42 - right2.length)}$right2\n")
              }
              
              // Gap then first ruled line
              printerBuilder.actionFeedLine(1)
              printerBuilder.actionPrintRuledLine(RuledLineParameter(fullWidthMm))
              
              // Item lines with manual padding
              val itemList = items?.mapNotNull { it as? Map<*, *> } ?: emptyList()
              for (item in itemList) {
                val qty = (item["quantity"] as? String)?.trim().orEmpty()
                val name = (item["name"] as? String)?.trim().orEmpty()
                val price = (item["price"] as? String)?.trim().orEmpty()
                val repeatStr = (item["repeat"] as? String)?.trim().orEmpty()
                val repeatN = repeatStr.toIntOrNull() ?: 1
                val leftText = listOf(qty.ifEmpty { "1" }, "x", name.ifEmpty { "Item" }).joinToString(" ")
                val rightText = if (price.isNotEmpty()) "$price" else "$0.00"
                repeat(repeatN.coerceAtLeast(1).coerceAtMost(200)) {
                  val totalLen = leftText.length + rightText.length
                  val spacesNeeded = (42 - totalLen).coerceAtLeast(1)
                  val paddedLine = leftText + " ".repeat(spacesNeeded) + rightText
                  printerBuilder.actionPrintText("$paddedLine\n")
                }
              }
              
              // Second ruled line and footer
              printerBuilder.actionPrintRuledLine(RuledLineParameter(fullWidthMm))
              printerBuilder.actionFeedLine(1)
              if (footer.isNotEmpty()) {
                printerBuilder.styleAlignment(Alignment.Center).actionPrintText("$footer\n").styleAlignment(Alignment.Left)
              }
            } else {
              // Use normal TextParameter approach for other printers (that support .setWidth())
              val leftWidthTop = (cpl / 2).coerceAtLeast(8)
              val rightWidthTop = (cpl - leftWidthTop).coerceAtLeast(8)
              val leftParam = TextParameter().setWidth(leftWidthTop)
              val rightParam = TextParameter().setWidth(rightWidthTop, TextWidthParameter().setAlignment(TextAlignment.Right))
              val left1 = listOf(dateText, timeText).filter { it.isNotEmpty() }.joinToString(" ")
              val right1 = if (cashier.isNotEmpty()) "Cashier: $cashier" else ""
              printerBuilder.actionPrintText(left1, leftParam)
              printerBuilder.actionPrintText("$right1\n", rightParam)
              val left2 = if (receiptNum.isNotEmpty()) "Receipt No: $receiptNum" else ""
              val right2 = if (lane.isNotEmpty()) "Lane: $lane" else ""
              printerBuilder.actionPrintText(left2, leftParam)
              printerBuilder.actionPrintText("$right2\n", rightParam)
              printerBuilder.actionFeedLine(1)
              printerBuilder.actionPrintRuledLine(RuledLineParameter(fullWidthMm))
              
              val itemList = items?.mapNotNull { it as? Map<*, *> } ?: emptyList()
              if (itemList.isNotEmpty()) {
                val leftItemsWidth = ((cpl * 5) / 8).coerceAtLeast(8)
                val rightItemsWidth = (cpl - leftItemsWidth).coerceAtLeast(6)
                val leftParam2 = TextParameter().setWidth(leftItemsWidth)
                val rightParam2 = TextParameter().setWidth(rightItemsWidth, TextWidthParameter().setAlignment(TextAlignment.Right))
                for (item in itemList) {
                  val qty = (item["quantity"] as? String)?.trim().orEmpty()
                  val name = (item["name"] as? String)?.trim().orEmpty()
                  val price = (item["price"] as? String)?.trim().orEmpty()
                  val repeatStr = (item["repeat"] as? String)?.trim().orEmpty()
                  val repeatN = repeatStr.toIntOrNull() ?: 1
                  val leftText = listOf(qty.ifEmpty { "1" }, "x", name.ifEmpty { "Item" }).joinToString(" ")
                  val rightText = if (price.isNotEmpty()) "$price" else "$0.00"
                  repeat(repeatN.coerceAtLeast(1).coerceAtMost(200)) {
                    printerBuilder.actionPrintText(leftText, leftParam2)
                    printerBuilder.actionPrintText("$rightText\n", rightParam2)
                  }
                }
              }
              printerBuilder.actionPrintRuledLine(RuledLineParameter(fullWidthMm))
              printerBuilder.actionFeedLine(1)
              
              // Financial summary section
              if (subtotal.isNotEmpty() || discounts.isNotEmpty() || hst.isNotEmpty() || gst.isNotEmpty() || total.isNotEmpty()) {
                val leftFinancialWidth = (cpl * 5) / 8
                val rightFinancialWidth = cpl - leftFinancialWidth
                val leftFinancialParam = TextParameter().setWidth(leftFinancialWidth)
                val rightFinancialParam = TextParameter().setWidth(rightFinancialWidth, TextWidthParameter().setAlignment(TextAlignment.Right))
                
                if (subtotal.isNotEmpty()) {
                  printerBuilder.actionPrintText("Subtotal", leftFinancialParam)
                  printerBuilder.actionPrintText("$subtotal\n", rightFinancialParam)
                }
                if (discounts.isNotEmpty()) {
                  printerBuilder.actionPrintText("Discounts", leftFinancialParam)
                  printerBuilder.actionPrintText("$discounts\n", rightFinancialParam)
                }
                if (hst.isNotEmpty()) {
                  printerBuilder.actionPrintText("HST", leftFinancialParam)
                  printerBuilder.actionPrintText("$hst\n", rightFinancialParam)
                }
                if (gst.isNotEmpty()) {
                  printerBuilder.actionPrintText("GST", leftFinancialParam)
                  printerBuilder.actionPrintText("$gst\n", rightFinancialParam)
                }
                if (total.isNotEmpty()) {
                  printerBuilder.actionPrintText("Total", leftFinancialParam)
                  printerBuilder.actionPrintText("$total\n", rightFinancialParam)
                }
                
                // Third ruled line after financial summary
                printerBuilder.actionPrintRuledLine(RuledLineParameter(fullWidthMm))
                printerBuilder.actionFeedLine(1)
                
                // Payment methods section
                if (payments.isNotEmpty()) {
                  // Centered "Payment Method" header
                  printerBuilder.styleAlignment(Alignment.Center)
                    .actionPrintText("Payment Method\n")
                    .styleAlignment(Alignment.Left)
                  
                  // Each payment method with left-right alignment
                  for ((method, amount) in payments) {
                    printerBuilder.actionPrintText(method, leftFinancialParam)
                    printerBuilder.actionPrintText("$$amount\n", rightFinancialParam)
                  }
                }
              }
              
              if (footer.isNotEmpty()) {
                printerBuilder.styleAlignment(Alignment.Center).actionPrintText("$footer\n").styleAlignment(Alignment.Left)
              }
            }
          }
        }

        // 3) Body content or Label template
        val trimmedBody = content.trim()
        
        println("DEBUG: Rendering body content - useLabelMode=$useLabelMode, graphicsOnly=$graphicsOnly, hasLabelFields=$hasLabelFields, contentLength=${trimmedBody.length}")
        
        if (useLabelMode && hasLabelFields) {
          // Label template rendering
          println("DEBUG: Rendering label template with layout: $layoutType")
          
          when (layoutType) {
            "vertical_centered" -> {
              // 38mm paper (34.5mm printable) - everything vertical and centered
              if (category.isNotEmpty()) {
                printerBuilder
                  .styleAlignment(Alignment.Center)
                  .styleMagnification(MagnificationParameter(textMagnificationWidth, textMagnificationHeight))
                  .actionPrintText("$category\n")
                  .styleMagnification(MagnificationParameter(1, 1))
                  .styleAlignment(Alignment.Left)
              }
              
              if (labelPrice.isNotEmpty()) {
                printerBuilder
                  .styleAlignment(Alignment.Center)
                  .styleBold(true)
                  .styleMagnification(MagnificationParameter(textMagnificationWidth, textMagnificationHeight))
                  .actionPrintText("$$labelPrice\n")
                  .styleMagnification(MagnificationParameter(1, 1))
                  .styleBold(false)
                  .styleAlignment(Alignment.Left)
              }
              // Size and Color on one line, centered (no pipes, no magnification)
              val combinedLine = buildString {
                if (size.isNotEmpty()) append(size)
                if (color.isNotEmpty()) {
                  if (isNotEmpty()) append("  ")
                  append(color)
                }
              }
              
              if (combinedLine.isNotEmpty()) {
                printerBuilder
                  .styleAlignment(Alignment.Center)
                  .actionPrintText("$combinedLine\n")
                  .styleAlignment(Alignment.Left)
              }
            }
            "mixed" -> {
              // 58mm paper (51mm printable) - optimized horizontal layout
              // Category centered below header (skip if already in header)
              if (category.isNotEmpty() && category != headerTitle) {
                printerBuilder
                  .styleAlignment(Alignment.Center)
                  .styleMagnification(MagnificationParameter(textMagnificationWidth, textMagnificationHeight))
                  .actionPrintText("$category\n")
                  .styleMagnification(MagnificationParameter(1, 1))
                  .styleAlignment(Alignment.Left)
              }
              
              // Price centered on its own line (bold)
              if (labelPrice.isNotEmpty()) {
                printerBuilder
                  .styleAlignment(Alignment.Center)
                  .styleBold(true)
                  .styleMagnification(MagnificationParameter(textMagnificationWidth, textMagnificationHeight))
                  .actionPrintText("$$labelPrice\n")
                  .styleMagnification(MagnificationParameter(1, 1))
                  .styleBold(false)
                  .styleAlignment(Alignment.Left)
              }
              
              // Size and Color on one line, centered (no pipes, no magnification)
              val combinedLine = buildString {
                if (size.isNotEmpty()) append(size)
                if (color.isNotEmpty()) {
                  if (isNotEmpty()) append("  ")
                  append(color)
                }
              }
              
              if (combinedLine.isNotEmpty()) {
                printerBuilder
                  .styleAlignment(Alignment.Center)
                  .actionPrintText("$combinedLine\n")
                  .styleAlignment(Alignment.Left)
              }
            }
            else -> {
              // 80mm paper (72mm printable) - same layout as 58mm
              // Category centered below header (skip if already in header)
              if (category.isNotEmpty() && category != headerTitle) {
                printerBuilder
                  .styleAlignment(Alignment.Center)
                  .styleMagnification(MagnificationParameter(textMagnificationWidth, textMagnificationHeight))
                  .actionPrintText("$category\n")
                  .styleMagnification(MagnificationParameter(1, 1))
                  .styleAlignment(Alignment.Left)
              }
              
              // Price centered on its own line (bold)
              if (labelPrice.isNotEmpty()) {
                printerBuilder
                  .styleAlignment(Alignment.Center)
                  .styleBold(true)
                  .styleMagnification(MagnificationParameter(textMagnificationWidth, textMagnificationHeight))
                  .actionPrintText("$$labelPrice\n")
                  .styleMagnification(MagnificationParameter(1, 1))
                  .styleBold(false)
                  .styleAlignment(Alignment.Left)
              }
              
              // Size and Color on one line, centered (no pipes, no magnification)
              val combinedLine = buildString {
                if (size.isNotEmpty()) append(size)
                if (color.isNotEmpty()) {
                  if (isNotEmpty()) append("  ")
                  append(color)
                }
              }
              
              if (combinedLine.isNotEmpty()) {
                printerBuilder
                  .styleAlignment(Alignment.Center)
                  .actionPrintText("$combinedLine\n")
                  .styleAlignment(Alignment.Left)
              }
            }
          }
          
          // Print barcode at the bottom for labels
          if (barcodeContent.isNotEmpty()) {
            println("DEBUG: Printing barcode at bottom: content=$barcodeContent, symbology=$barcodeSymbology, height=$barcodeHeight")
            
            val symbology = when (barcodeSymbology) {
              "code128" -> BarcodeSymbology.Code128
              "code39" -> BarcodeSymbology.Code39
              "code93" -> BarcodeSymbology.Code93
              "jan8", "ean8" -> BarcodeSymbology.Jan8
              "jan13", "ean13" -> BarcodeSymbology.Jan13
              "nw7", "codabar" -> BarcodeSymbology.NW7
              else -> BarcodeSymbology.Code128
            }
            
            // Scale barcode for mcLabel2 to match text magnification
            val scaledBarcodeHeight = barcodeHeight.toDouble() * textMagnificationHeight
            val barcodeBarDots = textMagnificationWidth  // Scale bar width to match text width
            
            val barcodeParam = BarcodeParameter(barcodeContent, symbology)
              .setBarDots(barcodeBarDots)
              .setPrintHri(barcodePrintHRI)
              .setHeight(scaledBarcodeHeight)
            
            printerBuilder
              .styleAlignment(Alignment.Center)
              .actionPrintBarcode(barcodeParam)
              .styleAlignment(Alignment.Left)
            
            println("DEBUG: Barcode command added at bottom (height=${scaledBarcodeHeight}mm, barDots=$barcodeBarDots)")
          }
          
          // Set printable area for label
          if (printableAreaMm > 0) {
            println("DEBUG: Set label printable area to ${printableAreaMm}mm")
          }
        } else if (graphicsOnly || labelPrinter) {
          // Skip generating an empty body bitmap to prevent a blank rectangle artifact
          // on graphics-only printers (e.g., TSP100III). Only render if there is real content.
          // Label printers (like TSP100SK) also need centered image rendering.
          if (trimmedBody.isNotEmpty()) {
            println("DEBUG: Rendering body as image for label printer")
            val bodyBitmap = createTextBitmap(content, targetDots)
            printerBuilder.actionPrintImage(ImageParameter(bodyBitmap, targetDots)).actionFeedLine(2)
          } else {
            // Light feed to keep a small margin before cut for visual consistency.
            println("DEBUG: Skipping body content (empty)")
            printerBuilder.actionFeedLine(1)
          }
        } else {
          println("DEBUG: Rendering body as text")
          printerBuilder.actionPrintText(content).actionFeedLine(2)
        }

        // Build document - DO NOT use settingPrintableArea() as it permanently changes printer memory!
        // We already calculated targetDots based on printableAreaMm for our rendering
        val documentBuilder = DocumentBuilder()
        // Let the printer use its own configured printable area
        documentBuilder.addPrinter(printerBuilder.actionCut(CutType.Partial))
        
        builder.addDocument(documentBuilder)
        
        val commands = builder.getCommands()
        printer?.printAsync(commands)?.await()
        
        withContext(Dispatchers.Main) {
          result.success(true)
        }
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          result.error("PRINT_FAILED", e.message ?: "Unknown error", null)
        }
      }
    }
  }

  private fun getStatus(result: Result) {
    if (printer == null) {
      result.error("NOT_CONNECTED", "Printer is not connected", null)
      return
    }

    CoroutineScope(Dispatchers.IO).launch {
      try {
        val status = printer?.getStatusAsync()?.await()
        
        val statusMap = mutableMapOf<String, Any?>(
          "isOnline" to (status != null),
          "status" to "OK"
        )
        
        // Note: paperPresent is available on iOS but not consistently exposed in Android StarIO10 SDK
        // Leaving this out for now on Android
        
        withContext(Dispatchers.Main) {
          result.success(statusMap)
        }
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          result.error("STATUS_FAILED", e.message ?: "Unknown error", null)
        }
      }
    }
  }

  private fun openCashDrawer(result: Result) {
    if (printer == null) {
      result.error("NOT_CONNECTED", "Printer is not connected", null)
      return
    }

    CoroutineScope(Dispatchers.IO).launch {
      try {
        val builder = StarXpandCommandBuilder()
        builder.addDocument(DocumentBuilder().addDrawer(
          DrawerBuilder()
            .actionOpen(OpenParameter())
        ))
        
        val commands = builder.getCommands()
        printer?.printAsync(commands)?.await()
        
        withContext(Dispatchers.Main) {
          result.success(true)
        }
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          result.error("CASH_DRAWER_FAILED", e.message ?: "Unknown error", null)
        }
      }
    }
  }

  private fun isConnected(result: Result) {
    result.success(printer != null)
  }

  private fun runUsbDiagnostics(result: Result) {
    CoroutineScope(Dispatchers.IO).launch {
      try {
        val diagnostics = mutableMapOf<String, Any>()
        
        // Check USB Host support
        val packageManager = context.packageManager
        val hasUsbHost = packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)
        diagnostics["usb_host_supported"] = hasUsbHost
        
        // Check USB Manager and connected devices
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val deviceList = usbManager.deviceList
        diagnostics["connected_usb_devices"] = deviceList.size
        
        val usbDevices = mutableListOf<Map<String, Any>>()
        for ((deviceName, device) in deviceList) {
          val deviceInfo = mapOf(
            "device_name" to deviceName,
            "vendor_id" to device.vendorId,
            "product_id" to device.productId,
            "device_class" to device.deviceClass,
            "device_subclass" to device.deviceSubclass,
            "product_name" to (device.productName ?: "Unknown"),
            "manufacturer_name" to (device.manufacturerName ?: "Unknown")
          )
          usbDevices.add(deviceInfo)
        }
        diagnostics["usb_devices"] = usbDevices
        
        // Check for TSP100 specific devices (vendor ID 1305, common product IDs)
        val tsp100Devices = deviceList.values.filter { device ->
          device.vendorId == 1305 // Star Micronics vendor ID
        }
        diagnostics["tsp100_devices_found"] = tsp100Devices.size
        
        // Try USB-only discovery
        var usbPrintersFound = 0
        try {
          val printers = mutableListOf<String>()
          discoveryManager?.stopDiscovery()
          discoveryManager = StarDeviceDiscoveryManagerFactory.create(listOf(InterfaceType.Usb), context)
          
          discoveryManager?.discoveryTime = 3000 // 3 seconds for diagnostics (optimized)
          
          val discoveryCompleted = CompletableDeferred<Unit>()
          
          discoveryManager?.callback = object : StarDeviceDiscoveryManager.Callback {
            override fun onPrinterFound(printer: StarPrinter) {
              val identifier = printer.connectionSettings.identifier
              val model = printer.information?.model ?: "Unknown"
              printers.add("USB:$identifier:$model")
              usbPrintersFound++
            }
            
            override fun onDiscoveryFinished() {
              discoveryCompleted.complete(Unit)
            }
          }
          
          discoveryManager?.startDiscovery()
          discoveryCompleted.await()
          
          diagnostics["usb_printers_discovered"] = usbPrintersFound
          diagnostics["usb_printer_list"] = printers
          
        } catch (e: Exception) {
          diagnostics["usb_discovery_error"] = e.message ?: "Unknown error"
          diagnostics["usb_printers_discovered"] = 0
        }
        
        withContext(Dispatchers.Main) {
          result.success(diagnostics)
        }
        
      } catch (e: Exception) {
        withContext(Dispatchers.Main) {
          result.error("USB_DIAGNOSTICS_FAILED", e.message ?: "Unknown error", null)
        }
      }
    }
  }

  // ActivityAware implementation
  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  private fun hasBluetoothPermissions(): Boolean {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      // Android 12+ permissions - BLUETOOTH_CONNECT is required for printer communication
      ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED &&
      ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
    } else {
      // Legacy permissions
      ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH) == PackageManager.PERMISSION_GRANTED &&
      ContextCompat.checkSelfPermission(context, android.Manifest.permission.BLUETOOTH_ADMIN) == PackageManager.PERMISSION_GRANTED
    }
  }

  private fun isBluetoothAvailable(): Boolean {
    val bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
    val bluetoothAdapter = bluetoothManager?.adapter
    return bluetoothAdapter != null && bluetoothAdapter.isEnabled
  }

  // Determine if the connected printer is graphics-only (e.g., TSP100iii series)
  private fun isGraphicsOnlyPrinter(): Boolean {
    return try {
      val modelStr = printer?.information?.model?.toString() ?: return false
      // Use a case-insensitive check to avoid tight coupling to enum identifiers
      val ms = modelStr.lowercase()
      ms.contains("tsp100iii") || ms.contains("tsp1003")
    } catch (e: Exception) {
      false
    }
  }

  // Heuristic: determine if current model is a label printer (e.g., mC-Label2, TSP100SK)
  private fun isLabelPrinter(): Boolean {
    return try {
      val modelStr = printer?.information?.model?.toString() ?: return false
      val ms = modelStr.lowercase()
      val isLabel = ms.contains("label") || ms.contains("tsp100iv_sk") || ms.contains("tsp100sk") || ms.contains("_sk") || ms.contains("mpop")
      // DO NOT include regular tsp100iv - it's a receipt printer!
      println("DEBUG: isLabelPrinter check for '$ms': $isLabel")
      isLabel
    } catch (_: Exception) { false }
  }

  // Estimate printable width in dots by model family (conservative defaults)
  private fun currentPrintableWidthDots(): Int {
    return try {
      val ms = (printer?.information?.model?.toString() ?: "").lowercase()
      println("DEBUG: Printer model for width calculation: $ms")
      
      // ADJUST THIS VALUE if labels are still being cut off:
      // - If content is cut off on right: decrease this number (try 220, 200, etc.)
      // - If content appears too narrow with margins: increase this number (try 260, 280, etc.)
      val tsp100skWidth = 240  // Optimized for TSP100SK label printing
      
      val width = when {
        // Label printers - render at 576 and let device scale if needed
        ms.contains("label") -> 576
        // TSP100SK is a 2" label printer but actual printable width appears much narrower
        ms.contains("tsp100iv_sk") || ms.contains("tsp100sk") || ms.contains("_sk") -> {
          println("DEBUG: TSP100SK detected, using $tsp100skWidth dots width")
          tsp100skWidth
        }
        // 58mm class
        ms.contains("mpop") || ms.contains("mcp2") -> 384
        // 80mm class
        ms.contains("mcp3") || ms.contains("tsp100") || ms.contains("tsp650") -> 576
        else -> 576
      }
      width
    } catch (_: Exception) { 576 }
  }

  private fun currentPrintableWidthMm(): Double {
    val dots = currentPrintableWidthDots()
    // Star thermal printers are ~203dpi (~8 dots/mm)
    return dots / 8.0
  }

  private fun currentColumnsPerLine(): Int {
    val dots = currentPrintableWidthDots()
    val modelStr = printer?.information?.model?.toString()?.lowercase() ?: ""
    
    return when {
      // TSP650II needs fewer characters per line than other 80mm printers
      modelStr.contains("tsp650") -> 42
      // Other 80mm printers
      dots >= 576 -> 48
      // 58mm printers  
      else -> 32
    }
  }

  // Render multiline text into a Bitmap suitable for printing
  private fun createTextBitmap(text: String): Bitmap {
    val width = 576 // default fallback
    val padding = 20

    val textPaint = TextPaint().apply {
      isAntiAlias = true
      color = Color.BLACK
      textSize = 24f
    }

    val contentWidth = width - (padding * 2)

    val layout: StaticLayout = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      StaticLayout.Builder
        .obtain(text, 0, text.length, textPaint, contentWidth)
        .setAlignment(Layout.Alignment.ALIGN_NORMAL)
        .setIncludePad(false)
        .build()
    } else {
      @Suppress("DEPRECATION")
      StaticLayout(
        text,
        textPaint,
        contentWidth,
        Layout.Alignment.ALIGN_NORMAL,
        1.0f,
        0.0f,
        false
      )
    }

    val height = (layout.height + padding * 2).coerceAtLeast(100)
    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.drawColor(Color.WHITE)
    canvas.save()
    canvas.translate(padding.toFloat(), padding.toFloat())
    layout.draw(canvas)
    canvas.restore()
    return bitmap
  }

  // Overload that renders text to a specified width (in dots)
  private fun createTextBitmap(text: String, width: Int): Bitmap {
    println("DEBUG createTextBitmap: Original text = '$text'")
    // Filter out barcode placeholder lines (lines that are mostly pipe characters)
    val filteredText = text.lines()
      .filter { line ->
        val trimmed = line.trim()
        // Keep empty lines
        if (trimmed.isEmpty()) return@filter true
        
        val pipeCount = trimmed.count { it == '|' }
        val totalChars = trimmed.length
        // Skip lines that are more than 50% pipe characters (barcode placeholders)
        val isPipeLine = (pipeCount.toDouble() / totalChars.toDouble()) >= 0.5
        if (isPipeLine) {
          println("DEBUG createTextBitmap: Filtering out pipe line: '$trimmed' (pipes: $pipeCount/$totalChars)")
        }
        !isPipeLine
      }
      .joinToString("\n")
    
    println("DEBUG createTextBitmap: Filtered text = '$filteredText' (Original: ${text.length} chars, Filtered: ${filteredText.length} chars)")
    
    val w = width.coerceIn(8, 576)
    val padding = 20

    val textPaint = TextPaint().apply {
      isAntiAlias = true
      color = Color.BLACK
      textSize = 24f
    }

    val contentWidth = w - (padding * 2)

    val layout: StaticLayout = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      StaticLayout.Builder
        .obtain(filteredText, 0, filteredText.length, textPaint, contentWidth)
        .setAlignment(Layout.Alignment.ALIGN_CENTER)
        .setIncludePad(false)
        .build()
    } else {
      @Suppress("DEPRECATION")
      StaticLayout(
        filteredText,
        textPaint,
        contentWidth,
        Layout.Alignment.ALIGN_CENTER,
        1.0f,
        0.0f,
        false
      )
    }

    val height = (layout.height + padding * 2).coerceAtLeast(100)
    val bitmap = Bitmap.createBitmap(w, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.drawColor(Color.WHITE)
    canvas.save()
    canvas.translate(padding.toFloat(), padding.toFloat())
    layout.draw(canvas)
    canvas.restore()
    return bitmap
  }

  // Render centered header text to a bitmap of given width
  private fun createHeaderBitmap(text: String, fontSize: Int, width: Int): Bitmap? {
    val w = width.coerceAtMost(576)
    val padding = 20
    val textPaint = TextPaint().apply {
      isAntiAlias = true
      color = Color.BLACK
      textSize = fontSize.toFloat()
    }
    val contentWidth = w - (padding * 2)
    val layout: StaticLayout = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      StaticLayout.Builder
        .obtain(text, 0, text.length, textPaint, contentWidth)
        .setAlignment(Layout.Alignment.ALIGN_CENTER)
        .setIncludePad(false)
        .build()
    } else {
      @Suppress("DEPRECATION")
      StaticLayout(text, textPaint, contentWidth, Layout.Alignment.ALIGN_CENTER, 1.0f, 0.0f, false)
    }
    val height = (layout.height + padding * 2).coerceAtLeast(100)
    val bitmap = Bitmap.createBitmap(w, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bitmap)
    canvas.drawColor(Color.WHITE)
    canvas.save()
    canvas.translate(padding.toFloat(), padding.toFloat())
    layout.draw(canvas)
    canvas.restore()
    return bitmap
  }

  // Create a structured details block bitmap matching iOS layout
  private fun createDetailsBitmap(
    locationText: String,
    dateText: String,
    timeText: String,
    cashier: String,
    receiptNum: String,
    lane: String,
    footer: String,
    items: List<*>?,
    canvasWidth: Int,
    receiptTitle: String = "Receipt"  // Add receiptTitle parameter with default
  ): Bitmap? {
    val width = canvasWidth.coerceIn(8, 576)
    val padding = 20

    val titlePaint = TextPaint().apply {
      isAntiAlias = true
      color = Color.BLACK
      textSize = 28f
    }
    val bodyPaint = TextPaint().apply {
      isAntiAlias = true
      color = Color.BLACK
      textSize = 22f
    }

    val contentWidth = width - padding * 2

    fun buildLayout(text: String, paint: TextPaint, align: Layout.Alignment): StaticLayout {
      return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        StaticLayout.Builder
          .obtain(text, 0, text.length, paint, contentWidth)
          .setAlignment(align)
          .setIncludePad(false)
          .build()
      } else {
        @Suppress("DEPRECATION")
        StaticLayout(text, paint, contentWidth, align, 1.0f, 0.0f, false)
      }
    }

    // Build layouts (no lines yet)
    val layouts = mutableListOf<StaticLayout>()
    var totalHeight = 0

    if (locationText.isNotEmpty()) {
      val loc = buildLayout(locationText, titlePaint, Layout.Alignment.ALIGN_CENTER)
      layouts.add(loc)
      totalHeight += loc.height
      // blank line spacer
      val spacer = buildLayout(" ", bodyPaint, Layout.Alignment.ALIGN_NORMAL)
      layouts.add(spacer)
      totalHeight += spacer.height
    }

    val tax = buildLayout(receiptTitle, titlePaint, Layout.Alignment.ALIGN_CENTER)
    layouts.add(tax)
    totalHeight += tax.height

    // Column rows (date/time vs cashier, receipt vs lane) need true right alignment.
    // We'll measure & draw these rows manually instead of using padded spaces.
    data class TwoCol(val left: String, val right: String)
    val twoColRows = mutableListOf<TwoCol>()
    val left1 = listOf(dateText, timeText).filter { it.isNotEmpty() }.joinToString(" ")
    val right1 = if (cashier.isNotEmpty()) "Cashier: $cashier" else ""
    val left2 = if (receiptNum.isNotEmpty()) "Receipt No: $receiptNum" else ""
    val right2 = if (lane.isNotEmpty()) "Lane: $lane" else ""
    if (left1.isNotEmpty() || right1.isNotEmpty()) twoColRows.add(TwoCol(left1, right1))
    if (left2.isNotEmpty() || right2.isNotEmpty()) twoColRows.add(TwoCol(left2, right2))

    // Estimate per-row height using bodyPaint metrics
    val rowHeight = (bodyPaint.textSize + 10).toInt() // a little padding below baseline
    totalHeight += rowHeight * twoColRows.size

    // Prepare items (if any) for graphics-only rendering
    val parsedItems = mutableListOf<Pair<String,String>>()
    items?.mapNotNull { it as? Map<*, *> }?.forEach { item ->
      val qty = (item["quantity"] as? String)?.trim().orEmpty().ifEmpty { "1" }
      val name = (item["name"] as? String)?.trim().orEmpty().ifEmpty { "Item" }
      val priceRaw = (item["price"] as? String)?.trim().orEmpty().ifEmpty { "0.00" }
      val repeatStr = (item["repeat"] as? String)?.trim().orEmpty()
      val repeatN = repeatStr.toIntOrNull() ?: 1
      val leftText = "$qty x $name"
      val rightText = "$priceRaw"
      repeat(repeatN.coerceAtLeast(1).coerceAtMost(200)) {
        parsedItems.add(Pair(leftText, rightText))
      }
    }

    // Reserve space: gap + first line + items + second line + gap after second line
    val gapBeforeLinesPx = (bodyPaint.textSize).toInt()
    val lineThicknessPx = 4
    val interItemLineSpacing = 8
    val gapAfterSecondLinePx = (bodyPaint.textSize * 0.6f).toInt().coerceAtLeast(8)
    var itemsBlockHeight = 0
    if (parsedItems.isNotEmpty()) {
      val lineHeight = (bodyPaint.textSize + 4).toInt()
      itemsBlockHeight = parsedItems.size * (lineHeight + interItemLineSpacing)
    }
    totalHeight += gapBeforeLinesPx + lineThicknessPx + itemsBlockHeight + lineThicknessPx + gapAfterSecondLinePx

    val footerLayout = if (footer.isNotEmpty()) buildLayout(footer, bodyPaint, Layout.Alignment.ALIGN_CENTER) else null
    if (footerLayout != null) {
      totalHeight += footerLayout.height
    }

    // Draw to bitmap
    val height = totalHeight + padding * 2
    val bmp = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bmp)
    canvas.drawColor(Color.WHITE)
    var y = padding

    // Draw text layouts first (those already in layouts list)
    for (layout in layouts) {
      canvas.save()
      canvas.translate(padding.toFloat(), y.toFloat())
      layout.draw(canvas)
      canvas.restore()
      y += layout.height
    }

    // Draw manual two-column rows with precise right alignment
    if (twoColRows.isNotEmpty()) {
      val availableWidth = (width - padding * 2).toFloat()
      // Reserve ~60% for left column, rest for right column; adjust if right is long.
      val baseLeftWidth = availableWidth * 0.55f
      for (row in twoColRows) {
        val (l, r) = row
        // Measure right text width
        val rightWidth = bodyPaint.measureText(r)
        // Dynamic left max: ensure right text always fits with a small gap
        val gap = 12f
        val leftMax = (availableWidth - rightWidth - gap).coerceAtLeast(availableWidth * 0.35f)
        val leftWidth = minOf(baseLeftWidth, leftMax)

        // Draw left (wrap if needed)
        if (l.isNotEmpty()) {
          val leftLayout = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            StaticLayout.Builder.obtain(l, 0, l.length, bodyPaint, leftWidth.toInt())
              .setAlignment(Layout.Alignment.ALIGN_NORMAL)
              .setIncludePad(false)
              .build()
          } else {
            @Suppress("DEPRECATION")
            StaticLayout(l, bodyPaint, leftWidth.toInt(), Layout.Alignment.ALIGN_NORMAL, 1.0f, 0f, false)
          }
          canvas.save()
            canvas.translate(padding.toFloat(), y.toFloat())
            leftLayout.draw(canvas)
          canvas.restore()
        }
        // Draw right (single line) aligned to right edge
        if (r.isNotEmpty()) {
          val baseline = y + bodyPaint.textSize
          val rightEdge = width - padding
          canvas.drawText(r, rightEdge.toFloat(), baseline - 4, bodyPaint.apply { textAlign = android.graphics.Paint.Align.RIGHT })
          bodyPaint.textAlign = android.graphics.Paint.Align.LEFT // reset
        }
        y += rowHeight
      }
    }

    // Draw gap then first ruled line
    y += gapBeforeLinesPx
    val leftX = padding
    val rightX = width - padding
    val linePaint = android.graphics.Paint().apply {
      color = Color.BLACK
      style = android.graphics.Paint.Style.FILL
      isAntiAlias = false
    }
    canvas.drawRect(leftX.toFloat(), y.toFloat(), rightX.toFloat(), (y + lineThicknessPx).toFloat(), linePaint)
    y += lineThicknessPx + 10

    // Draw items if present (left/right columns)
    if (parsedItems.isNotEmpty()) {
      val availableWidth = (width - padding * 2)
      val leftColWidth = (availableWidth * 0.65).toInt()
      val rightColWidth = availableWidth - leftColWidth
      val leftXText = padding
      val rightXText = padding + leftColWidth
      val textPaintLeft = TextPaint(bodyPaint)
      val textPaintRight = TextPaint(bodyPaint)
      textPaintRight.textAlign = android.graphics.Paint.Align.RIGHT
      parsedItems.forEach { (l, r) ->
        // Left text clipped to column
        val leftLayout = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
          StaticLayout.Builder.obtain(l, 0, l.length, textPaintLeft, leftColWidth)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setIncludePad(false)
            .build()
        } else {
          @Suppress("DEPRECATION")
          StaticLayout(l, textPaintLeft, leftColWidth, Layout.Alignment.ALIGN_NORMAL, 1.0f, 0f, false)
        }
        canvas.save()
        canvas.translate(leftXText.toFloat(), y.toFloat())
        leftLayout.draw(canvas)
        canvas.restore()
        // Right text (single line) aligned right
        val priceY = y + bodyPaint.textSize
        canvas.drawText(r, (rightXText + rightColWidth).toFloat(), priceY - 6, textPaintRight)
        val lineH = leftLayout.height.coerceAtLeast(bodyPaint.textSize.toInt()) + interItemLineSpacing
        y += lineH
      }
    }

    // Second ruled line
    canvas.drawRect(leftX.toFloat(), y.toFloat(), rightX.toFloat(), (y + lineThicknessPx).toFloat(), linePaint)
    y += lineThicknessPx + gapAfterSecondLinePx

    // Footer centered if present
    if (footerLayout != null) {
      canvas.save()
      canvas.translate(padding.toFloat(), y.toFloat())
      footerLayout.draw(canvas)
      canvas.restore()
      y += footerLayout.height
    }

    return bmp
  }

  // Create a placeholder bitmap (solid black square)
  private fun createPlaceholderBitmap(width: Int, height: Int): Bitmap {
    val w = width.coerceIn(8, 576)
    val h = height.coerceAtLeast(8)
    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(bmp)
    canvas.drawColor(Color.BLACK)
    return bmp
  }

  // Flatten bitmap onto white background at target width (keep aspect)
  private fun flattenBitmap(src: Bitmap, targetWidth: Int): Bitmap {
    val tw = targetWidth.coerceIn(8, 576)
    val aspect = src.height.toFloat() / src.width.toFloat().coerceAtLeast(1f)
    val th = (tw * aspect).toInt().coerceAtLeast(8)
    val out = Bitmap.createBitmap(tw, th, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(out)
    canvas.drawColor(Color.WHITE)
    val dst = android.graphics.Rect(0, 0, tw, th)
    canvas.drawBitmap(src, null, dst, null)
    return out
  }

  // Center a bitmap on a full-width canvas to force horizontal centering
  private fun centerOnCanvas(src: Bitmap, canvasWidth: Int): Bitmap {
    val cw = canvasWidth.coerceIn(8, 576)
    val aspect = src.height.toFloat() / src.width.toFloat().coerceAtLeast(1f)
    val targetW = src.width.coerceAtMost(cw)
    val targetH = (targetW * aspect).toInt().coerceAtLeast(8)
    val out = Bitmap.createBitmap(cw, targetH, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(out)
    canvas.drawColor(Color.WHITE)
    val left = (cw - targetW) / 2
    val dst = android.graphics.Rect(left, 0, left + targetW, targetH)
    canvas.drawBitmap(src, null, dst, null)
    return out
  }

  // Decode Base64 (with optional data URI) to Bitmap
  private fun decodeBase64ToBitmap(b64: String?): Bitmap? {
    if (b64.isNullOrEmpty()) return null
    return try {
      val trimmed = b64.trim()
      val payload = if (trimmed.startsWith("data:image")) trimmed.substringAfter(",") else trimmed
      val clean = payload.replace("\n", "").replace("\r", "").replace(" ", "")
      val bytes = android.util.Base64.decode(clean, android.util.Base64.DEFAULT)
      android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
    } catch (e: Exception) {
      null
    }
  }
}