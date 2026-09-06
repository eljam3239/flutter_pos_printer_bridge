/// Receipt string localization for [PrinterBridge].
///
/// Receipt text is deliberately kept independent of whatever localization the
/// host app uses. A printer has its own configured receipt language, which is
/// frequently *not* the language the operator is running the UI in — a
/// bilingual store may run the register in English while the customer-facing
/// receipt prints in French. Binding receipt strings to the app's UI locale
/// makes that impossible to express.
///
/// Call sites read the ambient [langCon]. To render a receipt in a specific
/// language without disturbing the app, wrap the print in
/// [PrinterLocalizations.withPrintLanguage].
library;

/// Receipt strings for a single language.
///
/// Supported codes are `en`, `fr`, `es` and `it`; an unrecognized code falls
/// back to English rather than printing blanks, since a receipt with missing
/// labels is worse than one in the wrong language.
class PrinterLocalizations {
  final String languageCode;

  const PrinterLocalizations(this.languageCode);

  static PrinterLocalizations _current = const PrinterLocalizations('en');

  /// The localization every `langCon.*` call site reads.
  static PrinterLocalizations get current => _current;

  /// Sets the default receipt language for subsequent prints.
  static set current(PrinterLocalizations value) => _current = value;

  /// Runs [body] with receipt strings reported in [code], then restores the
  /// previous language.
  ///
  /// Used by [PrinterBridge.printReceipt] and
  /// [PrinterBridge.printTerminalReceipt] so a printer's own configured
  /// receipt language never leaks into the rest of the application.
  static Future<T> withPrintLanguage<T>(
    String code,
    Future<T> Function() body,
  ) async {
    final previous = _current;
    _current = PrinterLocalizations(code);
    try {
      return await body();
    } finally {
      _current = previous;
    }
  }

  /// Resolved language, narrowed to a code that has translations.
  String get _effectiveLanguage =>
      const {'en', 'fr', 'es', 'it'}.contains(languageCode)
          ? languageCode
          : 'en';

  String get subTotal => switch (_effectiveLanguage) {
        "en" => "Subtotal",
        "fr" => "Sous-total",
        "es" => "Subtotal",
        "it" => "Subtotale",
        String() => "",
      };

  String get total => switch (_effectiveLanguage) {
        "en" => "Total",
        "fr" => "Totale",
        "es" => "Total",
        "it" => "Totale",
        String() => "",
      };

  String get discount => switch (_effectiveLanguage) {
        "en" => "Discount",
        "fr" => "Réductions",
        "es" => "Descuento",
        "it" => "Sconto",
        String() => "",
      };

  String get authCode => switch (_effectiveLanguage) {
        "en" => "Auth Code",
        "fr" => "Code d'autorisation",
        "es" => "Código de autorización",
        "it" => "Codice di autorizzazione",
        String() => "",
      };

  String get ref => switch (_effectiveLanguage) {
        "en" => "Ref",
        "fr" => "Réf",
        "es" => "Ref",
        "it" => "Rif",
        String() => "",
      };

  String get merchantIdLabel => switch (_effectiveLanguage) {
        "en" => "Merc. ID",
        "fr" => "ID Marchand",
        "es" => "ID Comerciante",
        "it" => "ID Commerciante",
        String() => "",
      };

  String get terminalIdLabel => switch (_effectiveLanguage) {
        "en" => "Term. ID",
        "fr" => "ID Terminal",
        "es" => "ID Terminal",
        "it" => "ID Terminale",
        String() => "",
      };

  String get rrnLabel => switch (_effectiveLanguage) {
        "en" => "RRN",
        "fr" => "RRN",
        "es" => "RRN",
        "it" => "RRN",
        String() => "",
      };

  String get batchNumberLabel => switch (_effectiveLanguage) {
        "en" => "Batch#",
        "fr" => "Lot n°",
        "es" => "N.º de lote",
        "it" => "Lotto n.",
        String() => "",
      };

