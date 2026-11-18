// SPDX-License-Identifier: GPL-3.0-or-later
public class LocalTestMain {
 public static void main(String[] args) throws Exception {
  br.jus.cnj.pje.office.core.imp.sec.PjeSecurity.GRANTOR.setDevMode(true);
  br.jus.cnj.pje.office.imp.PjeOfficePRODev.main(args);
 }
}
