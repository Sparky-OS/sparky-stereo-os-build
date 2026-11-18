// SPDX-License-Identifier: GPL-3.0-or-later
import java.io.*;import java.security.*;import java.security.cert.*;import java.util.*;
import javax.net.ssl.*;
import br.jus.cnj.pje.office.core.imp.PjeWebGlobal;
import org.apache.hc.client5.http.classic.methods.HttpGet;
public class AppTrustProbe {
 public static void main(String[] a) throws Exception {
  Class<?> app=Class.forName("br.jus.cnj.pje.office.core.imp.PjeWebGlobal");
  System.out.println("resource="+app.getResource("/pjeoffice.jks"));
  KeyStore k=KeyStore.getInstance("JKS");
  try(InputStream in=app.getResourceAsStream("/pjeoffice.jks")){k.load(in,"pjeoffice".toCharArray());}
  int icp=0, roots=0,keys=0;
  for(Enumeration<String> en=k.aliases();en.hasMoreElements();){String alias=en.nextElement();if(k.isKeyEntry(alias))keys++;
   X509Certificate c=(X509Certificate)k.getCertificate(alias);
   if(c.getSubjectX500Principal().getName().contains("ICP-Brasil")){icp++;if(c.getSubjectX500Principal().equals(c.getIssuerX500Principal())){roots++;System.out.println("ICP root="+alias+" expires="+c.getNotAfter());}}
  }
  System.out.println("entries="+k.size()+" icp="+icp+" icpRoots="+roots+" keyEntries="+keys);
  if(a.length==2&&a[0].equals("merge")){
   try(InputStream in=new FileInputStream(a[1])){k.setCertificateEntry("synthetic-test-root",CertificateFactory.getInstance("X.509").generateCertificate(in));}
   try(OutputStream out=new FileOutputStream("/scratch/union/pjeoffice.jks")){k.store(out,"pjeoffice".toCharArray());}
   System.out.println("merged entries="+k.size());
  }
  if(a.length==1){try {System.out.println("GET="+PjeWebGlobal.HTTPS_CODEC.get(()->new HttpGet(a[0])));}catch(Exception e){e.printStackTrace();System.exit(2);}finally{PjeWebGlobal.closeAll();}}
 }
}