  String get noSignatureRequired => switch (_effectiveLanguage) {
        "en" => "No Signature Required",
        "fr" => "Signature non requise",
        "es" => "No se requiere firma",
        "it" => "Firma non richiesta",
        String() => "",
      };

  String get traceNumberLabel => switch (_effectiveLanguage) {
        "en" => "Trace",
        "fr" => "Trace",
        "es" => "Rastreo",
        "it" => "Traccia",
        String() => "",
      };

  String get availableBalanceLabel => switch (_effectiveLanguage) {
        "en" => "Balance",
        "fr" => "Solde",
        "es" => "Saldo",
        "it" => "Saldo",
        String() => "",
      };

  String get transactionRecord => switch (_effectiveLanguage) {
        "en" => "Transaction Record",
        "fr" => "Relevé de Transaction",
        "es" => "Registro de transacción",
        "it" => "Registro della transazione",
        String() => "",
      };

  String get saleLabel => switch (_effectiveLanguage) {
        "en" => "SALE",
        "fr" => "VENTE",
        "es" => "VENTA",
        "it" => "VENDITA",
        String() => "",
      };

  String get refundLabel => switch (_effectiveLanguage) {
        "en" => "REFUND",
        "fr" => "REMIS",
        "es" => "REEMBOLSO",
        "it" => "RIMBORSO",
        String() => "",
      };

  String get voidSaleLabel => switch (_effectiveLanguage) {
        "en" => "VOID SALE",
        "fr" => "ANNULATION VENTE",
        "es" => "ANULAR VENTA",
        "it" => "ANNULLA VENDITA",
        String() => "",
      };

  String get voidRefundLabel => switch (_effectiveLanguage) {
        "en" => "VOID REFUND",
        "fr" => "ANNULATION REMBOURSEMENT",
        "es" => "ANULAR REEMBOLSO",
        "it" => "ANNULLA RIMBORSO",
        String() => "",
      };

  String get cancelLabel => switch (_effectiveLanguage) {
        "en" => "CANCEL",
        "fr" => "ANNULER",
        "es" => "CANCELAR",
        "it" => "ANNULLA",
        String() => "",
      };

  String get clientCopy => switch (_effectiveLanguage) {
        "en" => "CUSTOMER COPY",
        "fr" => "COPIE DU CLIENT",
        "es" => "COPIA DEL CLIENTE",
        "it" => "COPIA CLIENTE",
        String() => "",
      };

  String get merchantCopy => switch (_effectiveLanguage) {
        "en" => "MERCHANT COPY",
        "fr" => "COPIE DU MARCHAND",
        "es" => "COPIA DEL COMERCIANTE",
        "it" => "COPIA ESERCENTE",
        String() => "",
      };

  String get aid => switch (_effectiveLanguage) {
        "en" => "AID",
        "fr" => "AID",
        "es" => "AID",
        "it" => "AID",
        String() => "",
      };

  String get tc => switch (_effectiveLanguage) {
        "en" => "TC",
        "fr" => "TC",
        "es" => "TC",
        "it" => "TC",
        String() => "",
      };

  String get aac => switch (_effectiveLanguage) {
        "en" => "AAC",
        "fr" => "AAC",
        "es" => "AAC",
        "it" => "AAC",
        String() => "",
      };

  String get tvr => switch (_effectiveLanguage) {
        "en" => "TVR",
        "fr" => "TVR",
        "es" => "TVR",
        "it" => "TVR",
        String() => "",
      };

  String get tsi => switch (_effectiveLanguage) {
        "en" => "TSI",
        "fr" => "TSI",
        "es" => "TSI",
        "it" => "TSI",
        String() => "",
      };

  String get lane => switch (_effectiveLanguage) {
        "en" => "Lane",
        "fr" => "Caisse",
        "es" => "Caja",
        "it" => "Cassa",
        String() => "",
      };

  String get cashier => switch (_effectiveLanguage) {
        "en" => "Cashier",
        "fr" => "Caissière",
        "es" => "Cajero",
        "it" => "Cassiere",
        String() => "",
      };

