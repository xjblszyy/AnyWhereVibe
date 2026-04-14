fn main() {
    println!("cargo:rerun-if-changed=../../proto/mrt.proto");
    println!("cargo:rerun-if-changed=../../proto");

    let protoc = protoc_bin_vendored::protoc_bin_path().expect("failed to locate protoc");
    std::env::set_var("PROTOC", protoc);

    prost_build::compile_protos(&["../../proto/mrt.proto"], &["../../proto/"]).unwrap();
}
