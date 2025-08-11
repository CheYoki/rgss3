fn main() {
    println!("cargo:rustc-link-search=native=./libwebp/lib");
    println!("cargo:rustc-link-lib=libwebp");
}