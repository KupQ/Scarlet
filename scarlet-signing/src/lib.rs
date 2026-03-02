//! C FFI wrapper around zsign-rs for iOS integration.
//!
//! Provides extern "C" functions callable from Swift via a bridging header.
//! Uses OpenSSL (vendored) for robust P12 parsing that handles all formats.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::Mutex;

use zsign_rs::{SigningCredentials, ZSign};

/// Thread-local storage for the last error message.
static LAST_ERROR: Mutex<Option<String>> = Mutex::new(None);

/// Store an error message for later retrieval.
fn set_last_error(msg: String) {
    if let Ok(mut err) = LAST_ERROR.lock() {
        *err = Some(msg);
    }
}

/// Sign an IPA file with a PKCS#12 certificate.
///
/// Uses OpenSSL to parse the P12, extracts cert+key as PEM,
/// then passes to zsign-rs via from_pem().
///
/// # Returns
/// - `0` on success
/// - `-1` on invalid arguments
/// - `-2` on credential loading failure
/// - `-3` on signing failure
#[no_mangle]
pub extern "C" fn scarlet_sign_ipa(
    ipa_path: *const c_char,
    cert_path: *const c_char,
    cert_password: *const c_char,
    profile_path: *const c_char,
    output_path: *const c_char,
) -> i32 {
    let ipa = match unsafe_cstr_to_str(ipa_path, "ipa_path") {
        Ok(s) => s,
        Err(code) => return code,
    };
    let cert = match unsafe_cstr_to_str(cert_path, "cert_path") {
        Ok(s) => s,
        Err(code) => return code,
    };
    let password = match unsafe_cstr_to_str(cert_password, "cert_password") {
        Ok(s) => s,
        Err(code) => return code,
    };
    let output = match unsafe_cstr_to_str(output_path, "output_path") {
        Ok(s) => s,
        Err(code) => return code,
    };

    // Read the P12 file
    let p12_data = match std::fs::read(&cert) {
        Ok(data) => data,
        Err(e) => {
            set_last_error(format!("Failed to read certificate file: {}", e));
            return -2;
        }
    };

    // Try OpenSSL-based P12 parsing first (handles all formats)
    let credentials = match parse_p12_with_openssl(&p12_data, &password) {
        Ok(creds) => creds,
        Err(e) => {
            // Fallback to zsign-rs native P12 parser
            match SigningCredentials::from_p12(&p12_data, &password) {
                Ok(creds) => creds,
                Err(e2) => {
                    set_last_error(format!(
                        "Failed to load credentials. OpenSSL: {}. Native: {}",
                        e, e2
                    ));
                    return -2;
                }
            }
        }
    };

    do_sign(credentials, &ipa, profile_path, &output)
}

/// Sign an IPA file using PEM-encoded certificate and private key.
#[no_mangle]
pub extern "C" fn scarlet_sign_ipa_pem(
    ipa_path: *const c_char,
    cert_pem: *const c_char,
    key_pem: *const c_char,
    profile_path: *const c_char,
    output_path: *const c_char,
) -> i32 {
    let ipa = match unsafe_cstr_to_str(ipa_path, "ipa_path") {
        Ok(s) => s,
        Err(code) => return code,
    };
    let cert_pem_str = match unsafe_cstr_to_str(cert_pem, "cert_pem") {
        Ok(s) => s,
        Err(code) => return code,
    };
    let key_pem_str = match unsafe_cstr_to_str(key_pem, "key_pem") {
        Ok(s) => s,
        Err(code) => return code,
    };
    let output = match unsafe_cstr_to_str(output_path, "output_path") {
        Ok(s) => s,
        Err(code) => return code,
    };

    let credentials = match SigningCredentials::from_pem(
        cert_pem_str.as_bytes(),
        key_pem_str.as_bytes(),
        None,
    ) {
        Ok(creds) => creds,
        Err(e) => {
            set_last_error(format!("Failed to load PEM credentials: {}", e));
            return -2;
        }
    };

    do_sign(credentials, &ipa, profile_path, &output)
}

/// Parse a P12 file using OpenSSL and convert to zsign-rs credentials via PEM.
fn parse_p12_with_openssl(
    p12_data: &[u8],
    password: &str,
) -> Result<SigningCredentials, String> {
    use openssl::pkcs12::Pkcs12;

    // Parse the PKCS#12 with OpenSSL
    let pkcs12 = Pkcs12::from_der(p12_data)
        .map_err(|e| format!("OpenSSL P12 parse error: {}", e))?;

    let parsed = pkcs12
        .parse2(password)
        .map_err(|e| format!("OpenSSL P12 decrypt error: {}", e))?;

    // Extract certificate PEM
    let cert = parsed
        .cert
        .ok_or_else(|| "No certificate in P12".to_string())?;
    let cert_pem = cert
        .to_pem()
        .map_err(|e| format!("Failed to convert cert to PEM: {}", e))?;

    // Extract private key PEM
    let key = parsed
        .pkey
        .ok_or_else(|| "No private key in P12".to_string())?;
    let key_pem = key
        .private_key_to_pem_pkcs8()
        .map_err(|e| format!("Failed to convert key to PEM: {}", e))?;

    // Load into zsign-rs using from_pem
    SigningCredentials::from_pem(&cert_pem, &key_pem, None)
        .map_err(|e| format!("zsign-rs PEM load error: {}", e))
}

