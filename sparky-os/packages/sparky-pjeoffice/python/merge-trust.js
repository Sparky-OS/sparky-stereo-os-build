// SPDX-FileCopyrightText: 2026 Daniel Ramos (Capitain Jack)
// SPDX-License-Identifier: GPL-3.0-or-later
// Run by sparky-pjeoffice with the program's own bundled Java: jjs merge-trust.js -- TYPE ORIGINAL BUNDLE OUTPUT PASSWORD
// Reads the certificate list inside PJeOffice Pro's jar (a PKCS12 or JKS store of trusted certificates), adds every certificate of the
// system's PEM bundle that the list does not hold, writes the result in the same type, reads it back and checks that every
// original certificate is still there, byte for byte (its DER encoding). Prints one JSON line; a failure is a nonzero exit.
var KeyStore = Java.type('java.security.KeyStore');
var CertificateFactory = Java.type('java.security.cert.CertificateFactory');
var FileInputStream = Java.type('java.io.FileInputStream');
var FileOutputStream = Java.type('java.io.FileOutputStream');
var ByteArrayInputStream = Java.type('java.io.ByteArrayInputStream');
var MessageDigest = Java.type('java.security.MessageDigest');
var Files = Java.type('java.nio.file.Files');
var Paths = Java.type('java.nio.file.Paths');
var JString = Java.type('java.lang.String');
var Integer = Java.type('java.lang.Integer');

var type = arguments[0], original = arguments[1], bundle = arguments[2], out = arguments[3];
var password = new JString(arguments[4]).toCharArray();

function hex(bytes) {
    var digest = MessageDigest.getInstance('SHA-256').digest(bytes);
    var text = '';
    for (var i = 0; i < digest.length; i++) {
        text += ('0' + Integer.toHexString(digest[i] & 0xff)).slice(-2);
    }
    return text;
}

function load(path) {
    var store = KeyStore.getInstance(type);
    var stream = new FileInputStream(path);
    try {
        store.load(stream, password);
    } finally {
        stream.close();
    }
    return store;
}

function encodings(store) {
    var found = {};
    var count = 0;
    var names = store.aliases();
    while (names.hasMoreElements()) {
        var name = names.nextElement();
        if (store.isKeyEntry(name)) {
            throw 'the store holds a private key entry (' + name + '): only trusted certificates are expected';
        }
        found[hex(store.getCertificate(name).getEncoded())] = true;
        count++;
    }
    return {set: found, count: count};
}

var store = load(original);
var before = encodings(store);
var factory = CertificateFactory.getInstance('X.509');
var text = new JString(Files.readAllBytes(Paths.get(bundle)), 'UTF-8');
var pieces = text.split('-----END CERTIFICATE-----');
var add = {};
var skipped = 0;
var read = 0;
for (var i = 0; i < pieces.length; i++) {
    var start = pieces[i].indexOf('-----BEGIN CERTIFICATE-----');
    if (start < 0) {
        continue;
    }
    var block = pieces[i].substring(start) + '-----END CERTIFICATE-----\n';
    try {
        var certificate = factory.generateCertificate(new ByteArrayInputStream(new JString(block).getBytes('UTF-8')));
        read++;
        var key = hex(certificate.getEncoded());
        if (!before.set[key] && !add[key]) {
            add[key] = certificate;
        }
    } catch (error) {
        skipped++;
    }
}
if (read === 0) {
    throw 'the system bundle ' + bundle + ' holds no certificate that Java can read';
}
var keys = Object.keys(add).sort();
for (var j = 0; j < keys.length; j++) {
    store.setCertificateEntry('sparky-system-' + keys[j].substring(0, 16), add[keys[j]]);
}
var sink = new FileOutputStream(out);
try {
    store.store(sink, password);
} finally {
    sink.close();
}
var after = encodings(load(out));
for (var key in before.set) {
    if (!after.set[key]) {
        throw 'an original certificate is missing from the result: ' + key;
    }
}
if (after.count !== before.count + keys.length) {
    throw 'the result holds ' + after.count + ' certificates, expected ' + (before.count + keys.length);
}
print(JSON.stringify({original: before.count, added: keys.length, skipped: skipped, read: read}));