  String get paymentMethod => switch (_effectiveLanguage) {
        "en" => "Payment Method",
        "fr" => "Mode de Paiement",
        "es" => "Método de pago",
        "it" => "Metodo di pagamento",
        String() => "",
      };

  String get amountLabel => switch (_effectiveLanguage) {
        "en" => "AMOUNT",
        "fr" => "MONTANT",
        "es" => "IMPORTE",
        "it" => "IMPORTO",
        String() => "",
      };

  String get subtotalLabel => switch (_effectiveLanguage) {
        "en" => "Subtotal",
        "fr" => "Sous-total",
        "es" => "Subtotal",
        "it" => "Subtotale",
        String() => "",
      };

  String get receiptNo => switch (_effectiveLanguage) {
        "en" => "Receipt No",
        "fr" => "No de reçu",
        "es" => "N.º de recibo",
        "it" => "N. ricevuta",
        String() => "",
      };

  String get receipt => switch (_effectiveLanguage) {
        "en" => "Receipt",
        "fr" => "Reçu de facture",
        "es" => "Recibo",
        "it" => "Ricevuta",
        String() => "",
      };

  String get returns => switch (_effectiveLanguage) {
        "en" => "Returns",
        "fr" => "Retours",
        "es" => "Devoluciones",
        "it" => "Resi",
        String() => "",
      };

  String get card => switch (_effectiveLanguage) {
        "en" => "Card",
        "fr" => "Carte",
        "es" => "Tarjeta",
        "it" => "Scheda",
        String() => "",
      };

  String get tradeInsExchanges => switch (_effectiveLanguage) {
        "en" => "Trade-ins & Exchanges",
        "fr" => "Reprises & Échanges / Trade-ins & Exchanges",
        "es" => "Entregas a cuenta y cambios",
        "it" => "Permute e cambi",
        String() => "",
      };

  // --- Service-layer strings ------------------------------------------

  String get loyalty => switch (_effectiveLanguage) {
        "en" => "Loyalty",
        "fr" => "Fidélité",
        "es" => "Fidelidad",
        "it" => "Fedeltà",
        String() => "",
      };

  String get storeCredit => switch (_effectiveLanguage) {
        "en" => "Store Credit",
        "fr" => "Crédit du magasin",
        "es" => "Crédito de la tienda",
        "it" => "Credito del negozio",
        String() => "",
      };

  String get giftCard => switch (_effectiveLanguage) {
        "en" => "Gift Card",
        "fr" => "Carte Cadeau",
        "es" => "Tarjeta de regalo",
        "it" => "Carta regalo",
        String() => "",
      };

  String get cash => switch (_effectiveLanguage) {
        "en" => "Cash",
        "fr" => "Argent",
        "es" => "Efectivo",
        "it" => "Contanti",
        String() => "",
      };

  String get loyaltyPoints => switch (_effectiveLanguage) {
        "en" => "Loyalty Points",
        "fr" => "Points de Fidélité",
        "es" => "Puntos de fidelidad",
        "it" => "Punti fedeltà",
        String() => "",
      };

  String get credit => switch (_effectiveLanguage) {
        "en" => "Credit",
        "fr" => "Crédit",
        "es" => "Crédito",
        "it" => "Credito",
        String() => "",
      };

  String get debit => switch (_effectiveLanguage) {
        "en" => "Debit",
        "fr" => "Débit",
        "es" => "Débito",
        "it" => "Debito",
        String() => "",
      };

  String get giftReceipt => switch (_effectiveLanguage) {
        "en" => 'Gift Receipt',
        "fr" => 'Reçu',
        "es" => "Recibo de regalo",
        "it" => "Ricevuta regalo",
        String() => "",
      };

  String get cheque => switch (_effectiveLanguage) {
        "en" => 'cheque',
        "fr" => 'chèque',
        "es" => "cheque",
        "it" => "assegno",
        String() => "",
      };

