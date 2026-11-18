// SPDX-License-Identifier: GPL-3.0-or-later
import javax.net.ssl.TrustManager;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;
import java.security.KeyStore;
import java.security.cert.X509Certificate;

/** Lists public ICP-Brasil issuers exposed by this JVM's default TLS trust manager. */
public class TrustProbe {
    public static void main(String[] args) throws Exception {
        TrustManagerFactory factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        factory.init((KeyStore) null);
        int count = 0;
        for (TrustManager manager : factory.getTrustManagers()) {
            if (!(manager instanceof X509TrustManager)) continue;
            for (X509Certificate certificate : ((X509TrustManager) manager).getAcceptedIssuers()) {
                String name = certificate.getSubjectX500Principal().getName();
                if (name.contains("ICP-Brasil")) { System.out.println(name); count++; }
            }
        }
        System.out.println("ICP-Brasil accepted TLS issuers=" + count);
    }
}
