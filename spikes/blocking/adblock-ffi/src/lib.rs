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

/// Escapes `text` as a JavaScript string literal (double quoted).
fn js_string(text: &str) -> String {
    let mut out = String::with_capacity(text.len() + 2);
    out.push('"');
    for c in text.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '<' => out.push_str("\\u003c"),
            '\u{2028}' => out.push_str("\\u2028"),
            '\u{2029}' => out.push_str("\\u2029"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

/// JavaScript adding one stylesheet that hides every selector (a selector the browser rejects only
/// drops its own rule). Empty for no selectors.
fn style_script(selectors: &[String]) -> String {
    if selectors.is_empty() {
        return String::new();
    }
    let css: String = selectors
        .iter()
        .map(|selector| format!("{selector}{{display:none!important}}\n"))
        .collect();
    format!(
        "(function(){{var css={};try{{var sheet=new CSSStyleSheet();sheet.replaceSync(css);\
         document.adoptedStyleSheets=[].concat(Array.from(document.adoptedStyleSheets),[sheet]);}}\
         catch(e){{var add=function(){{var s=document.createElement('style');s.textContent=css;\
         (document.head||document.documentElement).appendChild(s);}};\
         if(document.documentElement){{add();}}else{{document.addEventListener('DOMContentLoaded',add);}}}}}})();",
        js_string(&css)
    )
}

/// Reports class and id names of the top-level document, new ones only, to the browser process, which
/// answers with the generic rules those names trigger. Two channels carry the same report: a request to a
/// reserved host that the browser cancels (unaffected by page console use) and a console line (unaffected
/// by a page's Content-Security-Policy). The browser ignores a repeat of a report it already handled.
const HARVESTER: &str = "(function(){if(window!==window.top)return;var c=new Set(),i=new Set(),t=0;\
function send(o){var q='c='+o.c.map(encodeURIComponent).join(',')+'&i='+o.i.map(encodeURIComponent).join(',');\
try{fetch('https://bato.invalid/__cosmetic?'+q,{mode:'no-cors',cache:'no-store'}).catch(function(){});}catch(e){}\
console.info('bato-cosmetic:'+JSON.stringify(o));}\
function scan(){t=0;var nc=[],ni=[];document.querySelectorAll('[class],[id]').forEach(function(e){\
if(e.id&&!i.has(e.id)){i.add(e.id);ni.push(e.id);}\
if(e.classList)e.classList.forEach(function(k){if(!c.has(k)){c.add(k);nc.push(k);}});});\
if(nc.length||ni.length)send({c:nc.slice(0,1500),i:ni.slice(0,1500)});}\
function later(){if(!t)t=setTimeout(scan,400);}\
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',scan);else scan();\
new MutationObserver(later).observe(document,{childList:true,subtree:true,attributes:true,attributeFilter:['class','id']});})();";

/// JavaScript for the cosmetic rules that apply to `url`: a stylesheet hiding the page-specific
/// selectors, the class/id harvester unless the lists forbid generic hiding, then any scriptlets the
/// lists inject. Empty when nothing applies. Procedural filters are not supported. Scriptlets need
/// resources, which are not loaded, so none is ever emitted.
pub fn cosmetic_script(engine: &BatoAdblock, url: &str) -> String {
    let resources = engine.0.url_cosmetic_resources(url);
    let mut selectors: Vec<String> = resources.hide_selectors.iter().cloned().collect();
    selectors.sort();
    let mut script = style_script(&selectors);
    if !resources.generichide {
        script.push_str(HARVESTER);
    }
    script.push_str(&resources.injected_script);
    script
}

/// The generic class/id rules triggered by `classes` and `ids` on a page at `url`, as a stylesheet script.
pub fn generic_script(engine: &BatoAdblock, url: &str, classes: &[&str], ids: &[&str]) -> String {
    let resources = engine.0.url_cosmetic_resources(url);
    if resources.generichide {
        return String::new();
    }
    let mut selectors = engine.0.hidden_class_id_selectors(classes, ids, &resources.exceptions);
    selectors.sort();
    style_script(&selectors)
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

/// The cosmetic script for `url` as a newly allocated C string (free with `bato_adblock_string_free`),
/// or null when nothing applies or an argument is invalid.
#[no_mangle]
pub unsafe extern "C" fn bato_adblock_cosmetic_script(
    engine: *const BatoAdblock,
    url: *const c_char,
) -> *mut c_char {
    let (Some(engine), Some(url)) = (engine.as_ref(), text(url)) else {
        return std::ptr::null_mut();
    };
    let script = cosmetic_script(engine, url);
    if script.is_empty() {
        return std::ptr::null_mut();
    }
    std::ffi::CString::new(script).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

/// Generic rules for the names in `names`, one per line, `c:<class>` or `i:<id>`. Same ownership as
/// `bato_adblock_cosmetic_script`.
#[no_mangle]
pub unsafe extern "C" fn bato_adblock_cosmetic_generic(
    engine: *const BatoAdblock,
    url: *const c_char,
    names: *const c_char,
) -> *mut c_char {
    let (Some(engine), Some(url), Some(names)) = (engine.as_ref(), text(url), text(names)) else {
        return std::ptr::null_mut();
    };
    let classes: Vec<&str> = names.lines().filter_map(|l| l.strip_prefix("c:")).collect();
    let ids: Vec<&str> = names.lines().filter_map(|l| l.strip_prefix("i:")).collect();
    let script = generic_script(engine, url, &classes, &ids);
    if script.is_empty() {
        return std::ptr::null_mut();
    }
    std::ffi::CString::new(script).map(|c| c.into_raw()).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn bato_adblock_string_free(string: *mut c_char) {
    if !string.is_null() {
        drop(std::ffi::CString::from_raw(string));
    }
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
    fn cosmetic_script_hides_page_selectors_and_escapes_them() {
        let engine = from_list("127.0.0.1##div[data-x=\"a\"]\nother.example##.only-other\n");
        let script = cosmetic_script(&engine, PAGE);
        assert!(script.contains("div[data-x=\\\"a\\\"]{display:none!important}"));
        assert!(!script.contains(".only-other"));
        assert!(script.contains("bato-cosmetic:"));
    }

    #[test]
    fn generic_class_and_id_rules_follow_the_names_on_the_page() {
        let engine = from_list("##.bato-fixture-ad\n###bato-banner\n");
        let script = generic_script(&engine, PAGE, &["bato-fixture-ad", "other"], &["bato-banner"]);
        assert!(script.contains(".bato-fixture-ad{display:none!important}"));
        assert!(script.contains("#bato-banner{display:none!important}"));
        assert!(generic_script(&engine, PAGE, &["other"], &[]).is_empty());
    }

    #[test]
    fn generichide_exception_turns_generic_rules_off() {
        let engine = from_list("##.bato-fixture-ad\n@@||127.0.0.1^$generichide\n");
        assert!(generic_script(&engine, PAGE, &["bato-fixture-ad"], &[]).is_empty());
        assert!(!cosmetic_script(&engine, PAGE).contains("bato-cosmetic:"));
    }

    #[test]
    fn nothing_applies_to_a_list_without_cosmetic_rules() {
        let script = cosmetic_script(&from_list("||ads.example^\n"), PAGE);
        assert!(!script.contains("adoptedStyleSheets"));
    }

    #[test]
    fn invalid_url_is_an_error_not_a_block() {
        assert_eq!(verdict("not a url", "script"), BATO_ADBLOCK_ERROR);
    }
}
