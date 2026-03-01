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

#ifdef __cplusplus
}
#endif

#endif /* scarlet_signing_h */