/// Common signing logic.
fn do_sign(
    credentials: SigningCredentials,
    ipa: &str,
    profile_path: *const c_char,
    output: &str,
) -> i32 {
    let mut signer = ZSign::new().credentials(credentials);

    if !profile_path.is_null() {
        if let Ok(profile) = unsafe_cstr_to_str(profile_path, "profile_path") {
            signer = signer.provisioning_profile(profile);
        }
    }

    match signer.sign_ipa(ipa, output) {
        Ok(()) => 0,
        Err(e) => {
            set_last_error(format!("Signing failed: {}", e));
            -3
        }
    }
}

/// Retrieve the last error message.
#[no_mangle]
pub extern "C" fn scarlet_get_last_error() -> *mut c_char {
    let msg = LAST_ERROR
        .lock()
        .ok()
        .and_then(|mut err| err.take());

    match msg {
        Some(s) => CString::new(s).unwrap_or_default().into_raw(),
        None => std::ptr::null_mut(),
    }
}

/// Free a string allocated by the Rust side.
#[no_mangle]
pub extern "C" fn scarlet_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// Safely convert a C string pointer to a Rust `String`.
fn unsafe_cstr_to_str(ptr: *const c_char, name: &str) -> Result<String, i32> {
    if ptr.is_null() {
        set_last_error(format!("Null pointer for parameter: {}", name));
        return Err(-1);
    }
    unsafe {
        CStr::from_ptr(ptr)
            .to_str()
            .map(|s| s.to_owned())
            .map_err(|e| {
                set_last_error(format!("Invalid UTF-8 in {}: {}", name, e));
                -1
            })
    }
}

// ─────────────────────────────────────────────────────────────
// OCSP Certificate Checking (using OpenSSL)
// ─────────────────────────────────────────────────────────────

use openssl::{hash::MessageDigest, ocsp::*, pkcs12::Pkcs12, x509::X509};

