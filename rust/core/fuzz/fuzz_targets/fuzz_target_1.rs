#![no_main]

use libfuzzer_sys::fuzz_target;
use toolshed_core::Primitive;

fuzz_target!(|data: &[u8]| {
    // Basic fuzzing: try to create Primitive values from the input
    if data.is_empty() {
        return;
    }
    
    // Try to decode data as UTF-8 string
    if let Ok(s) = std::str::from_utf8(data) {
        let p_string = Primitive::String(s.to_string());
        
        // Exercise the primitive by cloning, comparing, and formatting
        let _ = p_string.clone();
        let _ = p_string == p_string.clone();
        let _ = format!("{:?}", p_string);
        
        // Try to parse as various numeric types and exercise them
        if let Ok(val) = s.parse::<i32>() {
            let p = Primitive::I32(val);
            let _ = p.clone();
            let _ = p == p.clone();
            let _ = format!("{:?}", p);
        }
        if let Ok(val) = s.parse::<i64>() {
            let p = Primitive::I64(val);
            let _ = p.clone();
            let _ = p == p.clone();
            let _ = format!("{:?}", p);
        }
        if let Ok(val) = s.parse::<u32>() {
            let p = Primitive::U32(val);
            let _ = p.clone();
            let _ = p == p.clone();
            let _ = format!("{:?}", p);
        }
        if let Ok(val) = s.parse::<u64>() {
            let p = Primitive::U64(val);
            let _ = p.clone();
            let _ = p == p.clone();
            let _ = format!("{:?}", p);
        }
        if let Ok(val) = s.parse::<f64>() {
            let p = Primitive::F64(val);
            let _ = p.clone();
            let _ = p == p.clone();
            let _ = format!("{:?}", p);
        }
        if let Ok(val) = s.parse::<bool>() {
            let p = Primitive::Bool(val);
            let _ = p.clone();
            let _ = p == p.clone();
            let _ = format!("{:?}", p);
        }
    }
});
