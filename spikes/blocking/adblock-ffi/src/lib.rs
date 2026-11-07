//! Minimal C ABI over Brave's adblock-rust for the Bato blocking spike.
//!
//! The engine is immutable after creation and `Send + Sync` (adblock's
//! `single-thread` feature is disabled), so concurrent `bato_adblock_check`
//! calls need no locking. Swapping a list means creating a new engine and
//! freeing the old one only after in-flight checks have finished.

use adblock::request::Request;
use adblock::Engine;
use std::ffi::CStr;
use std::os::raw::c_char;

pub const BATO_ADBLOCK_ALLOW: i32 = 0;
pub const BATO_ADBLOCK_BLOCK: i32 = 1;
/// Blocked, and the engine holds a redirect resource body for the request.
pub const BATO_ADBLOCK_REDIRECT: i32 = 2;
pub const BATO_ADBLOCK_ERROR: i32 = -1;

pub struct BatoAdblock(Engine);

/// Evaluates one request. `request_type` uses adblock names (`script`, `image`,
/// `xmlhttprequest`, `subdocument`, `stylesheet`, `websocket`, `other`, ...).
pub fn check(engine: &BatoAdblock, url: &str, source_url: &str, request_type: &str) -> i32 {
    let Ok(request) = Request::new(url, source_url, request_type, "GET") else {
        return BATO_ADBLOCK_ERROR;
    };
    let result = engine.0.check_network_request(&request);
    match (result.should_block(), result.redirect.is_some()) {
        (true, true) => BATO_ADBLOCK_REDIRECT,
        (true, false) => BATO_ADBLOCK_BLOCK,
        _ => BATO_ADBLOCK_ALLOW,
    }
}

pub fn from_list(list_text: &str) -> BatoAdblock {
    BatoAdblock(Engine::new_with_list_text(list_text))
}

unsafe fn text<'a>(pointer: *const c_char) -> Option<&'a str> {
    if pointer.is_null() {
        return None;
    }
    CStr::from_ptr(pointer).to_str().ok()
}

/// Returns null when `list_text` is null or not UTF-8. Free with `bato_adblock_free`.
#[no_mangle]
pub unsafe extern "C" fn bato_adblock_create(list_text: *const c_char) -> *mut BatoAdblock {
    match text(list_text) {
        Some(list) => Box::into_raw(Box::new(from_list(list))),
        None => std::ptr::null_mut(),
    }
}

/// Returns a `BATO_ADBLOCK_*` value; any null/invalid argument yields `BATO_ADBLOCK_ERROR`.
#[no_mangle]
pub unsafe extern "C" fn bato_adblock_check(
    engine: *const BatoAdblock,
    url: *const c_char,
    source_url: *const c_char,
    request_type: *const c_char,
) -> i32 {
    let (Some(engine), Some(url), Some(source), Some(kind)) =
        (engine.as_ref(), text(url), text(source_url), text(request_type))
    else {
        return BATO_ADBLOCK_ERROR;
    };
    check(engine, url, source, kind)
}

#[no_mangle]
pub unsafe extern "C" fn bato_adblock_free(engine: *mut BatoAdblock) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    const LIST: &str = include_str!("../../../fixtures/blocking/bato-fixture-list.txt");
    const PAGE: &str = "http://127.0.0.1:18765/blocking-network.html";

    fn verdict(url: &str, kind: &str) -> i32 {
        check(&from_list(LIST), url, PAGE, kind)
    }

    #[test]
    fn blocks_third_party_by_type() {
        for (path, kind) in [
            ("tracker.js", "script"),
            ("pixel.png", "image"),
            ("beacon.json", "xmlhttprequest"),
            ("frame.html", "subdocument"),
            ("style.css", "stylesheet"),
        ] {
            let url = format!("http://localhost:18766/ads/{path}");
            assert_eq!(verdict(&url, kind), BATO_ADBLOCK_BLOCK, "{url}");
        }
    }

    #[test]
    fn allows_same_origin_and_controls() {
        assert_eq!(verdict("http://127.0.0.1:18765/ads/tracker.js", "script"), BATO_ADBLOCK_ALLOW);
        assert_eq!(verdict("http://localhost:18766/control/ok.js", "script"), BATO_ADBLOCK_ALLOW);
    }

    #[test]
    fn exception_and_important_rules() {
        assert_eq!(verdict("http://localhost:18766/ads/allowed-tracker.js", "script"), BATO_ADBLOCK_ALLOW);
        assert_eq!(verdict("http://localhost:18766/ads/important-allowed-tracker.js", "script"), BATO_ADBLOCK_BLOCK);
    }

    #[test]
    fn same_origin_rule_blocks_worker_script_requests() {
        assert_eq!(verdict("http://127.0.0.1:18765/ads/worker-blocked.js", "script"), BATO_ADBLOCK_BLOCK);
    }

    #[test]
    fn domain_option_limits_rule_to_listed_page() {
        let url = "http://localhost:18766/ads/domain-only.js";
        assert_eq!(check(&from_list(LIST), url, PAGE, "script"), BATO_ADBLOCK_BLOCK);
        assert_eq!(check(&from_list(LIST), url, "http://localhost:18766/other.html", "script"), BATO_ADBLOCK_ALLOW);
    }

    #[test]
    fn c_abi_round_trip_and_null_safety() {
        let list = CString::new(LIST).unwrap();
        let url = CString::new("http://localhost:18766/ads/tracker.js").unwrap();
        let page = CString::new(PAGE).unwrap();
        let kind = CString::new("script").unwrap();
        unsafe {
            let engine = bato_adblock_create(list.as_ptr());
            assert!(!engine.is_null());
            assert_eq!(bato_adblock_check(engine, url.as_ptr(), page.as_ptr(), kind.as_ptr()), BATO_ADBLOCK_BLOCK);
            assert_eq!(bato_adblock_check(engine, std::ptr::null(), page.as_ptr(), kind.as_ptr()), BATO_ADBLOCK_ERROR);
            bato_adblock_free(engine);
            bato_adblock_free(std::ptr::null_mut());
            assert!(bato_adblock_create(std::ptr::null()).is_null());
        }
    }

    #[test]
    fn invalid_url_is_an_error_not_a_block() {
        assert_eq!(verdict("not a url", "script"), BATO_ADBLOCK_ERROR);
    }
}
