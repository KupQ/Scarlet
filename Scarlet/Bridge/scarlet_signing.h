//
//  scarlet_signing.h
//  Scarlet
//
//  C declarations for zsign-ios, IPA utilities, and PNG normalizer.
//

#ifndef scarlet_signing_h
#define scarlet_signing_h

#ifdef __cplusplus
extern "C" {
#endif

/// Sign an extracted .app folder in place using zsign.
int zsign(const char *path, const char *certFile, const char *pKeyFile,
          const char *provFile, const char *password, const char *bundleId,
          const char *displayName);

/// Extract an IPA (zip) file to a destination directory.
int ipa_extract(const char *ipaPath, const char *destPath);

/// Create an IPA (zip) from a directory containing Payload/.
/// compressionLevel: 0 = store (fastest), 1-9 = deflate (9 = smallest)
int ipa_archive(const char *sourceDir, const char *outputPath,
                int compressionLevel);

/// Check if PNG data uses Apple's CgBI format.
int png_is_cgbi(const unsigned char *data, unsigned long dataLen);

/// Normalize a CgBI PNG to standard PNG.
int png_normalize_cgbi(const unsigned char *inData, unsigned long inLen,
                       unsigned char **outData, unsigned long *outLen);

// ─── Scarlet Signing (Rust FFI) ───

/// Sign an IPA with a P12 certificate.
int scarlet_sign_ipa(const char *ipa_path, const char *cert_path,
                     const char *cert_password, const char *profile_path,
                     const char *output_path);

/// Sign an IPA with PEM cert + key.
int scarlet_sign_ipa_pem(const char *ipa_path, const char *cert_pem,
                         const char *key_pem, const char *profile_path,
                         const char *output_path);

/// Get the last error message from Rust.
char *scarlet_get_last_error(void);

/// Free a string allocated by Rust.
void scarlet_free_string(char *ptr);

// ─── OCSP Certificate Checking (Rust FFI) ───

/// Extract cert info from P12. Returns JSON string (caller frees with
/// scarlet_free_string).
char *scarlet_cert_info_from_p12(const unsigned char *p12_data,
                                 unsigned long p12_len, const char *password);

/// Build an OCSP request DER from P12 + issuer cert.
/// Returns 0 on success, negative on error.
int scarlet_build_ocsp_request(const unsigned char *p12_data,
                               unsigned long p12_len, const char *password,
                               const unsigned char *issuer_der,
                               unsigned long issuer_len,
                               unsigned char **out_data,
                               unsigned long *out_len);

/// Parse OCSP response. Returns status string: "Valid", "Revoked", "Unknown",
/// or "Error". Caller frees with scarlet_free_string.
char *scarlet_parse_ocsp_response(const unsigned char *p12_data,
                                  unsigned long p12_len, const char *password,
                                  const unsigned char *issuer_der,
                                  unsigned long issuer_len,
                                  const unsigned char *response_der,
                                  unsigned long response_len);

/// Free data allocated by Rust OCSP functions.
void scarlet_free_data(unsigned char *ptr);

#ifdef __cplusplus
}
#endif

#endif /* scarlet_signing_h */
