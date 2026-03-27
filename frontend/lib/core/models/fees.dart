class FeeStructureModel {
  final int id;
  final String academicYear;
  final int grade;
  final double baseAmount;
  final double economicsFee;
  final double computerFee;
  final double aiFee;
  final double totalAmount;

  const FeeStructureModel({
    required this.id,
    required this.academicYear,
    required this.grade,
    required this.baseAmount,
    required this.economicsFee,
    required this.computerFee,
    required this.aiFee,
    required this.totalAmount,
  });

  factory FeeStructureModel.fromJson(Map<String, dynamic> json) =>
      FeeStructureModel(
        id: json['id'] as int,
        academicYear: json['academic_year'] as String,
        grade: json['grade'] as int,
        baseAmount: (json['base_amount'] as num).toDouble(),
        economicsFee: (json['economics_fee'] as num).toDouble(),
        computerFee: (json['computer_fee'] as num).toDouble(),
        aiFee: (json['ai_fee'] as num).toDouble(),
        totalAmount: (json['total_amount'] as num).toDouble(),
      );
}

class FeePaymentModel {
  final int id;
  final int studentId;
  final double amount;
  final DateTime paidAt;
  final int? updatedByAdminId;
  final String? notes;

  const FeePaymentModel({
    required this.id,
    required this.studentId,
    required this.amount,
    required this.paidAt,
    this.updatedByAdminId,
    this.notes,
  });

  factory FeePaymentModel.fromJson(Map<String, dynamic> json) =>
      FeePaymentModel(
        id: json['id'] as int,
        studentId: json['student_id'] as int,
        amount: (json['amount'] as num).toDouble(),
        paidAt: DateTime.parse(json['paid_at'] as String),
        updatedByAdminId: json['updated_by_admin_id'] as int?,
        notes: json['notes'] as String?,
      );
}

class PaymentInfoModel {
  final int id;
  final String? bankName;
  final String? accountHolder;
  final String? accountNumber;
  final String? ifsc;
  final String? upiId;
  final String? qrCodeUrl;
  final DateTime updatedAt;

  const PaymentInfoModel({
    required this.id,
    this.bankName,
    this.accountHolder,
    this.accountNumber,
    this.ifsc,
    this.upiId,
    this.qrCodeUrl,
    required this.updatedAt,
  });

  factory PaymentInfoModel.fromJson(Map<String, dynamic> json) =>
      PaymentInfoModel(
        id: json['id'] as int,
        bankName: json['bank_name'] as String?,
        accountHolder: json['account_holder'] as String?,
        accountNumber: json['account_number'] as String?,
        ifsc: json['ifsc'] as String?,
        upiId: json['upi_id'] as String?,
        qrCodeUrl: json['qr_code_url'] as String?,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );
}

class StudentFeeSummaryModel {
  final int studentId;
  final String academicYear;
  final int grade;
  final double totalFee;
  final double totalPaid;
  final double balanceDue;
  final double baseAmount;
  final double economicsFee;
  final double computerFee;
  final double aiFee;
  final List<FeePaymentModel> payments;
  final PaymentInfoModel? paymentInfo;

  const StudentFeeSummaryModel({
    required this.studentId,
    required this.academicYear,
    required this.grade,
    required this.totalFee,
    required this.totalPaid,
    required this.balanceDue,
    this.baseAmount = 0.0,
    this.economicsFee = 0.0,
    this.computerFee = 0.0,
    this.aiFee = 0.0,
    required this.payments,
    this.paymentInfo,
  });

  factory StudentFeeSummaryModel.fromJson(Map<String, dynamic> json) =>
      StudentFeeSummaryModel(
        studentId: json['student_id'] as int,
        academicYear: json['academic_year'] as String,
        grade: json['grade'] as int,
        totalFee: (json['total_fee'] as num).toDouble(),
        totalPaid: (json['total_paid'] as num).toDouble(),
        balanceDue: (json['balance_due'] as num).toDouble(),
        baseAmount: (json['base_amount'] as num? ?? 0).toDouble(),
        economicsFee: (json['economics_fee'] as num? ?? 0).toDouble(),
        computerFee: (json['computer_fee'] as num? ?? 0).toDouble(),
        aiFee: (json['ai_fee'] as num? ?? 0).toDouble(),
        payments: (json['payments'] as List<dynamic>)
            .map((p) => FeePaymentModel.fromJson(p as Map<String, dynamic>))
            .toList(),
        paymentInfo: json['payment_info'] != null
            ? PaymentInfoModel.fromJson(
                json['payment_info'] as Map<String, dynamic>)
            : null,
      );
}
