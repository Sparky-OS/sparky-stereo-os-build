// SPDX-License-Identifier: GPL-3.0-or-later
import java.io.*;import java.security.cert.*;import java.util.*;
public class SanShape {public static void main(String[] a)throws Exception{
 X509Certificate c=(X509Certificate)CertificateFactory.getInstance("X.509").generateCertificate(new FileInputStream(a[0]));
 for(List<?> e:c.getSubjectAlternativeNames()){System.out.print("size="+e.size());for(Object v:e) System.out.print(" type="+v.getClass().getName()+ (v instanceof Number||v instanceof String?" value="+v:""));System.out.println();}
}}
