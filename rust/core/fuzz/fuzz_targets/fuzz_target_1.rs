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
        let _ = Primitive::String(s.to_string());
        
        // Try to parse as various numeric types
        if let Ok(val) = s.parse::<i32>() {
            let _ = Primitive::I32(val);
        }
        if let Ok(val) = s.parse::<i64>() {
            let _ = Primitive::I64(val);
        }
        if let Ok(val) = s.parse::<u32>() {
            let _ = Primitive::U32(val);
        }
        if let Ok(val) = s.parse::<u64>() {
            let _ = Primitive::U64(val);
        }
        if let Ok(val) = s.parse::<f64>() {
            let _ = Primitive::F64(val);
        }
        if let Ok(val) = s.parse::<bool>() {
            let _ = Primitive::Bool(val);
        }
    }
});
