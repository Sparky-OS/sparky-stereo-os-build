// SPDX-License-Identifier: GPL-3.0-or-later
import com.itextpdf.text.*;
import com.itextpdf.text.pdf.*;
import java.io.*;
public class CreatePdf {
 public static void main(String[] args) throws Exception {
  Document d=new Document(); PdfWriter.getInstance(d,new FileOutputStream(args[0]));
  d.open();d.add(new Paragraph("SYNTHETIC DOCUMENT. NO PERSONAL OR COURT INFORMATION."));d.close();
 }
}
