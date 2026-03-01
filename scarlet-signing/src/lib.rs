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
