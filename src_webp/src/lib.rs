use std::ffi::CStr;
use std::os::raw::{c_char, c_int, c_void};
use std::fs;
use std::panic;
use std::slice;

unsafe extern "C" {
    fn WebPGetInfo(data: *const u8, data_size: usize, width: *mut c_int, height: *mut c_int) -> c_int;
    fn WebPDecodeBGRA(data: *const u8, data_size: usize, width: *mut c_int, height: *mut c_int) -> *mut u8;
    fn WebPFree(ptr: *mut c_void);
}

#[unsafe(no_mangle)]
pub extern "C" fn get_webp_info(path_ptr: *const c_char, width_ptr: *mut c_int, height_ptr: *mut c_int) -> c_int {
    let result = panic::catch_unwind(|| {
        let path_cstr = unsafe { CStr::from_ptr(path_ptr) };
        let path = match path_cstr.to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        };
        let file_data = match fs::read(path) {
            Ok(data) => data,
            Err(_) => return -1,
        };
        let mut width: c_int = 0;
        let mut height: c_int = 0;
        let success = unsafe { WebPGetInfo(file_data.as_ptr(), file_data.len(), &mut width, &mut height) };
        if success == 1 {
            unsafe {
                *width_ptr = width;
                *height_ptr = height;
            }
            0
        } else {
            -1
        }
    });
    result.unwrap_or(-1)
}

#[unsafe(no_mangle)]
pub extern "C" fn decode_webp_to_bitmap(path_ptr: *const c_char, bitmap_ptr: *mut u8, buffer_size: u32) -> c_int {
    let result = panic::catch_unwind(|| {
        let path_cstr = unsafe { CStr::from_ptr(path_ptr) };
        let path = match path_cstr.to_str() {
            Ok(s) => s,
            Err(_) => return -1,
        };
        let file_data = match fs::read(path) {
            Ok(data) => data,
            Err(_) => return -1,
        };
        let mut width: c_int = 0;
        let mut height: c_int = 0;
        
        if unsafe { WebPGetInfo(file_data.as_ptr(), file_data.len(), &mut width, &mut height) } != 1 {
            return -1;
        }
        let decoded_buffer_ptr = unsafe {
            WebPDecodeBGRA(file_data.as_ptr(), file_data.len(), &mut width, &mut height)
        };
        if decoded_buffer_ptr.is_null() {
            return -1;
        }
        let dest_slice = unsafe { slice::from_raw_parts_mut(bitmap_ptr, buffer_size as usize) };
        let src_slice = unsafe { slice::from_raw_parts(decoded_buffer_ptr, buffer_size as usize) };
        let stride = (width * 4) as usize;
        for y in 0..height as usize {
            let src_start = y * stride;
            let src_end = src_start + stride;
            let src_row = &src_slice[src_start..src_end];
            let dest_y = (height as usize) - 1 - y;
            let dest_start = dest_y * stride;
            let dest_end = dest_start + stride;
            let dest_row = &mut dest_slice[dest_start..dest_end];
            dest_row.copy_from_slice(src_row);
        }
        
        unsafe { WebPFree(decoded_buffer_ptr as *mut c_void) };
        0
    });
    result.unwrap_or(-1)
}