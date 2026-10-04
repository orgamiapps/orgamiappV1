"use strict";

const crypto = require("node:crypto");
const asn1 = require("asn1js");
const pki = require("pkijs");

function certificate(pem) {
  const match = /-----BEGIN CERTIFICATE-----([\s\S]+?)-----END CERTIFICATE-----/.exec(pem);
  if (!match) throw new Error("A PEM signing certificate is required.");
  return pki.Certificate.fromBER(Buffer.from(match[1].replace(/\s/g, ""), "base64"));
}

async function signDetached(content, signing) {
  const leaf = certificate(signing.certificate);
  const chain = certificate(signing.wwdrCertificate);
  const key = crypto.createPrivateKey(signing.privateKey);
  if (key.asymmetricKeyType !== "rsa" ||
      !new crypto.X509Certificate(signing.certificate).checkPrivateKey(key)) {
    throw new Error("The RSA signing key must match the pass certificate.");
  }
  const privateKey = await crypto.webcrypto.subtle.importKey("pkcs8",
      key.export({format: "der", type: "pkcs8"}),
      {name: "RSASSA-PKCS1-v1_5", hash: "SHA-256"}, false, ["sign"]);
  const dataType = "1.2.840.113549.1.7.1";
  const signed = new pki.SignedData({version: 1,
    encapContentInfo: new pki.EncapsulatedContentInfo({eContentType: dataType}),
    certificates: [leaf, chain],
    signerInfos: [new pki.SignerInfo({version: 1,
      sid: new pki.IssuerAndSerialNumber({issuer: leaf.issuer, serialNumber: leaf.serialNumber}),
      signedAttrs: new pki.SignedAndUnsignedAttributes({type: 0, attributes: [
        new pki.Attribute({type: "1.2.840.113549.1.9.3", values: [new asn1.ObjectIdentifier({value: dataType})]}),
        new pki.Attribute({type: "1.2.840.113549.1.9.5", values: [new asn1.UTCTime({valueDate: new Date()})]}),
        new pki.Attribute({type: "1.2.840.113549.1.9.4", values: [new asn1.OctetString({
          valueHex: crypto.createHash("sha256").update(content).digest(),
        })]}),
      ]}),
    })],
  });
  const engine = new pki.CryptoEngine({name: "node-webcrypto", crypto: crypto.webcrypto});
  await signed.sign(privateKey, 0, "SHA-256", content, engine);
  return Buffer.from(new pki.ContentInfo({contentType: "1.2.840.113549.1.7.2",
    content: signed.toSchema(true)}).toSchema().toBER(false));
}

module.exports = {signDetached};
