// FILE: lib/compliance/gst_offline_engine/gst_offline_models.dart
import 'dart:convert';

/// Complete GSTN GSTR-1 Offline Data Transfer Object (DTO)
/// Matches CBIC & GST Portal (gst.gov.in) Schema V3.2 / Release 3.2
class Gstr1OfflinePayload {
  final String gstin;
  final String fp; // MMYYYY (e.g. "102026")
  final double gt; // Gross turnover previous FY
  final double curGt; // Current FY gross turnover
  final String version; // "GST_3.2.4" (Matches Release 3.2.4)
  final String hash;
  
  final List<GstB2bGroup> b2b;
  final List<GstB2clGroup> b2cl;
  final List<GstB2csItem> b2cs;
  final List<GstCdnrGroup> cdnr;
  final List<GstCdnurItem> cdnur;
  final List<GstHsnItem> hsnData;
  final List<GstDocGroup> docIssue;

  Gstr1OfflinePayload({
    required this.gstin,
    required this.fp,
    this.gt = 0.0,
    this.curGt = 0.0,
    this.version = "GST_3.2.4",
    this.hash = "hash",
    required this.b2b,
    required this.b2cl,
    required this.b2cs,
    required this.cdnr,
    required this.cdnur,
    required this.hsnData,
    required this.docIssue,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      "gstin": gstin,
      "fp": fp,
      "version": version,
      "hash": hash,
    };
    if (gt > 0) data["gt"] = gt;
    if (curGt > 0) data["cur_gt"] = curGt;

    if (b2b.isNotEmpty) {
      data["b2b"] = b2b.map((g) => g.toJson()).toList();
    }
    if (b2cl.isNotEmpty) {
      data["b2cl"] = b2cl.map((g) => g.toJson()).toList();
    }
    if (b2cs.isNotEmpty) {
      data["b2cs"] = b2cs.map((item) => item.toJson()).toList();
    }
    if (cdnr.isNotEmpty) {
      data["cdnr"] = cdnr.map((g) => g.toJson()).toList();
    }
    if (cdnur.isNotEmpty) {
      data["cdnur"] = cdnur.map((item) => item.toJson()).toList();
    }
    if (hsnData.isNotEmpty) {
      data["hsn"] = {
        "data": hsnData.map((item) => item.toJson()).toList(),
      };
    }
    if (docIssue.isNotEmpty) {
      data["doc_issue"] = {
        "doc_det": docIssue.map((g) => g.toJson()).toList(),
      };
    }

    return data;
  }

  String toFormattedJson() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }
}

/// B2B: Registered Supplier Group (Grouped by Buyer GSTIN)
class GstB2bGroup {
  final String ctin; // Counterparty GSTIN (15 chars)
  final List<GstInvoice> inv;

  GstB2bGroup({required this.ctin, required this.inv});

  Map<String, dynamic> toJson() => {
    "ctin": ctin,
    "inv": inv.map((i) => i.toJson()).toList(),
  };
}

/// Invoice Details for B2B
class GstInvoice {
  final String inum; // Invoice Number
  final String idt;  // Date formatted dd-MM-yyyy
  final double val;  // Total Invoice Value
  final String pos;  // 2-digit State Code
  final String rchrg; // "Y" or "N" (Reverse Charge)
  final String invTyp; // "R" (Regular), "SEZWP", "SEZWOP", "DE"
  final List<GstTaxItem> itms;

  GstInvoice({
    required this.inum,
    required this.idt,
    required this.val,
    required this.pos,
    this.rchrg = "N",
    this.invTyp = "R",
    required this.itms,
  });

  Map<String, dynamic> toJson() => {
    "inum": inum,
    "idt": idt,
    "val": val,
    "pos": pos,
    "rchrg": rchrg,
    "inv_typ": invTyp,
    "itms": itms.map((i) => i.toJson()).toList(),
  };
}

/// B2CL: Large Consumer Invoices (Inter-state unregistered > ₹1L / ₹2.5L)
class GstB2clGroup {
  final String pos;
  final List<GstB2clInvoice> inv;

  GstB2clGroup({required this.pos, required this.inv});

  Map<String, dynamic> toJson() => {
    "pos": pos,
    "inv": inv.map((i) => i.toJson()).toList(),
  };
}

class GstB2clInvoice {
  final String inum;
  final String idt;
  final double val;
  final List<GstTaxItem> itms;

  GstB2clInvoice({
    required this.inum,
    required this.idt,
    required this.val,
    required this.itms,
  });

  Map<String, dynamic> toJson() => {
    "inum": inum,
    "idt": idt,
    "val": val,
    "itms": itms.map((i) => i.toJson()).toList(),
  };
}

/// B2CS: Small Consumer Invoices (Aggregated by POS and Tax Rate)
class GstB2csItem {
  final String splyTy; // "INTRA" or "INTER"
  final double rt;     // Tax Rate (e.g. 5.0, 12.0, 18.0)
  final String typ;    // "OE" (Other than E-Commerce)
  final String pos;    // 2-digit State Code
  final double txval;  // Taxable Value
  final double iamt;   // IGST
  final double camt;   // CGST
  final double samt;   // SGST
  final double csamt;  // Cess Amount

  GstB2csItem({
    required this.splyTy,
    required this.rt,
    this.typ = "OE",
    required this.pos,
    required this.txval,
    required this.iamt,
    required this.camt,
    required this.samt,
    this.csamt = 0.0,
  });

