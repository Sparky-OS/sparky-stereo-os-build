// SPDX-License-Identifier: GPL-3.0-or-later
import java.io.FileInputStream;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.Provider;
import java.security.Signature;
import java.security.cert.Certificate;
import java.util.Arrays;
import java.util.Enumeration;

/** Probe upstream provider construction and a synthetic challenge, not a court login. */
public class ProviderProbe {
    public static void main(String[] args) throws Exception {
        char[] pin = new String(Files.readAllBytes(Paths.get(args[1])), StandardCharsets.UTF_8).trim().toCharArray();
        try {
            KeyStore store;
            Provider provider = null;
            if (args[0].equals("file")) {
                store = KeyStore.getInstance("PKCS12");
                try (FileInputStream input = new FileInputStream(args[2])) { store.load(input, pin); }
            } else {
                Class<?> type = Class.forName("com.github.signer4j.provider.SunPKCS11Creator");
                Method create = type.getDeclaredMethod("create", String.class);
                create.setAccessible(true);
                provider = (Provider) create.invoke(null, "name=TESTONLY\nlibrary=" + args[2] + "\nslotListIndex=0\n");
                store = KeyStore.getInstance("PKCS11", provider);
                store.load(null, pin);
            }
            Enumeration<String> aliases = store.aliases();
            boolean verified = false;
            while (aliases.hasMoreElements()) {
                String alias = aliases.nextElement();
                if (!store.isKeyEntry(alias)) continue;
                Certificate certificate = store.getCertificate(alias);
                PrivateKey key = (PrivateKey) store.getKey(alias, pin);
                byte[] challenge = "SYNTHETIC TEST CHALLENGE".getBytes(StandardCharsets.UTF_8);
                Signature signer = provider == null ? Signature.getInstance("SHA256withRSA") : Signature.getInstance("SHA256withRSA", provider);
                signer.initSign(key); signer.update(challenge);
                byte[] bytes = signer.sign();
                Signature verifier = Signature.getInstance("SHA256withRSA");
                verifier.initVerify(certificate); verifier.update(challenge);
                verified = verifier.verify(bytes);
                System.out.println("synthetic challenge verified=" + verified + " provider=" + signer.getProvider().getName());
                if (!verified) throw new Exception("Signature verification failed");
            }
            if (!verified) throw new Exception("No signing identity found");
        } finally { Arrays.fill(pin, '\0'); }
    }
}