/// Extract certificate info from a P12 file.
/// Returns a JSON string: {"name":"…","expires":"…","serial":"…"}
/// Caller must free the returned string with scarlet_free_string.
#[no_mangle]
pub extern "C" fn scarlet_cert_info_from_p12(
    p12_data: *const u8,
    p12_len: usize,
    password: *const c_char,
) -> *mut c_char {
    let data = unsafe { std::slice::from_raw_parts(p12_data, p12_len) };
    let pwd = match unsafe_cstr_to_str(password, "password") {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    match do_cert_info(data, &pwd) {
        Ok(json) => CString::new(json).unwrap_or_default().into_raw(),
        Err(e) => {
            set_last_error(e);
            std::ptr::null_mut()
        }
    }
}

fn cert_cn(cert: &X509) -> String {
    let name = cert.subject_name().entries()
        .find(|e| e.object().nid().short_name().unwrap_or("") == "CN")
        .and_then(|e| e.data().as_utf8().ok())
        .map(|s| s.to_string())
        .unwrap_or_default();

    let stripped = name.strip_prefix("iPhone Distribution: ")
        .or(name.strip_prefix("Apple Distribution: "))
        .or(name.strip_prefix("iPhone Developer: "))
        .or(name.strip_prefix("Apple Developer: "))
        .unwrap_or(&name);

    stripped.split(" (").next().unwrap_or(stripped).to_string()
}

fn do_cert_info(data: &[u8], password: &str) -> Result<String, String> {
    let parsed = Pkcs12::from_der(data).map_err(|e| format!("Bad P12: {e}"))?
        .parse2(password).map_err(|e| format!("Wrong password: {e}"))?;

    let cert = parsed.cert.ok_or("No cert in P12")?;
    let cn = cert_cn(&cert);

    let not_before = cert.not_before().to_string();
    let not_after = cert.not_after().to_string();

    let serial = cert.serial_number().to_bn()
        .map(|bn| bn.to_hex_str().map(|s| s.to_string()).unwrap_or_default())
        .unwrap_or_default();

    Ok(format!(
        "{{\"name\":\"{}\",\"not_before\":\"{}\",\"not_after\":\"{}\",\"serial\":\"{}\"}}",
        cn.replace('\"', "\\\""),
        not_before,
        not_after,
        serial
    ))
}

/// Build an OCSP request for a P12 certificate.
/// `issuer_der` is the DER-encoded Apple WWDR issuer certificate.
/// Returns the DER-encoded OCSP request. Caller must free with scarlet_free_data.
#[no_mangle]
pub extern "C" fn scarlet_build_ocsp_request(
    p12_data: *const u8,
    p12_len: usize,
    password: *const c_char,
    issuer_der: *const u8,
    issuer_len: usize,
    out_data: *mut *mut u8,
    out_len: *mut usize,
) -> i32 {
    let data = unsafe { std::slice::from_raw_parts(p12_data, p12_len) };
    let issuer_bytes = unsafe { std::slice::from_raw_parts(issuer_der, issuer_len) };
    let pwd = match unsafe_cstr_to_str(password, "password") {
        Ok(s) => s,
        Err(code) => return code,
    };

    match do_build_ocsp(data, &pwd, issuer_bytes) {
        Ok(ocsp_der) => {
            let len = ocsp_der.len();
            let ptr = ocsp_der.as_ptr();
            unsafe {
                *out_data = libc_malloc(len) as *mut u8;
                if (*out_data).is_null() {
                    set_last_error("malloc failed".to_string());
                    return -4;
                }
                std::ptr::copy_nonoverlapping(ptr, *out_data, len);
                *out_len = len;
            }
            0
        }
        Err(e) => {
            set_last_error(e);
            -5
        }
    }
}

extern "C" {
    #[link_name = "malloc"]
    fn libc_malloc(size: usize) -> *mut std::ffi::c_void;
}

fn do_build_ocsp(p12_data: &[u8], password: &str, issuer_der: &[u8]) -> Result<Vec<u8>, String> {
    let parsed = Pkcs12::from_der(p12_data).map_err(|e| format!("Bad P12: {e}"))?
        .parse2(password).map_err(|e| format!("Wrong password: {e}"))?;

    let cert = parsed.cert.ok_or("No cert in P12")?;
    let issuer = X509::from_der(issuer_der).map_err(|e| format!("Bad issuer cert: {e}"))?;

    let cert_id = OcspCertId::from_cert(MessageDigest::sha1(), &cert, &issuer)
        .map_err(|e| format!("CertId: {e}"))?;

    let mut request = OcspRequest::new().map_err(|e| format!("OcspReq: {e}"))?;
    request.add_id(cert_id).map_err(|e| format!("add_id: {e}"))?;

    let der = request.to_der().map_err(|e| format!("to_der: {e}"))?;
    Ok(der)
}

/// Parse an OCSP response and return the certificate status.
/// Returns a string: "Valid", "Revoked", or "Unknown".
/// Caller must free with scarlet_free_string.
#[no_mangle]
pub extern "C" fn scarlet_parse_ocsp_response(
    p12_data: *const u8,
    p12_len: usize,
    password: *const c_char,
    issuer_der: *const u8,
    issuer_len: usize,
    response_der: *const u8,
    response_len: usize,
) -> *mut c_char {
    let data = unsafe { std::slice::from_raw_parts(p12_data, p12_len) };
    let issuer_bytes = unsafe { std::slice::from_raw_parts(issuer_der, issuer_len) };
    let resp_bytes = unsafe { std::slice::from_raw_parts(response_der, response_len) };
    let pwd = match unsafe_cstr_to_str(password, "password") {
        Ok(s) => s,
        Err(_) => return CString::new("Error").unwrap_or_default().into_raw(),
    };

    let result = match do_parse_ocsp(data, &pwd, issuer_bytes, resp_bytes) {
        Ok(status) => status,
        Err(e) => {
            set_last_error(e);
            "Error".to_string()
        }
    };

    CString::new(result).unwrap_or_default().into_raw()
}

fn do_parse_ocsp(p12_data: &[u8], password: &str, issuer_der: &[u8], resp_der: &[u8]) -> Result<String, String> {
    let parsed = Pkcs12::from_der(p12_data).map_err(|e| format!("Bad P12: {e}"))?
        .parse2(password).map_err(|e| format!("Wrong password: {e}"))?;

    let cert = parsed.cert.ok_or("No cert in P12")?;
    let issuer = X509::from_der(issuer_der).map_err(|e| format!("Bad issuer cert: {e}"))?;

    let resp = OcspResponse::from_der(resp_der).map_err(|e| format!("Bad OCSP resp: {e}"))?;

    if resp.status() != OcspResponseStatus::SUCCESSFUL {
        return Err(format!("OCSP not successful: {:?}", resp.status()));
    }

    let cert_id = OcspCertId::from_cert(MessageDigest::sha1(), &cert, &issuer)
        .map_err(|e| format!("CertId: {e}"))?;

    let basic = resp.basic().map_err(|e| format!("basic: {e}"))?;

    match basic.find_status(&cert_id) {
        Some(s) if s.revocation_time.is_some() => Ok("Revoked".to_string()),
        Some(_) => Ok("Valid".to_string()),
        None => Ok("Unknown".to_string()),
    }
}

/// Free data allocated by Rust (for OCSP request bytes).
#[no_mangle]
pub extern "C" fn scarlet_free_data(ptr: *mut u8) {
    if !ptr.is_null() {
        unsafe {
            // This was allocated with libc malloc, so free with libc free
            libc_free(ptr as *mut std::ffi::c_void);
        }
    }
}

extern "C" {
    #[link_name = "free"]
    fn libc_free(ptr: *mut std::ffi::c_void);
}

