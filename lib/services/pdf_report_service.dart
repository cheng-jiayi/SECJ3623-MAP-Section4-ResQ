import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../core/constants/app_strings.dart';

class PdfReportService {
  static Future<File> generateReportPdf(String reportText, String reportTitle) async {
    final pdf = pw.Document();
    
    // Add page
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return [
            // Header
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(AppStrings.pdfAwanisReportTitle, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
                  pw.Text(
                    '${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}',
                    style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              reportTitle,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 20),
            
            // Content
            pw.Text(
              reportText,
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 1.5),
            ),
            
            pw.SizedBox(height: 30),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(AppStrings.pdfAwanisReportFooter, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
            ),
          ];
        },
      ),
    );

    final directory = await getTemporaryDirectory();
    final fileName = 'Laporan_AWANIS_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final filePath = '${directory.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return file;
  }

  static Future<void> shareReport(File pdfFile) async {
    await Share.shareXFiles(
      [XFile(pdfFile.path)],
      text: 'Laporan Insiden AI - SIGAP',
    );
  }

  static Future<void> downloadReport(File pdfFile) async {
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdfFile.readAsBytes(),
      name: pdfFile.path.split('/').last,
    );
  }
}