  Map<String, dynamic> toJson() => {
    "sply_ty": splyTy,
    "rt": rt,
    "typ": typ,
    "pos": pos,
    "txval": txval,
    "iamt": iamt,
    "camt": camt,
    "samt": samt,
    "csamt": csamt,
  };
}

/// CDNR: Credit / Debit Notes to Registered Buyers
class GstCdnrGroup {
  final String ctin;
  final List<GstCreditNote> nt;

  GstCdnrGroup({required this.ctin, required this.nt});

  Map<String, dynamic> toJson() => {
    "ctin": ctin,
    "nt": nt.map((n) => n.toJson()).toList(),
  };
}

/// CDNUR: Credit / Debit Notes to Unregistered Buyers
class GstCdnurItem {
  final String typ; // "B2CL" or "B2CS"
  final String ntNum;
  final String ntDt;
  final double val;
  final String ntty; // "C" (Credit) or "D" (Debit)
  final String pos;
  final String pGst; // "N"
  final List<GstTaxItem> itms;

  GstCdnurItem({
    this.typ = "B2CS",
    required this.ntNum,
    required this.ntDt,
    required this.val,
    this.ntty = "C",
    required this.pos,
    this.pGst = "N",
    required this.itms,
  });

  Map<String, dynamic> toJson() => {
    "typ": typ,
    "nt_num": ntNum,
    "nt_dt": ntDt,
    "val": val,
    "ntty": ntty,
    "pos": pos,
    "p_gst": pGst,
    "itms": itms.map((i) => i.toJson()).toList(),
  };
}

class GstCreditNote {
  final String ntNum;
  final String ntDt;
  final double val;
  final String ntty; // "C" for Credit note
  final String pos;
  final String rchrg;
  final String invTyp;
  final String pGst;
  final List<GstTaxItem> itms;

  GstCreditNote({
    required this.ntNum,
    required this.ntDt,
    required this.val,
    this.ntty = "C",
    required this.pos,
    this.rchrg = "N",
    this.invTyp = "R",
    this.pGst = "N",
    required this.itms,
  });

  Map<String, dynamic> toJson() => {
    "nt_num": ntNum,
    "nt_dt": ntDt,
    "val": val,
    "ntty": ntty,
    "pos": pos,
    "rchrg": rchrg,
    "inv_typ": invTyp,
    "p_gst": pGst,
    "itms": itms.map((i) => i.toJson()).toList(),
  };
}

/// Item Line Breakdown (Tax Slab level)
class GstTaxItem {
  final int num;
  final double rt;
  final double txval;
  final double iamt;
  final double camt;
  final double samt;
  final double csamt;

  GstTaxItem({
    required this.num,
    required this.rt,
    required this.txval,
    required this.iamt,
    required this.camt,
    required this.samt,
    this.csamt = 0.0,
  });

  Map<String, dynamic> toJson() => {
    "num": num,
    "itm_det": {
      "rt": rt,
      "txval": txval,
      "iamt": iamt,
      "camt": camt,
      "samt": samt,
      "csamt": csamt,
    },
  };
}

/// Table 12: HSN Summary Item (Release 3.2 Schema)
class GstHsnItem {
  final int num;
  final String hsnSc; // 4 to 8 digit HSN Code
  final String desc;
  final String uqc;   // "NOS", "BOX", "BTL", etc.
  final double qty;
  final double val;   // Total value (Taxable + Tax)
  final double txval; // Taxable value
  final double iamt;
  final double camt;
  final double samt;
  final double csamt;
  final double rt;    // Mandatory Tax Rate in Release 3.2

  GstHsnItem({
    required this.num,
    required this.hsnSc,
    this.desc = "Medicaments / Pharmaceutical Products",
    this.uqc = "NOS",
    required this.qty,
    required this.val,
    required this.txval,
    required this.iamt,
    required this.camt,
    required this.samt,
    this.csamt = 0.0,
    required this.rt,
  });

  Map<String, dynamic> toJson() => {
    "num": num,
    "hsn_sc": hsnSc,
    "desc": desc,
    "uqc": uqc,
    "qty": qty,
    "val": val,
    "txval": txval,
    "iamt": iamt,
    "camt": camt,
    "samt": samt,
    "csamt": csamt,
    "rt": rt,
  };
}

/// Table 13: Documents Issued Summary
class GstDocGroup {
  final int docNum;
  final String docTyp;
  final List<GstDocSerial> docs;

  GstDocGroup({
    this.docNum = 1,
    this.docTyp = "Invoices for outward supply",
    required this.docs,
  });

  Map<String, dynamic> toJson() => {
    "doc_num": docNum,
    "doc_typ": docTyp,
    "docs": docs.map((d) => d.toJson()).toList(),
  };
}

class GstDocSerial {
  final int num;
  final String from;
  final String to;
  final int totnum;
  final int canc;
  final int netIssue;

  GstDocSerial({
    required this.num,
    required this.from,
    required this.to,
    required this.totnum,
    required this.canc,
    required this.netIssue,
  });

  Map<String, dynamic> toJson() => {
    "num": num,
    "from": from,
    "to": to,
    "totnum": totnum,
    "canc": canc,
    "net_issue": netIssue,
  };
}
