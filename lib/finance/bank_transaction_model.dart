// FILE: lib/finance/bank_transaction_model.dart

class BankTransaction {
  final String id;
  final DateTime date;
  final String particulars; // Kisse aaya ya kisko gaya
  final String reference;   // Bill No ya Cheque No
  final double amountIn;    // Credit (Bank mein aaya)
  final double amountOut;   // Debit (Bank se nikla)
  final String type;        // VOUCHER, CHEQUE, ya CONTRA

  BankTransaction({
    required this.id,
    required this.date,
    required this.particulars,
    required this.reference,
    this.amountIn = 0.0,
    this.amountOut = 0.0,
    required this.type,
  });
}
