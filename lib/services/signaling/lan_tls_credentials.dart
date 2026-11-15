import 'dart:convert';
import 'dart:io';

// Browsers block navigator.mediaDevices on plain http://<lan-ip> because
// window.isSecureContext is false. Serving an optional local HTTPS companion
// endpoint with this self-signed EC P-256 certificate unlocks Secure Context
// on offline RFC1918 LANs while WebRTC media/DataChannel still uses ephemeral
// per-session DTLS-SRTP keys.
SecurityContext buildLanSecurityContext() {
  return SecurityContext()
    ..useCertificateChainBytes(utf8.encode(_lanCertPem))
    ..usePrivateKeyBytes(utf8.encode(_lanKeyPem));
}

const String _lanKeyPem = '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg8HagXv9jfA6wmxxL
/QiqZcRn6PZWcZvj4EKQwisKdQGhRANCAAQtGFTNBKNpDJamnBRGYAaE3h3kqCaj
DOqE4DdLoP4MQZwOXI4AUbvZkqNErOCsP359TSsMLZse7THaI1phyRuR
-----END PRIVATE KEY-----
''';

const String _lanCertPem = '''
-----BEGIN CERTIFICATE-----
MIIB1DCCAXugAwIBAgIUHB65H8l8+rEUxEmBdHYwqSd+LhQwCgYIKoZIzj0EAwIw
MjEZMBcGA1UEAwwQUGhvbmUyU2NyZWVuIExBTjEVMBMGA1UECgwMUGhvbmUyU2Ny
ZWVuMB4XDTI2MTExNTA2NDI1MFoXDTM2MTExMjA2NDI1MFowMjEZMBcGA1UEAwwQ
UGhvbmUyU2NyZWVuIExBTjEVMBMGA1UECgwMUGhvbmUyU2NyZWVuMFkwEwYHKoZI
zj0CAQYIKoZIzj0DAQcDQgAELRhUzQSjaQyWppwURmAGhN4d5KgmowzqhOA3S6D+
DEGcDlyOAFG72ZKjRKzgrD9+fU0rDC2bHu0x2iNaYckbkaNvMG0wHQYDVR0OBBYE
FLI5SZpIUHqEIxNJxbkopsqXXxRgMB8GA1UdIwQYMBaAFLI5SZpIUHqEIxNJxbko
psqXXxRgMAkGA1UdEwQCMAAwCwYDVR0PBAQDAgeAMBMGA1UdJQQMMAoGCCsGAQUF
BwMBMAoGCCqGSM49BAMCA0cAMEQCIA1m5weZCHeRfmjRNYqj1ncvh3fh+3tJaVlh
cOwF1CBeAiAIqhm24KWcM1uztn8kHPsUHP0UOZhFfgdSubVc/yaGJg==
-----END CERTIFICATE-----
''';