  String get noDefaultReceiptPrinter => switch (_effectiveLanguage) {
        "en" =>
          'No default receipt printer set. Please go to Settings > Printers and set a default receipt printer.',
        "fr" =>
          "Aucune imprimante de reçu par défaut définie. Veuillez aller dans Paramètres > Imprimantes et définir une imprimante de reçu par défaut.",
        "es" =>
          "No hay una impresora de recibos predeterminada configurada. Vaya a Configuración > Impresoras y establezca una impresora de recibos predeterminada.",
        "it" =>
          "Nessuna stampante degli scontrini predefinita impostata. Vai su Impostazioni > Stampanti e imposta una stampante degli scontrini predefinita.",
        String() => "",
      };

  String get defaultReceiptPrintFail => switch (_effectiveLanguage) {
        "en" =>
          'Receipt print failed. Please check that your device is connected and the printer is powered on. If issues persist, see our FAQ.',
        "fr" =>
          "L'impression du reçu a échoué. Veuillez vérifier que votre appareil est connecté et que l'imprimante est sous tension. Si les problèmes persistent, consultez notre FAQ pour obtenir de l'aide.",
        "es" =>
          "Error al imprimir el recibo. Verifique que su dispositivo esté conectado y que la impresora esté encendida. Si el problema persiste, consulte nuestras preguntas frecuentes.",
        "it" =>
          "Stampa dello scontrino non riuscita. Verifica che il dispositivo sia connesso e che la stampante sia accesa. Se il problema persiste, consulta le nostre domande frequenti.",
        String() => "",
      };

  String get noDefaultLabelPrinter => switch (_effectiveLanguage) {
        "en" =>
          'No default label printer set. Please go to Settings > Printers and set a default label printer.',
        "fr" =>
          "Aucune imprimante d'étiquette par défaut définie. Veuillez aller dans Paramètres > Imprimantes et définir une imprimante d'étiquette par défaut.",
        "es" =>
          "No hay una impresora de etiquetas predeterminada configurada. Vaya a Configuración > Impresoras y establezca una impresora de etiquetas predeterminada.",
        "it" =>
          "Nessuna stampante di etichette predefinita impostata. Vai su Impostazioni > Stampanti e imposta una stampante di etichette predefinita.",
        String() => "",
      };

  String get defaultLabelPrintFail => switch (_effectiveLanguage) {
        "en" =>
          'Label print failed. Please check that your device is connected and the printer is powered on. If issues persist, see our FAQ.',
        "fr" =>
          "L'impression de l'étiquette a échoué. Veuillez vérifier que votre appareil est connecté et que l'imprimante est sous tension. Si les problèmes persistent, consultez notre FAQ pour obtenir de l'aide.",
        "es" =>
          "Error al imprimir la etiqueta. Verifique que su dispositivo esté conectado y que la impresora esté encendida. Si el problema persiste, consulte nuestras preguntas frecuentes.",
        "it" =>
          "Stampa dell'etichetta non riuscita. Verifica che il dispositivo sia connesso e che la stampante sia accesa. Se il problema persiste, consulta le nostre domande frequenti.",
        String() => "",
      };

  String get testStore => switch (_effectiveLanguage) {
        "en" => 'Test Store',
        "fr" => 'Magasin de test',
        "es" => "Tienda de prueba",
        "it" => "Negozio di prova",
        String() => "",
      };

  String get backupStoreLocationFooter => switch (_effectiveLanguage) {
        "en" => 'Thank you for shopping with us!',
        "fr" => 'Merci de votre visite !',
        "es" => "¡Gracias por comprar con nosotros!",
        "it" => "Grazie per aver fatto acquisti da noi!",
        String() => "",
      };

}

/// The ambient receipt localization.
///
/// Named to read naturally at the ~130 call sites inside the receipt builders,
/// where it appears once per printed label.
PrinterLocalizations get langCon => PrinterLocalizations.current;
