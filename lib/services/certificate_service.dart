import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class CertificateService {
  static Future<Uint8List> generateCertificatePDF({
    required String volunteerName,
    required String certificateTitle,
    required DateTime date,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(40),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.blue900, width: 10),
            ),
            child: pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  pw.Text(
                    'SIJIL PENGHARGAAN',
                    style: pw.TextStyle(
                      fontSize: 40,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue900,
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'Dengan sukacitanya dianugerahkan kepada',
                    style: const pw.TextStyle(fontSize: 18),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    volunteerName.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 32,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Text(
                    'Atas sumbangan dan dedikasi sebagai',
                    style: const pw.TextStyle(fontSize: 18),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    certificateTitle,
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.red900,
                    ),
                  ),
                  pw.SizedBox(height: 40),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        children: [
                          pw.Container(
                            width: 150,
                            height: 1,
                            color: PdfColors.black,
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text('Tarikh: ${date.day}/${date.month}/${date.year}'),
                        ],
                      ),
                      pw.Column(
                        children: [
                          pw.Container(
                            width: 150,
                            height: 1,
                            color: PdfColors.black,
                          ),
                          pw.SizedBox(height: 5),
                          pw.Text('Pihak Pengurusan SIGAP'),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }
}
